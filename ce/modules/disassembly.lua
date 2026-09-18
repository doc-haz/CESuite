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
function M.capture(api,address,arch)
  local result={address=U.hex(address),boundary='unverified_candidate',bytes=U.array(),instructions=U.array(),status='partial'}
  result.bytes_start=U.hex(math.max(0,address-16));result.bytes_requested=48
  local bytes,err=U.call(api,'readBytes',math.max(0,address-16),48,true)
  if type(bytes)=='table' then result.bytes=U.array(bytes) else result.read_error=err or 'Bytes unavailable' end
  local d
  local ok,failure=xpcall(function()
    d=assert(api.createDisassembler(),'Disassembler unavailable')
    local cursor=address
    for _=1,8 do
      local text=d.disassemble(cursor)
      local data=d.getLastDisassembleData()
      assert(type(data)=='table' and type(data.bytes)=='table' and #data.bytes>0,'Instruction metadata unavailable')
      local ins={address=U.hex(cursor),text=text or '',opcode=data.opcode or '',parameters=data.parameters or '',
        bytes=U.array(data.bytes),length=#data.bytes,branch='unknown',rip_relative=M.rip(data.bytes,arch),
        classification='CE metadata and limited byte decoder; not relocation validation'}
      if data.isCall then ins.branch='call'
      elseif data.isRet then ins.branch='return'
      elseif data.isConditionalJump then ins.branch='conditional_jump'
      elseif data.isJump then ins.branch='jump'
      elseif data.isJump==false and data.isCall==false and data.isRet==false then ins.branch='none' end
      if data.parameterValueType==1 then ins.parameter_address=U.hex(data.parameterValue) end
      if data.modrmValueType==1 then ins.memory_operand_address=U.hex(data.modrmValue) end
      result.instructions[#result.instructions+1]=ins
      cursor=cursor+#data.bytes
    end
    result.status=#result.bytes==48 and 'captured' or 'partial'
  end,function(e) return tostring(e) end)
  if d then pcall(function() d.destroy() end) end
  if not ok then result.disassembly_error=failure end
  return result
end
return M
