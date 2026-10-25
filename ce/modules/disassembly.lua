local U=require('util')
local M={}
-- CE does not document a universal RIP-relative flag. Recognize only selected
-- legacy one-byte opcodes whose ModRM position is known; all others stay unknown.
function M.rip(bytes,arch)
  if arch=='x86' then return 'not_applicable' end
  if arch~='x64' then return 'unknown' end
  local i,addressOverride=1,false
  while bytes[i] do
    local b=bytes[i]
    if b==0x67 then addressOverride=true;i=i+1
    elseif b==0x66 or b==0xF0 or b==0xF2 or b==0xF3 or b==0x2E or b==0x36 or b==0x3E or b==0x26 or b==0x64 or b==0x65 or (b>=0x40 and b<=0x4F) then i=i+1
    else break end
  end
  local op=bytes[i]
  local known={[0x8B]=true,[0x89]=true,[0x8D]=true,[0x8A]=true,[0x88]=true,[0xFF]=true,[0xC7]=true,[0xC6]=true,
    [0x01]=true,[0x03]=true,[0x29]=true,[0x2B]=true,[0x39]=true,[0x3B]=true,[0x85]=true}
  local modrm=bytes[i+1]
  if not known[op] or not modrm then return 'unknown' end
  if addressOverride then return 'not_rip_relative' end
  return modrm<0x40 and modrm%8==5 and 'rip_relative' or 'not_rip_relative'
end
-- Compatibility stub: CE disassembly can invoke global overrides/callbacks.
-- Omit optional context without accessing CE APIs.
function M.capture(api,address,arch)
  return nil
end

-- Conservative decoder from raw bytes. It never calls Cheat Engine disassembly,
-- never executes target code and never guesses an unsupported opcode.
-- Operand size is tracked in BITS; helpers derive bytes where needed, so an
-- 8-bit operand can never be mistaken for an 8-byte register.
local REG64={'rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi',
  'r8','r9','r10','r11','r12','r13','r14','r15'}
local REG32={'eax','ecx','edx','ebx','esp','ebp','esi','edi',
  'r8d','r9d','r10d','r11d','r12d','r13d','r14d','r15d'}
local REG16={'ax','cx','dx','bx','sp','bp','si','di',
  'r8w','r9w','r10w','r11w','r12w','r13w','r14w','r15w'}
-- Without REX, ModRM indexes 4-7 address ah/ch/dh/bh; any REX prefix (even one
-- without bits) redirects them to spl/bpl/sil/dil.
local REG8={'al','cl','dl','bl','ah','ch','dh','bh',
  'r8b','r9b','r10b','r11b','r12b','r13b','r14b','r15b'}
local REG8_REX={'al','cl','dl','bl','spl','bpl','sil','dil',
  'r8b','r9b','r10b','r11b','r12b','r13b','r14b','r15b'}
local XMM={'xmm0','xmm1','xmm2','xmm3','xmm4','xmm5','xmm6','xmm7',
  'xmm8','xmm9','xmm10','xmm11','xmm12','xmm13','xmm14','xmm15'}

local SSE_SINGLE={[0x10]='movss',[0x11]='movss',[0x2E]='ucomiss',[0x2F]='comiss',
  [0x58]='addss',[0x59]='mulss',[0x5C]='subss',[0x5E]='divss'}
local SSE_DOUBLE={[0x10]='movsd',[0x11]='movsd',[0x2E]='ucomisd',[0x2F]='comisd',
  [0x58]='addsd',[0x59]='mulsd',[0x5C]='subsd',[0x5E]='divsd'}

local OP1={
  [0x01]={name='add',form='rm,reg'},
  [0x03]={name='add',form='reg,rm'},
  [0x09]={name='or',form='rm,reg'},
  [0x0B]={name='or',form='reg,rm'},
  [0x21]={name='and',form='rm,reg'},
  [0x23]={name='and',form='reg,rm'},
  [0x29]={name='sub',form='rm,reg'},
  [0x2B]={name='sub',form='reg,rm'},
  [0x31]={name='xor',form='rm,reg'},
  [0x33]={name='xor',form='reg,rm'},
  [0x39]={name='cmp',form='rm,reg'},
  [0x3B]={name='cmp',form='reg,rm'},
  [0x85]={name='test',form='rm,reg'},
  [0x88]={name='mov',form='rm,reg',bits=8},
  [0x89]={name='mov',form='rm,reg'},
  [0x8A]={name='mov',form='reg,rm',bits=8},
  [0x8B]={name='mov',form='reg,rm'},
  [0x8D]={name='lea',form='reg,mem'},
  [0xC6]={name='mov',form='rm,imm',bits=8,imm=1},
  [0xC7]={name='mov',form='rm,imm',imm=4},
  [0x63]={name='movsxd',form='reg,rm',x64only=true}
}
local X87={[0xD9]=32,[0xDD]=64}
local X87_GROUP={[0]='fld',[2]='fst',[3]='fstp'}

local function is64(arch) return arch=='x86_64' or arch=='x64' end
local function is32(arch) return arch=='i386' or arch=='x86' end

local function bytesAt(bytes,i,n)
  for k=0,n-1 do if bytes[i+k]==nil then return false end end
  return true
end

local function readSigned(bytes,i,size)
  if not bytesAt(bytes,i,size) then return nil end
  if size==1 then
    local v=bytes[i]
    if v>=0x80 then v=v-256 end
    return v
  end
  local v=0
  for k=size-1,0,-1 do v=v*256+bytes[i+k] end
  if v>=0x80000000 then v=v-0x100000000 end
  return v
end

local function readUnsigned(bytes,i,size)
  if not bytesAt(bytes,i,size) then return nil end
  local v=0
  for k=size-1,0,-1 do v=v*256+bytes[i+k] end
  return v
end

-- 8-bit register naming depends on the mere presence of any REX prefix.
local function gpr8(index,has_rex)
  if index<4 then return REG8[index+1] end
  if index<8 then return has_rex and REG8_REX[index+1] or REG8[index+1] end
  return REG8[index+1] or 'r8b'
end

local function gpr(index,bits,is64bit,addr32,has_rex)
  if bits==8 then return gpr8(index,has_rex) end
  if not is64bit or addr32 then
    if bits==16 then return REG16[index+1] or REG16[1] end
    return REG32[index+1] or REG32[1]
  end
  if bits==16 then return REG16[index+1] or REG16[1] end
  if bits==64 then return REG64[index+1] or REG64[1] end
  return REG32[index+1] or REG32[1]
end

-- Address registers are pointer sized (32-bit with 0x67 in 64-bit mode).
local function addrReg(index,is64bit,addr32)
  if is64bit and not addr32 then return REG64[index+1] or REG64[1] end
  return REG32[index+1] or REG32[1]
end

local function sizePrefix(bits)
  if bits==8 then return 'byte ptr ' end
  if bits==16 then return 'word ptr ' end
  if bits==32 then return 'dword ptr ' end
  if bits==64 then return 'qword ptr ' end
  return ''
end

local function memText(mem)
  if mem.absolute then return string.format('[0x%X]',mem.displacement) end
  local parts={}
  if mem.rip_relative then parts[#parts+1]='rip'
  elseif mem.base_register then parts[#parts+1]=mem.base_register end
  if mem.index_register then
    parts[#parts+1]=mem.scale and mem.scale~=1
      and (mem.index_register..'*'..tostring(mem.scale)) or mem.index_register
  end
  local disp=mem.displacement or 0
  if #parts==0 then return string.format('[0x%X]',disp) end
  local text='['..table.concat(parts,'+')
  if disp<0 then text=text..string.format('-0x%X',-disp)
  elseif disp>0 then text=text..string.format('+0x%X',disp) end
  return text..']'
end

local function emptyMemory()
  return {present=false,base_register=nil,index_register=nil,scale=nil,displacement=nil,
    rip_relative=false,absolute=false,expression_text=nil,is_stack_reference=false}
end

-- SSE mnemonic and operand size in bits. 0F 10/11/28/29 differentiate on
-- 66 (packed double), F3 (scalar single) and F2 (scalar double).
local function sseMnemonic(pfx,op2)
  if op2==0x10 or op2==0x11 then
    if pfx[0xF3] then return 'movss',32 end
    if pfx[0xF2] then return 'movsd',64 end
    if pfx[0x66] then return 'movupd',128 end
    return 'movups',128
  end
  if op2==0x28 or op2==0x29 then
    if pfx[0xF3] or pfx[0xF2] then return nil end
    if pfx[0x66] then return 'movapd',128 end
    return 'movaps',128
  end
  if op2==0x58 or op2==0x59 or op2==0x5C or op2==0x5E then
    if pfx[0xF3] then return SSE_SINGLE[op2],32 end
    if pfx[0xF2] then return SSE_DOUBLE[op2],64 end
    return nil
  end
  if op2==0x2E or op2==0x2F then
    if pfx[0xF2] or pfx[0x66] then return SSE_DOUBLE[op2],64 end
    return SSE_SINGLE[op2],32
  end
  return nil
end

-- Reported status values: decoded | unsupported | truncated | invalid.
function M.decode(bytes,arch)
  local is64bit,is32bit=is64(arch),is32(arch)
  if not (is64bit or is32bit) then
    return {status='unsupported',reason='unsupported_architecture'}
  end
  if type(bytes)~='table' or #bytes==0 then
    return {status='invalid',reason='no_bytes'}
  end
  local i,prefixes,pfx=1,{}, {}
  while true do
    local b=bytes[i]
    if b==nil then return {status='truncated',reason='prefix_only'} end
    if b==0x66 or b==0x67 or b==0xF0 or b==0xF2 or b==0xF3 or b==0x2E or b==0x36
      or b==0x3E or b==0x26 or b==0x64 or b==0x65 then
      prefixes[#prefixes+1]=b;pfx[b]=true;i=i+1
    elseif is64bit and b>=0x40 and b<=0x4F then
      prefixes[#prefixes+1]=b;pfx.rex=b;i=i+1
    else break end
  end
  local op=bytes[i]
  if op==nil then return {status='truncated',reason='missing_opcode'} end
  if is32bit and pfx[0x67] then
    return {status='unsupported',reason='unsupported_address_size'}
  end
  local rex=pfx.rex
  local rex_w=rex and (rex & 0x8)~=0
  local rex_r=rex and (rex & 0x4)~=0
  local rex_x=rex and (rex & 0x2)~=0
  local rex_b=rex and (rex & 0x1)~=0
  local has_rex=rex~=nil
  local addr32=pfx[0x67]==true
  local result={status='decoded',reason=nil,length=nil,prefixes=prefixes,opcode=op,
    opcode_text=nil,modrm=nil,sib=nil,displacement=nil,operand_size=nil,
    mnemonic=nil,operands_text=nil,rip_relative=false,memory=emptyMemory()}
  local prefix_text={}
  for _,b in ipairs(prefixes) do prefix_text[#prefix_text+1]=string.format('%02X',b) end
  prefix_text=table.concat(prefix_text,' ')

  local mnemonic,form,imm_size,bits,sse_store
  if op==0x0F then
    local op2=bytes[i+1]
    if op2==nil then result.status='truncated';result.reason='missing_second_opcode';return result end
    result.opcode_text=(prefix_text~='' and (prefix_text..' ') or '')..string.format('0F %02X',op2)
    mnemonic,bits=sseMnemonic(pfx,op2)
    if mnemonic==nil then
      result.status='unsupported';result.reason='unsupported_opcode';return result
    end
    form='sse';sse_store=(op2==0x11 or op2==0x29);i=i+2
  elseif X87[op] then
    bits=X87[op];form='x87';i=i+1
  elseif OP1[op] then
    local info=OP1[op]
    if info.x64only and not is64bit then
      result.status='unsupported';result.reason='unsupported_opcode';return result
    end
    mnemonic=info.name;form=info.form;imm_size=info.imm;i=i+1
    -- Byte opcodes (88/8A/C6) are always 8 bits; 66/REX.W do not change them.
    -- Other opcodes use REX.W (64), 66 (16) or the default 32.
    bits=info.bits or (rex_w and 64 or (pfx[0x66] and 16 or 32))
    if form=='rm,imm' and imm_size and imm_size>1 then
      imm_size=pfx[0x66] and 2 or 4
    end
  else
    result.status='unsupported';result.reason='unsupported_opcode';return result
  end
  result.opcode_text=result.opcode_text or
    ((prefix_text~='' and (prefix_text..' ') or '')..string.format('%02X',op))

  local modrm=bytes[i]
  if modrm==nil then result.status='truncated';result.reason='missing_modrm';return result end
  result.modrm=modrm
  local mod=modrm>>6
  local reg_ext=((modrm>>3)&7)
  local reg=reg_ext+(rex_r and 8 or 0)
  local rm=((modrm&7))+(rex_b and 8 or 0)
  local pos=i+1
  local mem=emptyMemory()
  local rm_name,reg_name

  if form=='x87' then
    if mod==3 then
      result.status='unsupported';result.reason='x87_register_form';return result
    end
    mnemonic=X87_GROUP[reg_ext]
    if mnemonic==nil then
      result.status='unsupported';result.reason='unsupported_x87_group';return result
    end
    result.operand_size=bits
  elseif form=='sse' then
    reg_name=XMM[reg+1]
    if mod~=3 then rm_name=nil else rm_name=XMM[rm+1] end
  elseif form=='reg,mem' and mod==3 then
    result.status='unsupported';result.reason='lea_register_operand';return result
  elseif form=='rm,imm' then
    reg_name=nil
    rm_name=(mod==3) and gpr(rm,bits,is64bit,addr32,has_rex) or nil
  else
    reg_name=gpr(reg,bits,is64bit,addr32,has_rex)
    rm_name=(mod==3) and gpr(rm,bits,is64bit,addr32,has_rex) or nil
  end

  if mod~=3 then
    mem.present=true
    local rm_low=modrm&7
    local disp_size=0
    if rm_low==4 then
      local sib=bytes[pos]
      if sib==nil then result.status='truncated';result.reason='missing_sib';return result end
      result.sib=sib;pos=pos+1
      local scale=math.floor(2^(sib>>6))
      local index=((sib>>3)&7)+(rex_x and 8 or 0)
      local base=(sib&7)+(rex_b and 8 or 0)
      if not (index==4 and not rex_x) then
        mem.index_register=addrReg(index,is64bit,addr32)
        mem.scale=scale
      end
      if (sib&7)==5 and mod==0 then
        mem.displacement=readSigned(bytes,pos,4)
        if mem.displacement==nil then result.status='truncated';result.reason='missing_displacement';return result end
        pos=pos+4
        if mem.index_register==nil then mem.absolute=true end
      else
        mem.base_register=addrReg(base,is64bit,addr32)
        disp_size=(mod==1) and 1 or ((mod==2) and 4 or 0)
      end
    elseif rm_low==5 and mod==0 then
      mem.displacement=readSigned(bytes,pos,4)
      if mem.displacement==nil then result.status='truncated';result.reason='missing_displacement';return result end
      pos=pos+4
      if is64bit and not addr32 then mem.rip_relative=true else mem.absolute=true end
    else
      mem.base_register=addrReg(rm_low,is64bit,addr32)
      disp_size=(mod==1) and 1 or ((mod==2) and 4 or 0)
    end
    if disp_size>0 and mem.displacement==nil then
      mem.displacement=readSigned(bytes,pos,disp_size)
      if mem.displacement==nil then result.status='truncated';result.reason='missing_displacement';return result end
      pos=pos+disp_size
    end
    if mem.base_register then
      local base=mem.base_register:lower()
      mem.is_stack_reference=(base=='rsp' or base=='rbp' or base=='esp' or base=='ebp')
    end
    mem.expression_text=memText(mem)
    result.memory=mem
    result.displacement=mem.displacement
    result.rip_relative=mem.rip_relative
  end

  local immediate
  if imm_size then
    immediate=readUnsigned(bytes,pos,imm_size)
    if immediate==nil then result.status='truncated';result.reason='missing_immediate';return result end
    pos=pos+imm_size
  end
  result.length=pos-1
  result.mnemonic=mnemonic
  result.operand_size=bits
  if form=='sse' then
    result.operands_text=(mod==3)
      and ((sse_store and rm_name or reg_name)..', '..(sse_store and reg_name or rm_name))
      or ((sse_store and (mem.expression_text..', '..tostring(reg_name)))
        or (tostring(reg_name)..', '..mem.expression_text))
  elseif form=='x87' then
    result.operands_text=sizePrefix(bits)..mem.expression_text
  else
    local left,right
    if mod==3 then
      if form=='rm,imm' then left,right=rm_name,'imm'
      elseif form=='rm,reg' then left,right=rm_name,reg_name
      else left,right=reg_name,rm_name end
    elseif form=='rm,imm' then
      left,right=sizePrefix(bits)..mem.expression_text,'imm'
    elseif form=='rm,reg' then
      left,right=mem.expression_text,reg_name
    else
      left,right=reg_name,mem.expression_text
    end
    local imm_text=(immediate and string.format('0x%X',immediate)) or 'imm'
    if form=='rm,imm' then right=imm_text end
    result.operands_text=table.concat({tostring(left),tostring(right)},', ')
  end
  return result
end

return M
