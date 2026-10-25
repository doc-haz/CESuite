package.path='ce/modules/?.lua;'..package.path
-- Address Evidence Inspector tests. Synthetic CE objects only; no target access.
local U=require('util')
local A=require('address')
local D=require('disassembly')
local Export=require('exporter')

local tests=0
local function test(name,fn)
  fn()
  tests=tests+1
  print('PASS '..name)
end
local function eq(actual,expected,label)
  assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..
    ' got '..tostring(actual))
end
local function neq(actual,expected,label)
  assert(actual~=expected,(label or 'value')..': expected not '..tostring(expected)..
    ' got '..tostring(actual))
end

local DEFAULT_BYTES={0x48,0x8B,0x05,0x10,0x00,0x00,0x00}

local function defaultModules()
  return {
    {Name='game.exe',Address=0x140000000,PathToFile='C:/g/game.exe',Is64Bit=true},
    {Name='other.dll',Address=0x7FF800000000,PathToFile='C:/g/other.dll',Is64Bit=true}
  }
end

local function mock(opts)
  opts=opts or {}
  local calls={getAddress=0,getAddressSafe=0,disassemble=0,debug=0,writes=0,pid=0}
  local api={
    process='game.exe',
    getOpenedProcessID=function()
      calls.pid=calls.pid+1
      if opts.pid_change and calls.pid>1 then return 8 end
      return opts.pid or 7
    end,
    targetIs64Bit=function()
      if opts.no_arch then return nil end
      return opts.x64~=false
    end,
    enumModules=function() return opts.modules or defaultModules() end,
    getModuleSize=function(name)
      if opts.no_size then return nil end
      if name=='game.exe' then return 0x100000 end
      if name=='other.dll' then return 0x2000 end
      if name=='dup.dll' then return 0x1000 end
      return nil
    end,
    readBytes=function(addr,count)
      if opts.read_fail then return nil end
      local pattern=opts.bytes or DEFAULT_BYTES
      local limit=count
      if opts.short then limit=math.min(limit,opts.short) end
      if opts.fail_after and opts.fail_after<limit then limit=opts.fail_after end
      local data={}
      for i=1,limit do data[i]=pattern[i] or 0 end
      return data
    end,
    getAddress=function() calls.getAddress=calls.getAddress+1;return 0 end,
    getAddressSafe=function() calls.getAddressSafe=calls.getAddressSafe+1;return 0 end,
    disassemble=function() calls.disassemble=calls.disassemble+1;return '' end,
    debug_setBreakpoint=function() calls.debug=calls.debug+1 end,
    writeBytes=function() calls.writes=calls.writes+1 end
  }
  if opts.region_api~=false then
    api.getMemoryRegionInfo=function(address)
      if opts.no_region then return nil end
      if opts.region_error then return nil end
      return {BaseAddress=opts.region_base or 0x140001000,
        RegionSize=opts.region_size or 0x1000,
        AllocationBase=opts.region_alloc or 0x140000000,
        State=opts.state or 0x1000,
        Type=opts.region_type or 0x1000000,
        Protect=opts.protect or 0x20,
        AllocationProtect=opts.alloc_protect or 0x04}
    end
  end
  if opts.enum_regions then
    api.enumMemoryRegions=function() return opts.enum_regions end
  end
  return api,calls
end

local function inspect(input,opts)
  local api=opts and opts.api or mock(opts)
  return A.inspect(api,input,opts),api
end

local function rules(evidence)
  local out={}
  for _,d in ipairs(evidence.diagnostics) do out[d.rule]=d end
  return out
end

-- Address input ------------------------------------------------------------
test('hex literals resolve with and without 0x prefix',function()
  eq(A.parseInput('401000').status,'resolved')
  eq(A.parseInput('0x401000').address,0x401000)
  eq(A.parseInput('140001000').address,0x140001000)
  local ev=inspect('0x140001000')
  eq(ev.query.resolution_method,'hex_literal')
  eq(ev.query.resolution_status,'resolved')
  eq(ev.query.resolved_address,'0x140001000')
end)

test('invalid and empty input stay invalid, never resolved',function()
  for _,value in ipairs({'','   ','hello world','0x','0xZZ','@@'}) do
    local parsed=A.parseInput(value)
    eq(parsed.status,'invalid_input','input '..tostring(value))
  end
  local ev=inspect('not-an-address')
  eq(ev.status,'unknown')
  eq(ev.query.resolution_status,'invalid_input')
  eq(ev.query.resolved_address,U.null)
  assert(type(ev.query.failure_reason)=='string','failure reason expected')
end)

test('oversized hexadecimal values are out of range',function()
  eq(A.parseInput('0x1FFFFFFFFFFFFFFFF').status,'out_of_range')
  eq(A.parseInput('FFFFFFFFFFFFFFFF').status,'out_of_range')
  local ev=inspect('0x1FFFFFFFF',{x64=false})
  eq(ev.query.resolution_status,'out_of_range')
end)

test('module+RVA resolves through the module inventory',function()
  local parsed=A.parseInput('game.exe+123456')
  eq(parsed.kind,'module_rva')
  eq(parsed.rva,0x123456)
  local ev=inspect('game.exe+0x1000')
  eq(ev.query.resolution_status,'resolved')
  eq(ev.query.resolved_address,'0x140001000')
  eq(ev.query.resolution_method,'module_rva')
  eq(ev.module.inside_module,true)
  eq(ev.module.module_name,'game.exe')
  eq(ev.module.module_base,'0x140000000')
  eq(ev.module.rva,'0x1000')
end)

test('missing module is unresolved, not guessed',function()
  local ev=inspect('nope.dll+10')
  eq(ev.query.resolution_status,'unresolved_module')
  eq(ev.query.resolved_address,U.null)
  eq(ev.module.inside_module,U.null)
end)

test('ambiguous module names are not resolved silently',function()
  local modules={
    {Name='dup.dll',Address=0x10000000,PathToFile='C:/a/dup.dll'},
    {Name='dup.dll',Address=0x20000000,PathToFile='C:/b/dup.dll'}
  }
  local ev=inspect('dup.dll+10',{modules=modules})
  eq(ev.query.resolution_status,'ambiguous_module')
  eq(ev.query.resolved_address,U.null)
  eq(#ev.module.ambiguity,2)
end)

test('RVA beyond the known module size is out of range',function()
  local ev=inspect('game.exe+200000')
  eq(ev.query.resolution_status,'out_of_range')
end)

test('module without a base cannot resolve module+RVA',function()
  local modules={{Name='game.exe',Address=nil,PathToFile='C:/g/game.exe'}}
  local ev=inspect('game.exe+10',{modules=modules})
  eq(ev.query.resolution_status,'unavailable')
end)

test('numeric Memory Viewer selection is accepted',function()
  local ev=inspect(0x140001000)
  eq(ev.query.resolution_method,'memory_viewer_selection')
  eq(ev.query.resolution_status,'resolved')
  eq(ev.query.resolved_address,'0x140001000')
end)

-- Target / module ----------------------------------------------------------
test('detached target yields partial evidence without failing',function()
  local api,calls=mock({pid=0})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.target.attached,false)
  eq(ev.target.status,'unknown')
  eq(ev.target.process_name,U.null)
  eq(ev.status,'unknown')
  eq(ev.query.resolution_status,'resolved')
  eq(ev.region.status,'unknown')
  eq(ev.bytes.read_status,'read_failed')
  assert(rules(ev).TARGET_UNAVAILABLE,'TARGET_UNAVAILABLE diagnostic expected')
  eq(calls.writes,0)
  eq(calls.debug,0)
end)

test('stale PID and cached process name do not prove attachment',function()
  local api=mock({pid=7,modules={}})
  local ev=A.inspect(api,'0x15017F400',{})
  eq(ev.target.attached,false)
  eq(ev.target.status,'detached')
  eq(ev.target.process_name,U.null,'cached process name must not be reused')
  eq(ev.target.provenance,'unavailable')
  eq(ev.status,'unknown')
  -- Hex resolution stays syntactic, independent of the target state.
  eq(ev.query.resolution_status,'resolved')
  eq(ev.query.resolved_address,'0x15017F400')
  eq(ev.module.status,'unknown')
  eq(ev.region.status,'unknown')
  eq(ev.bytes.read_status,'read_failed')
  assert(rules(ev).TARGET_DETACHED,'TARGET_DETACHED diagnostic expected')
  assert(not rules(ev).OUTSIDE_MODULE,'OUTSIDE_MODULE must not be observed')
  assert(not rules(ev).UNMAPPED_ADDRESS,'UNMAPPED_ADDRESS must not be observed')
end)

test('failed module inventory is detached even with a cached PID',function()
  local api=mock({pid=7})
  api.enumModules=function() return nil end
  local ev=A.inspect(api,'0x15017F400',{})
  eq(ev.target.attached,false)
  eq(ev.target.status,'detached')
  eq(ev.query.resolution_status,'resolved')
  assert(rules(ev).TARGET_DETACHED,'TARGET_DETACHED diagnostic expected')
end)

test('module-relative resolution needs a live target',function()
  local api=mock({pid=7,modules={}})
  local ev=A.inspect(api,'game.exe+10',{})
  eq(ev.target.status,'detached')
  eq(ev.query.resolution_status,'unavailable')
  assert(ev.query.failure_reason:find('live target',1,true),'expected live-target reason')
end)

test('a live target with unreadable bytes stays attached',function()
  local ev=inspect('0x140001000',{read_fail=true})
  eq(ev.target.attached,true)
  eq(ev.target.status,'observed')
  eq(ev.bytes.read_status,'read_failed')
  eq(ev.bytes.status,'unknown')
end)

test('module membership needs a provable range',function()
  local ev=inspect('0x140001000',{no_size=true})
  eq(ev.module.inside_module,U.null)
  eq(ev.module.status,'unknown')
end)

test('address outside every module is reported as outside',function()
  local ev=inspect('0x7FF000000000')
  eq(ev.module.inside_module,false)
  assert(rules(ev).OUTSIDE_MODULE,'OUTSIDE_MODULE diagnostic expected')
end)

test('process change during inspection invalidates the result',function()
  local api=mock({pid_change=true})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.status,'invalidated')
  eq(ev.bytes.status,'invalidated')
  eq(ev.instruction.status,'invalidated')
  assert(rules(ev).PROCESS_CHANGED,'PROCESS_CHANGED diagnostic expected')
end)

-- Region / protection ------------------------------------------------------
local function protectCase(value)
  return inspect('0x140001000',{protect=value})
end

test('protection flags decode to readable/writable/executable',function()
  local cases={
    {0x02,true,false,false,'READONLY'},
    {0x04,true,true,false,'READWRITE'},
    {0x08,true,true,false,'WRITECOPY'},
    {0x10,false,false,true,'EXECUTE'},
    {0x20,true,false,true,'EXECUTE_READ'},
    {0x40,true,true,true,'EXECUTE_READWRITE'},
    {0x80,true,true,true,'EXECUTE_WRITECOPY'},
  }
  for _,case in ipairs(cases) do
    local ev=protectCase(case[1])
    eq(ev.region.readable,case[2],'readable 0x'..string.format('%X',case[1]))
    eq(ev.region.writable,case[3],'writable 0x'..string.format('%X',case[1]))
    eq(ev.region.executable,case[4],'executable 0x'..string.format('%X',case[1]))
    assert(ev.region.protect_text:find(case[5],1,true),'protect text '..case[5])
    eq(ev.region.protect_raw,case[1])
  end
end)

test('guard and no-access pages are represented exactly',function()
  local guard=protectCase(0x104)
  eq(guard.region.guard,true)
  eq(guard.region.protect_text,'READWRITE | GUARD')
  assert(rules(guard).GUARD_PAGE,'GUARD_PAGE diagnostic expected')
  local noaccess=protectCase(0x01)
  eq(noaccess.region.readable,false)
  eq(noaccess.region.protect_text,'NOACCESS')
end)

test('region API is preferred over enumeration',function()
  local api,calls=mock({enum_regions={{BaseAddress=0x1000,RegionSize=0x1000,Protect=0x04}}})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.region.region_source,'ce_region_api')
  eq(ev.region.mapped,true)
end)

test('enumeration fallback is bounded and marked',function()
  local api=mock({region_api=false,
    enum_regions={{BaseAddress=0x140000000,RegionSize=0x200000,Protect=0x04,State=0x1000}}})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.region.region_source,'enumerated_regions')
  eq(ev.region.mapped,true)
  eq(ev.region.readable,true)
  eq(ev.limits.regions_enumerated,1)
end)

test('missing region is reported as unmapped, not invented',function()
  local ev=inspect('0x140001000',{no_region=true})
  eq(ev.region.mapped,false)
  eq(ev.region.base_address,U.null)
  assert(rules(ev).UNMAPPED_ADDRESS,'UNMAPPED_ADDRESS diagnostic expected')
end)

-- Bytes --------------------------------------------------------------------
test('bounded byte read reports exact length and hex',function()
  local ev=inspect('0x140001000')
  eq(ev.bytes.read_status,'read_ok')
  eq(ev.bytes.read_length,32)
  eq(ev.bytes.requested_length,32)
  eq(ev.bytes.is_partial,false)
  eq(ev.bytes.hex,'48 8B 05 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00')
end)

test('requested length is capped at 64 bytes',function()
  local ev=inspect('0x140001000',{bytes=1024})
  eq(ev.bytes.requested_length,64)
  eq(ev.limits.max_bytes,64)
end)

test('short reads are marked partial and never fatal',function()
  local ev=inspect('0x140001000',{short=4})
  eq(ev.bytes.read_status,'short_read')
  eq(ev.bytes.read_length,4)
  eq(ev.bytes.is_partial,true)
  eq(ev.status,'observed')
  assert(rules(ev).PARTIAL_BYTE_READ,'PARTIAL_BYTE_READ expected')
end)

test('unreadable page skips the read and reports it',function()
  local api,calls=mock({protect=0x01})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.bytes.read_status,'unreadable')
  eq(ev.bytes.read_length,0)
  eq(ev.region.readable,false)
  assert(rules(ev).UNREADABLE_MEMORY,'UNREADABLE_MEMORY expected')
end)

test('read failure is controlled and does not throw',function()
  local api=mock({read_fail=true})
  local ev=A.inspect(api,'0x140001000',{})
  eq(ev.bytes.read_status,'read_failed')
  eq(ev.bytes.read_length,0)
  eq(ev.status,'observed')
end)

test('region boundary limits the read before it crosses into a bad page',function()
  -- 4 bytes remain in the region; ask for 32.
  local api=mock({region_size=5})
  local ev=A.inspect(api,'0x140001000',{bytes=32})
  eq(ev.bytes.requested_length,32)
  eq(ev.bytes.read_length,5)
  eq(ev.bytes.is_partial,true)
  eq(ev.bytes.read_status,'read_ok')
end)

test('page boundary fallback salvages the readable prefix',function()
  -- First full read fails, then one-byte reads fail after 3 bytes.
  local api=mock({})
  local realRead=api.readBytes
  local single=0
  api.readBytes=function(address,count)
    if count>1 then return nil end
    single=single+1
    if single>3 then return nil end
    return realRead(address,1)
  end
  local ev=A.inspect(api,'0x140001000',{bytes=8})
  eq(ev.bytes.read_status,'short_read')
  eq(ev.bytes.read_length,3)
  eq(ev.bytes.is_partial,true)
  assert(rules(ev).PARTIAL_BYTE_READ,'PARTIAL_BYTE_READ expected')
end)

local function operand(bytes,short)
  return inspect('0x140001000',{bytes=bytes,short=short})
end

-- Decoder ------------------------------------------------------------------
local function hx(s)
  local t={}
  for b in s:gmatch('%x%x') do t[#t+1]=tonumber(b,16) end
  return t
end

test('decoder handles a supported x64 instruction',function()
  local d=D.decode(hx('488B0510000000'),'x86_64')
  eq(d.status,'decoded')
  eq(d.length,7)
  eq(d.mnemonic,'mov')
  eq(d.rip_relative,true)
  eq(d.memory.base_register,nil)
  eq(d.memory.expression_text,'[rip+0x10]')
end)

test('decoder reports unsupported and truncated opcodes',function()
  local unsupported=D.decode({0xCC},'x86_64')
  eq(unsupported.status,'unsupported')
  eq(unsupported.reason,'unsupported_opcode')
  local truncated=D.decode({0x48,0x8B},'x86_64')
  eq(truncated.status,'truncated')
  local invalid=D.decode({},'x86_64')
  eq(invalid.status,'invalid')
end)

test('decoder supports x86 absolute and stack operands',function()
  local d=D.decode(hx('8B0500104000'),'i386')
  eq(d.status,'decoded')
  eq(d.memory.absolute,true)
  eq(d.memory.expression_text,'[0x401000]')
  local stack=D.decode(hx('8B4508'),'i386')
  eq(stack.memory.base_register,'ebp')
  eq(stack.memory.is_stack_reference,true)
end)

test('byte opcodes keep an 8-bit operand size and 8-bit registers',function()
  local store=D.decode(hx('8808'),'x86_64')
  eq(store.status,'decoded')
  eq(store.operand_size,8)
  eq(store.operands_text,'[rax], cl')
  local load=D.decode(hx('8A08'),'x86_64')
  eq(load.operand_size,8)
  eq(load.operands_text,'cl, [rax]')
  local imm=D.decode(hx('C60042'),'x86_64')
  eq(imm.operand_size,8)
  eq(imm.operands_text,'byte ptr [rax], 0x42')
  eq(imm.length,3)
  local inspected=operand({0x88,0x08})
  eq(inspected.instruction.operand_size,8)
  eq(inspected.instruction.operands_text,'[rax], cl')
  eq(inspected.type_advisory.status,'not_applicable')
end)

test('8-bit registers follow REX semantics',function()
  eq(D.decode(hx('88C8'),'x86_64').operands_text,'al, cl')
  eq(D.decode(hx('88D0'),'x86_64').operands_text,'al, dl')
  eq(D.decode(hx('88C4'),'x86_64').operands_text,'ah, al')
  eq(D.decode(hx('88FC'),'x86_64').operands_text,'ah, bh')
  eq(D.decode(hx('4088C4'),'x86_64').operands_text,'spl, al')
  eq(D.decode(hx('4088F0'),'x86_64').operands_text,'al, sil')
  eq(D.decode(hx('4088C7'),'x86_64').operands_text,'dil, al')
  eq(D.decode(hx('4488C0'),'x86_64').operands_text,'al, r8b')
  eq(D.decode(hx('4188C0'),'x86_64').operands_text,'r8b, al')
  eq(D.decode(hx('4188C4'),'x86_64').operands_text,'r12b, al')
  eq(D.decode(hx('4588C4'),'x86_64').operands_text,'r12b, r8b')
  -- REX.W does not widen a byte opcode.
  eq(D.decode(hx('4888C4'),'x86_64').operand_size,8)
  eq(D.decode(hx('4888C4'),'x86_64').operands_text,'spl, al')
end)

test('byte registers without REX still use ah/ch/dh/bh in i386',function()
  eq(D.decode(hx('88C4'),'i386').operands_text,'ah, al')
  eq(D.decode(hx('8A2424'),'i386').operands_text,'ah, [esp]')
  eq(D.decode(hx('88E0'),'i386').operands_text,'al, ah')
end)

test('SSE 0F 10 and 0F 28 differentiate on 66/F3/F2 prefixes',function()
  eq(D.decode(hx('0F10C1'),'x86_64').mnemonic,'movups')
  eq(D.decode(hx('660F10C1'),'x86_64').mnemonic,'movupd')
  eq(D.decode(hx('F30F10C1'),'x86_64').mnemonic,'movss')
  eq(D.decode(hx('F20F10C1'),'x86_64').mnemonic,'movsd')
  eq(D.decode(hx('0F28C1'),'x86_64').mnemonic,'movaps')
  eq(D.decode(hx('660F28C1'),'x86_64').mnemonic,'movapd')
  eq(D.decode(hx('F30F10C1'),'x86_64').operand_size,32)
  eq(D.decode(hx('F20F10C1'),'x86_64').operand_size,64)
  eq(D.decode(hx('660F10C1'),'x86_64').operand_size,128)
end)

-- Operand model ------------------------------------------------------------

test('operand parsing captures base, index, scale and displacement',function()
  local rax=operand({0x48,0x8B,0x41,0x20})
  eq(rax.memory_operand.base_register,'rcx')
  eq(rax.memory_operand.displacement,0x20)
  eq(rax.memory_operand.is_stack_reference,false)
  local sib=operand({0x48,0x8B,0x04,0x08})
  eq(sib.memory_operand.base_register,'rax')
  eq(sib.memory_operand.index_register,'rcx')
  eq(sib.memory_operand.scale,1)
  local scaled=operand({0x4B,0x8B,0x44,0xC4,0xF0})
  eq(scaled.memory_operand.base_register,'r12')
  eq(scaled.memory_operand.index_register,'r8')
  eq(scaled.memory_operand.scale,8)
  eq(scaled.memory_operand.displacement,-16)
end)

test('stack references are marked without being an error',function()
  local rsp=operand({0x48,0x8B,0x44,0x24,0x28})
  eq(rsp.memory_operand.base_register,'rsp')
  eq(rsp.memory_operand.is_stack_reference,true)
  assert(rules(rsp).STACK_REFERENCE,'STACK_REFERENCE expected')
  local rbp=operand({0x48,0x8B,0x45,0xF0})
  eq(rbp.memory_operand.base_register,'rbp')
  eq(rbp.memory_operand.is_stack_reference,true)
end)

test('instruction without memory operand has an empty operand model',function()
  local ev=operand({0x48,0x89,0xC1}) -- mov rcx, rax
  eq(ev.memory_operand.present,false)
  eq(ev.effective_address.effective_address_status,'unavailable')
end)

-- Effective address --------------------------------------------------------
test('RIP-relative effective address is proven from bytes',function()
  local ev=operand({0x48,0x8B,0x05,0x10,0x00,0x00,0x00})
  eq(ev.effective_address.effective_address_status,'resolved_rip_relative')
  eq(ev.effective_address.effective_address,'0x140001017')
  eq(ev.effective_address.status,'observed')
end)

test('absolute static displacement is resolved, registers are not',function()
  local absolute=operand({0x8B,0x04,0x25,0x00,0x10,0x40,0x00})
  eq(absolute.effective_address.effective_address_status,'resolved_static')
  eq(absolute.effective_address.effective_address,'0x401000')
  local registered=operand({0x48,0x8B,0x41,0x20})
  eq(registered.effective_address.effective_address_status,'requires_runtime_context')
  eq(registered.effective_address.effective_address,U.null)
  assert(rules(registered).REGISTER_DEPENDENT_EFFECTIVE_ADDRESS)
end)

-- Type inference -----------------------------------------------------------
test('type advisory maps SSE and x87 opcodes to candidates',function()
  local movss=operand({0xF3,0x0F,0x10,0x05,0x10,0x00,0x00,0x00})
  eq(movss.type_advisory.suggested_type,'Float')
  eq(movss.type_advisory.status,'candidate')
  eq(movss.type_advisory.confidence,'high')
  local movsd=operand({0xF2,0x0F,0x10,0x0D,0x10,0x00,0x00,0x00})
  eq(movsd.type_advisory.suggested_type,'Double')
  local fld32=operand({0xD9,0x00})
  eq(fld32.type_advisory.suggested_type,'Float')
  eq(fld32.type_advisory.confidence,'medium')
  local fld64=operand({0xDD,0x03})
  eq(fld64.type_advisory.suggested_type,'Double')
end)

test('integer and unsupported instructions are not typed',function()
  local mov=operand({0x48,0x8B,0x41,0x20})
  eq(mov.type_advisory.status,'not_applicable')
  local cmp=operand({0x48,0x39,0x41,0x20})
  eq(cmp.type_advisory.status,'not_applicable')
  local unsupported=operand({0xCC})
  eq(unsupported.type_advisory.status,'unsupported')
  local truncated=operand({0x48,0x8B},2)
  eq(truncated.type_advisory.status,'unknown')
end)

-- Provenance / status ------------------------------------------------------
test('observed bytes never come from inference and candidates never promote',function()
  local ev=inspect('0x140001000')
  eq(ev.bytes.status,'observed')
  eq(ev.bytes.provenance,'runtime_read')
  eq(ev.region.provenance,'ce_region_api')
  local typed=operand({0xF3,0x0F,0x10,0x05,0x10,0x00,0x00,0x00})
  eq(typed.type_advisory.status,'candidate')
  neq(typed.type_advisory.status,'observed')
  eq(typed.instruction.provenance,'static_bytes')
end)

test('unsupported instructions are not fatal errors',function()
  local ev=operand({0xCC})
  eq(ev.instruction.decode_status,'unsupported')
  eq(ev.instruction.status,'unsupported')
  eq(ev.status,'observed')
  assert(rules(ev).UNSUPPORTED_INSTRUCTION,'UNSUPPORTED_INSTRUCTION expected')
end)

test('unknown states keep their reason',function()
  local ev=inspect('0x140001000',{read_fail=true})
  eq(ev.instruction.status,'unknown')
  eq(ev.type_advisory.status,'unknown')
  assert(type(ev.type_advisory.reason)=='string','reason expected')
end)

test('limits and zero active resources are declared',function()
  local ev=inspect('0x140001000')
  eq(ev.limits.max_addresses,1)
  eq(ev.limits.max_bytes,64)
  eq(ev.limits.persistent_timers,0)
  eq(ev.limits.runtime_breakpoints,0)
  eq(ev.limits.memory_writes,0)
end)

test('inspection never calls expression resolution, disassembly or debug APIs',function()
  local api,calls=mock({})
  A.inspect(api,'game.exe+1000',{})
  eq(calls.getAddressSafe,0)
  eq(calls.getAddress,0)
  eq(calls.disassemble,0)
  eq(calls.debug,0)
  eq(calls.writes,0)
end)

test('evidence is deterministic except for timestamps',function()
  local first=A.inspect(mock({}),'0x140001000',{})
  local second=A.inspect(mock({}),'0x140001000',{})
  first.generated_at,second.generated_at=nil,nil
  first.completed_at,second.completed_at=nil,nil
  eq(Export.encode(first),Export.encode(second))
end)

-- Core integration ---------------------------------------------------------
local function loadCore(api)
  return assert(loadfile('ce/CESuite_Core.lua','t',
    setmetatable({api=api,require=require},{__index=_G})))()
end

test('Core.inspectAddress runs explicitly, keeps the guard and exports JSON',function()
  local api=mock({})
  local core=loadCore(api)
  local ev=core.inspectAddress('game.exe+1000')
  eq(core.state.busy,false)
  eq(ev.query.resolution_status,'resolved')
  eq(core.last_address_evidence,ev)
  local path=os.tmpname()..'.json'
  core.exportAddressEvidence(ev,path)
  eq(core.state.busy,false)
  local f=assert(io.open(path,'rb'))
  local json=f:read('*a');f:close()
  os.remove(path)
  assert(json:find('"title":"CESuite Address Evidence"',1,true))
  assert(json:find('"suite_version":"0.2.2"',1,true))
  assert(json:find('"core_version":"0.1.9"',1,true))
end)

test('Core.inspectAddress does not run inside collectReport',function()
  local api=mock({})
  local core=loadCore(api)
  local report=core.analyze('process')
  neq(report.assessment~=nil or report.address_evidence~=nil,true)
  eq(core.state.busy,false)
end)

test('Core version is 0.2.2 and the runtime contract stays 0.1.9',function()
  local core=loadCore(mock({}))
  eq(core.version,'0.2.2')
  local ev=core.inspectAddress('0x140001000')
  eq(ev.core_version,'0.1.9')
  eq(ev.suite_version,'0.2.2')
end)

print(tests..' address tests passed')
