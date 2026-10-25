-- Address Evidence Inspector: explicit, read-only evidence about one address.
-- It never evaluates CE expressions, never writes memory, never sets breakpoints
-- and never runs inside collectReport(). If evidence is unavailable the field
-- stays null and the status says why.
local U=require('util')
local D=require('disassembly')
local M={}

local MAX_BYTES=64
local DEFAULT_BYTES=32
local MAX_MODULE_SIZES=512
local MAX_AMBIGUITY=8

local PROTECT_BASE={[0x01]='NOACCESS',[0x02]='READONLY',[0x04]='READWRITE',
  [0x08]='WRITECOPY',[0x10]='EXECUTE',[0x20]='EXECUTE_READ',
  [0x40]='EXECUTE_READWRITE',[0x80]='EXECUTE_WRITECOPY'}
local PROTECT_MODS={{0x100,'GUARD'},{0x200,'NOCACHE'},{0x400,'WRITECOMBINE'}}
local READABLE={[0x02]=true,[0x04]=true,[0x08]=true,[0x20]=true,[0x40]=true,[0x80]=true}
local WRITABLE={[0x04]=true,[0x08]=true,[0x40]=true,[0x80]=true}
local EXECUTABLE={[0x10]=true,[0x20]=true,[0x40]=true,[0x80]=true}

local FLOAT_MNEMONICS={movss=true,addss=true,subss=true,mulss=true,divss=true,
  comiss=true,ucomiss=true}
local DOUBLE_MNEMONICS={movsd=true,addsd=true,subsd=true,mulsd=true,divsd=true,
  comisd=true,ucomisd=true}

local function s(v) return type(v)=='string' and v or nil end
local function n(v) return type(v)=='number' and v or nil end

-- Input grammar: hex literal, module+RVA, or a numeric Memory Viewer selection.
-- Arbitrary CE expressions are deliberately not accepted.
function M.parseInput(input)
  if type(input)=='number' then
    if input<0 or input~=math.floor(input) then
      return {kind='numeric',status='invalid_input',reason='Numeric address must be a non-negative integer'}
    end
    return {kind='numeric',status='resolved',address=input}
  end
  if type(input)~='string' then
    return {kind='invalid',status='invalid_input',reason='Address input must be a string or number'}
  end
  local text=U.trim(input)
  if text=='' then
    return {kind='invalid',status='invalid_input',reason='Address input is empty'}
  end
  local hex=text:match('^0[xX]([0-9A-Fa-f]+)$') or text:match('^([0-9A-Fa-f]+)$')
  if hex then
    if #hex>16 then
      return {kind='hex',status='out_of_range',reason='Hexadecimal value exceeds 64 bits'}
    end
    local value=tonumber(hex,16)
    if value==nil then
      return {kind='hex',status='invalid_input',reason='Hexadecimal value is not a number'}
    end
    if value<0 then
      return {kind='hex',status='out_of_range',reason='Address exceeds the 64-bit range'}
    end
    return {kind='hex',status='resolved',address=value}
  end
  local module,rva=text:match('^(.+)%+(0[xX][0-9A-Fa-f]+)$')
  if not module then module,rva=text:match('^(.+)%+([0-9A-Fa-f]+)$') end
  if module then
    module=U.trim(module)
    if module=='' then
      return {kind='module_rva',status='invalid_input',reason='Module name is empty'}
    end
    local offset=rva:gsub('^0[xX]','')
    local value=tonumber(offset,16)
    if value==nil or value<0 then
      return {kind='module_rva',status='invalid_input',reason='Module RVA is not a valid hexadecimal offset'}
    end
    return {kind='module_rva',status='resolved',module=module,rva=value}
  end
  return {kind='invalid',status='invalid_input',
    reason='Accepted forms: 0x…, hexadecimal, module+RVA (for example game.exe+0x1234)'}
end

local function pointerSize(api)
  local value,err=U.call(api,'targetIs64Bit')
  if type(value)=='boolean' then return value and 8 or 4 end
  return nil,err
end

local function architecture(api)
  local value=U.call(api,'targetIs64Bit')
  if value==true then return 'x86_64' end
  if value==false then return 'i386' end
  return 'unknown'
end

local function maskFor(size)
  if size==8 then return math.maxinteger end
  if size==4 then return 0xFFFFFFFF end
  return nil
end

local function collectModules(api,limits)
  local list,err=U.call(api,'enumModules')
  if type(list)~='table' then return nil,err or 'enumModules unavailable' end
  local modules={}
  local sizes=0
  for _,m in ipairs(list) do
    if type(m)=='table' then
      local name=s(m.Name) or U.null
      local base=n(m.Address) or n(m.BaseAddress)
      local path=s(m.PathToFile) or s(m.Path) or U.null
      local size=nil
      if type(name)=='string' and sizes<MAX_MODULE_SIZES then
        local value=U.call(api,'getModuleSize',name)
        if type(value)=='number' and value>0 then size=value end
        sizes=sizes+1
      elseif sizes>=MAX_MODULE_SIZES then
        limits.truncated=true
      end
      modules[#modules+1]={name=name,path=path,base=base,size=size,
        norm=(type(name)=='string' and U.moduleNorm(name) or nil),
        norm_path=(type(path)=='string' and U.moduleNorm(path) or nil)}
    end
  end
  return modules
end

local function matchModule(modules,query)
  local q=U.moduleNorm(query)
  if not q then return nil,'invalid module name' end
  local found={}
  local basename=not q:find('/',1,true)
  for _,m in ipairs(modules) do
    local match=(m.norm==q or m.norm_path==q)
    if not match and basename then
      match=(m.norm and m.norm:match('[^/]+$')==q) or (m.norm_path and m.norm_path:match('[^/]+$')==q)
    end
    if match then found[#found+1]=m end
  end
  if #found==0 then return nil,'unresolved module: '..query end
  if #found>1 then return found,'ambiguous module: '..query end
  return found[1],nil
end

local function decodeProtect(raw)
  if type(raw)~='number' then return U.null,nil,nil,nil,nil end
  local base=raw & 0xFF
  local parts={PROTECT_BASE[base] or string.format('0x%X',base)}
  for _,mod in ipairs(PROTECT_MODS) do
    if (raw & mod[1])~=0 then parts[#parts+1]=mod[2] end
  end
  local readable=READABLE[base]==true
  local writable=WRITABLE[base]==true
  local executable=EXECUTABLE[base]==true
  local guard=(raw & 0x100)~=0
  return table.concat(parts,' | '),readable,writable,executable,guard
end

local function regionFromAPI(api,address)
  local info,err=U.call(api,'getMemoryRegionInfo',address)
  if type(info)=='table' then return info,'ce_region_api',nil end
  return nil,'ce_region_api',err
end

local function regionFromEnumeration(api,address)
  local regions,err=U.call(api,'enumMemoryRegions')
  if type(regions)~='table' then return nil,'unavailable',err end
  for _,region in ipairs(regions) do
    local base=n(region.BaseAddress) or n(region.base)
    local size=n(region.RegionSize) or n(region.size)
    if base and size and address>=base and address<base+size then
      return region,'enumerated_regions',nil
    end
  end
  return nil,'enumerated_regions',nil
end

local function bytesHex(bytes)
  local parts={}
  for i=1,#bytes do parts[i]=string.format('%02X',bytes[i] & 0xFF) end
  return table.concat(parts,' ')
end

local function readBytes(api,address,count)
  local data,err=U.call(api,'readBytes',address,count,true)
  if type(data)=='table' then return data,nil end
  return nil,err or 'readBytes unavailable'
end

local function emptyMemoryOperand()
  return {present=false,base_register=U.null,index_register=U.null,scale=U.null,
    displacement=U.null,rip_relative=U.null,absolute=U.null,expression_text=U.null,
    is_stack_reference=U.null,status='unknown',provenance='unavailable'}
end

local function newDiagnostic(rule,severity,status,summary,provenance)
  return {rule=rule,severity=severity,status=status,summary=summary,provenance=provenance}
end

function M.inspect(api, input, options)
  options=options or {}
  local started=os.date('!%Y-%m-%dT%H:%M:%SZ')
  local limits={max_addresses=1,max_bytes=MAX_BYTES,bytes_requested=0,bytes_read=0,
    regions_enumerated=0,truncated=false,persistent_timers=0,runtime_breakpoints=0,memory_writes=0}
  local diagnostics=U.array()
  local parsed=M.parseInput(input)
  local pid=n(api and api.getOpenedProcessID and U.call(api,'getOpenedProcessID'))
  local pid_candidate=type(pid)=='number' and pid>0
  local ptr,ptrErr=pointerSize(api)
  local arch=architecture(api)
  local mask=maskFor(ptr)
  -- A cached PID (and the cached process name) is not proof of attachment.
  -- Require a live, non-empty module inventory before claiming a target.
  local modules,moduleErr
  if pid_candidate then modules,moduleErr=collectModules(api,limits) end
  local attached=pid_candidate and type(modules)=='table' and #modules>0

  local query={input=(type(input)=='number' and string.format('0x%X',input)) or tostring(input or ''),
    input_kind=parsed.kind,
    resolution_method=(parsed.kind=='numeric') and 'memory_viewer_selection'
      or (parsed.kind=='hex' and 'hex_literal')
      or (parsed.kind=='module_rva' and 'module_rva') or U.null,
    resolution_status=parsed.status,resolved_address=U.null,
    failure_reason=parsed.reason or U.null,provenance='runtime_read'}
  if parsed.kind=='module_rva' then query.resolution_method='module_rva' end
  if parsed.kind=='hex' then query.resolution_method='hex_literal' end

  local address=parsed.address
  local moduleBlock={inside_module=U.null,module_name=U.null,module_base=U.null,
    module_size=U.null,module_path=U.null,rva=U.null,ambiguity=U.array(),
    status='unknown',provenance='unavailable'}
  if pid_candidate and not attached then
    diagnostics[#diagnostics+1]=newDiagnostic('TARGET_DETACHED','medium','unknown',
      'The cached process id no longer resolves to a live target; module, region and byte evidence are unavailable.',
      'module_inventory')
  elseif not pid_candidate then
    diagnostics[#diagnostics+1]=newDiagnostic('TARGET_UNAVAILABLE','info','unknown',
      'No process is opened; only syntactic address resolution is available.',
      'runtime_read')
  end
  if parsed.status=='resolved' and parsed.kind=='module_rva' then
    if not attached then
      query.resolution_status='unavailable'
      query.failure_reason='No live target; module-relative resolution is unavailable'
    elseif not modules then
      query.resolution_status='unavailable'
      query.failure_reason=moduleErr or 'Module inventory unavailable'
    else
      local found,matchErr=matchModule(modules,parsed.module)
      if not found then
        query.resolution_status='unresolved_module'
        query.failure_reason=matchErr
      elseif type(found)=='table' and found[1]~=nil and found.base==nil then
        query.resolution_status='ambiguous_module'
        query.failure_reason=matchErr
        for i=1,math.min(#found,MAX_AMBIGUITY) do
          moduleBlock.ambiguity[#moduleBlock.ambiguity+1]={name=found[i].name or U.null,
            path=found[i].path or U.null,base=U.hex(found[i].base)}
        end
      elseif found.base==nil then
        query.resolution_status='unavailable'
        query.failure_reason='Module base is unavailable'
      else
        if found.size and parsed.rva>=found.size then
          query.resolution_status='out_of_range'
          query.failure_reason='RVA is outside the known module size'
        else
          address=found.base+parsed.rva
          query.resolved_address=U.hex(address)
        end
      end
    end
  elseif parsed.status=='resolved' then
    if mask and address>mask then
      query.resolution_status='out_of_range'
      query.failure_reason='Address exceeds the target pointer size'
      address=nil
    else
      query.resolved_address=U.hex(address)
    end
  end

  local status='unknown'
  if query.resolution_status=='resolved' and address then
    status=attached and 'observed' or 'unknown'
  end

  -- Module evidence for the resolved address.
  if address and attached then
    if modules then
      local enclosing,ambiguous,unknown_size={},false,false
      for _,m in ipairs(modules) do
        if m.base then
          if m.size then
            if address>=m.base and address<m.base+m.size then enclosing[#enclosing+1]=m end
          elseif address>=m.base then
            unknown_size=true
          end
        end
      end
      if #enclosing==1 then
        local m=enclosing[1]
        moduleBlock.inside_module=true
        moduleBlock.module_name=m.name
        moduleBlock.module_base=U.hex(m.base)
        moduleBlock.module_size=m.size or U.null
        moduleBlock.module_path=m.path
        moduleBlock.rva=U.hex(address-m.base)
        moduleBlock.status='observed'
        moduleBlock.provenance='module_inventory'
      elseif #enclosing>1 then
        ambiguous=true
      else
        for _,m in ipairs(modules) do
          if m.base and m.size==nil and address>=m.base then unknown_size=true end
        end
      end
      if ambiguous then
        moduleBlock.inside_module=U.null
        moduleBlock.status='unknown'
        moduleBlock.provenance='module_inventory'
        diagnostics[#diagnostics+1]=newDiagnostic('MODULE_AMBIGUOUS','info','unknown',
          'More than one module claims this address range.','module_inventory')
      elseif #enclosing==0 then
        moduleBlock.inside_module=unknown_size and U.null or false
        moduleBlock.status=unknown_size and 'unknown' or 'observed'
        moduleBlock.provenance='module_inventory'
        if not unknown_size then
          diagnostics[#diagnostics+1]=newDiagnostic('OUTSIDE_MODULE','info','observed',
            'Address is outside every enumerated module with a known size.','module_inventory')
        end
      end
    else
      moduleBlock.status='unknown'
      moduleBlock.provenance='unavailable'
    end
  end

  -- Memory region evidence: explicit API first, bounded enumeration second.
  local region={mapped=U.null,base_address=U.null,end_address=U.null,region_size=U.null,
    allocation_base=U.null,state=U.null,type=U.null,protect_raw=U.null,protect_text=U.null,
    allocation_protect_raw=U.null,readable=U.null,writable=U.null,executable=U.null,
    guard=U.null,offset_from_region_base=U.null,offset_from_allocation_base=U.null,
    region_source='unavailable',region_error=U.null,status='unknown',provenance='unavailable'}
  local regionInfo,regionSource,regionErr
  local regionBaseNum,regionEndNum
  if address and attached then
    if type(api and api.getMemoryRegionInfo)=='function' then
      regionInfo,regionSource,regionErr=regionFromAPI(api,address)
    else
      regionInfo,regionSource,regionErr=regionFromEnumeration(api,address)
    end
  end
  if regionInfo then
    local base=n(regionInfo.BaseAddress) or n(regionInfo.base)
    local size=n(regionInfo.RegionSize) or n(regionInfo.size)
    local alloc=n(regionInfo.AllocationBase) or n(regionInfo.allocation_base)
    local protect=n(regionInfo.Protect) or n(regionInfo.protect)
    local allocProtect=n(regionInfo.AllocationProtect) or n(regionInfo.allocation_protect)
    local state=n(regionInfo.State) or n(regionInfo.state)
    local type_=n(regionInfo.Type) or n(regionInfo.type)
    local text,readable,writable,executable,guard=decodeProtect(protect)
    region.mapped=true
    regionBaseNum=base
    regionEndNum=(base and size) and (base+size-1) or nil
    region.base_address=base and U.hex(base) or U.null
    region.region_size=size or U.null
    region.end_address=(base and size) and U.hex(base+size-1) or U.null
    region.allocation_base=alloc and U.hex(alloc) or U.null
    region.state=state or U.null
    region.type=type_ or U.null
    region.protect_raw=protect or U.null
    region.protect_text=text
    region.allocation_protect_raw=allocProtect or U.null
    region.readable=readable
    region.writable=writable
    region.executable=executable
    region.guard=guard
    region.offset_from_region_base=base and (address-base) or U.null
    region.offset_from_allocation_base=alloc and (address-alloc) or U.null
    region.region_source=regionSource
    region.status='observed'
    region.provenance=regionSource
    if regionSource=='enumerated_regions' then
      local regions=U.call(api,'enumMemoryRegions')
      limits.regions_enumerated=(type(regions)=='table') and #regions or 0
    end
    if guard then
      diagnostics[#diagnostics+1]=newDiagnostic('GUARD_PAGE','medium','observed',
        'The memory page is marked PAGE_GUARD.','ce_region_api')
    end
    if readable==false then
      diagnostics[#diagnostics+1]=newDiagnostic('UNREADABLE_MEMORY','medium','observed',
        'The memory page protection does not allow reading.','ce_region_api')
    end
  elseif address then
    region.region_source=regionSource or 'unavailable'
    region.region_error=regionErr or U.null
    region.provenance=regionSource or 'unavailable'
    if (regionSource=='enumerated_regions' or regionSource=='ce_region_api') and not regionErr then
      region.mapped=false
      region.status='observed'
      local regions=U.call(api,'enumMemoryRegions')
      limits.regions_enumerated=(type(regions)=='table') and #regions or 0
      diagnostics[#diagnostics+1]=newDiagnostic('UNMAPPED_ADDRESS','info','observed',
        'No memory region was reported for this address.',regionSource)
    else
      region.status='unknown'
    end
  end

  -- Bounded byte evidence with page/region boundary handling.
  local requested=math.floor(tonumber(options.bytes) or DEFAULT_BYTES)
  if requested<1 then requested=1 end
  if requested>MAX_BYTES then requested=MAX_BYTES end
  limits.bytes_requested=requested
  local bytesBlock={requested_length=requested,read_length=0,hex=U.null,
    read_status='read_failed',is_partial=false,address=U.null,status='unknown',provenance='unavailable'}
  local data,decodeBytes
  if address and attached then
    bytesBlock.address=U.hex(address)
    local allowed=requested
    if regionEndNum then
      local remaining=regionEndNum-address+1
      if remaining>=1 and remaining<allowed then
        allowed=remaining
        bytesBlock.is_partial=true
      end
    end
    if region.readable==false then
      bytesBlock.read_status='unreadable'
      bytesBlock.status='unknown'
      bytesBlock.provenance='ce_region_api'
    else
      data,bytesBlock.read_error=readBytes(api,address,allowed)
      if type(data)=='table' and #data==allowed then
        bytesBlock.read_status='read_ok'
        bytesBlock.provenance='runtime_read'
      elseif type(data)=='table' and #data>0 then
        bytesBlock.read_status='short_read'
        bytesBlock.is_partial=true
        bytesBlock.provenance='runtime_read'
        diagnostics[#diagnostics+1]=newDiagnostic('PARTIAL_BYTE_READ','info','observed',
          'Fewer bytes were readable than requested.','runtime_read')
      else
        -- Page-boundary fallback: salvage the readable prefix one byte at a time.
        local salvaged={}
        for offset=0,allowed-1 do
          local one=readBytes(api,address+offset,1)
          if type(one)=='table' and #one==1 then salvaged[#salvaged+1]=one[1] else break end
        end
        if #salvaged>0 then
          data=salvaged
          bytesBlock.read_status='short_read'
          bytesBlock.is_partial=true
          bytesBlock.provenance='runtime_read'
          diagnostics[#diagnostics+1]=newDiagnostic('PARTIAL_BYTE_READ','info','observed',
            'Read stopped at an unreadable page or region boundary.','runtime_read')
        else
          bytesBlock.read_status='read_failed'
          bytesBlock.provenance='runtime_read'
          diagnostics[#diagnostics+1]=newDiagnostic('UNREADABLE_MEMORY','medium','unknown',
            'The requested bytes could not be read.','runtime_read')
        end
      end
      if type(data)=='table' and #data>0 then
        bytesBlock.read_length=#data
        bytesBlock.hex=bytesHex(data)
        bytesBlock.status='observed'
        limits.bytes_read=#data
        decodeBytes=data
      end
    end
  elseif address then
    bytesBlock.read_status='read_failed'
    bytesBlock.provenance='unavailable'
  end

  -- Instruction evidence from our own decoder, never from CE disassembly.
  local instruction={decode_status='invalid',length=U.null,prefixes=U.array(),opcode=U.null,
    opcode_text=U.null,modrm=U.null,sib=U.null,displacement=U.null,operand_size=U.null,
    mnemonic=U.null,operands_text=U.null,rip_relative=U.null,status='unknown',reason=U.null,
    provenance='unavailable'}
  local memoryOperand=emptyMemoryOperand()
  local decodeResult
  if decodeBytes then
    decodeResult=D.decode(decodeBytes,arch)    instruction.decode_status=decodeResult.status
    instruction.provenance='static_bytes'
    instruction.reason=decodeResult.reason or U.null
    if decodeResult.status=='decoded' then
      instruction.status='observed'
      instruction.length=decodeResult.length
      instruction.opcode=decodeResult.opcode
      instruction.opcode_text=decodeResult.opcode_text
      instruction.modrm=decodeResult.modrm or U.null
      instruction.sib=decodeResult.sib or U.null
      instruction.displacement=decodeResult.displacement or U.null
      instruction.operand_size=decodeResult.operand_size or U.null
      instruction.mnemonic=decodeResult.mnemonic or U.null
      instruction.operands_text=decodeResult.operands_text or U.null
      instruction.rip_relative=decodeResult.rip_relative
      for _,p in ipairs(decodeResult.prefixes or {}) do
        instruction.prefixes[#instruction.prefixes+1]=string.format('%02X',p)
      end
      local mem=decodeResult.memory
      if mem and mem.present then
        memoryOperand.present=true
        memoryOperand.base_register=mem.base_register or U.null
        memoryOperand.index_register=mem.index_register or U.null
        memoryOperand.scale=mem.scale or U.null
        memoryOperand.displacement=mem.displacement or U.null
        memoryOperand.rip_relative=mem.rip_relative
        memoryOperand.absolute=mem.absolute
        memoryOperand.expression_text=mem.expression_text or U.null
        memoryOperand.is_stack_reference=mem.is_stack_reference
        memoryOperand.status='observed'
        memoryOperand.provenance='static_bytes'
      else
        memoryOperand.status='observed'
        memoryOperand.provenance='static_bytes'
      end
    elseif decodeResult.status=='truncated' then
      instruction.status='unknown'
    else
      instruction.status='unsupported'
    end
  else
    instruction.reason='no_bytes'
  end

  -- Effective address: only when the instruction alone proves it.
  local effective={effective_address=U.null,effective_address_status='unavailable',
    reason=U.null,status='unknown',provenance='unavailable'}
  if decodeResult and decodeResult.status=='decoded' then
    local mem=decodeResult.memory
    if mem and mem.present then
      if mem.rip_relative and decodeResult.length then
        local target=address+decodeResult.length+(mem.displacement or 0)
        if mask then target=target & mask end
        effective.effective_address=U.hex(target)
        effective.effective_address_status='resolved_rip_relative'
        effective.status='observed'
        effective.provenance='derived'
      elseif mem.absolute then
        local target=mem.displacement or 0
        if mask then target=target & mask end
        effective.effective_address=U.hex(target)
        effective.effective_address_status='resolved_static'
        effective.status='observed'
        effective.provenance='derived'
      else
        effective.effective_address_status='requires_runtime_context'
        effective.reason='Register-dependent operand; no register state is collected.'
        effective.status='unknown'
        diagnostics[#diagnostics+1]=newDiagnostic('REGISTER_DEPENDENT_EFFECTIVE_ADDRESS',
          'info','unknown','Effective address needs runtime registers.','derived')
      end
      if mem.is_stack_reference then
        diagnostics[#diagnostics+1]=newDiagnostic('STACK_REFERENCE','info','observed',
          'The memory operand references the stack.','static_bytes')
      end
    else
      effective.effective_address_status='unavailable'
      effective.reason='Instruction has no memory operand.'
      effective.status='unknown'
    end
  elseif decodeResult and decodeResult.status=='unsupported' then
    effective.effective_address_status='unsupported'
    effective.reason='Instruction decode is unsupported.'
    effective.status='unsupported'
    diagnostics[#diagnostics+1]=newDiagnostic('UNSUPPORTED_INSTRUCTION','info','unsupported',
      'Instruction is outside the supported decode whitelist.','static_bytes')
  end

  -- Conservative type advisory: still an inference, never a confirmed type.
  local typeBlock={suggested_type=U.null,category=U.null,confidence='none',
    status='not_applicable',reason=U.null,source='decoder',provenance='static_bytes'}
  if not decodeBytes then
    typeBlock.status='unknown'
    typeBlock.reason='No bytes were read.'
    typeBlock.provenance='unavailable'
  elseif decodeResult.status~='decoded' then
    typeBlock.status=(decodeResult.status=='unsupported') and 'unsupported' or 'unknown'
    typeBlock.reason=decodeResult.reason or decodeResult.status
  elseif not memoryOperand.present then
    typeBlock.status='not_applicable'
    typeBlock.reason='Instruction has no memory operand.'
  else
    local mnemonic=decodeResult.mnemonic
    if FLOAT_MNEMONICS[mnemonic] then
      typeBlock.suggested_type='Float'
      typeBlock.category='float'
      typeBlock.confidence='high'
      typeBlock.status='candidate'
      typeBlock.reason='Single-precision SSE opcode ('..mnemonic..').'
    elseif DOUBLE_MNEMONICS[mnemonic] then
      typeBlock.suggested_type='Double'
      typeBlock.category='double'
      typeBlock.confidence='high'
      typeBlock.status='candidate'
      typeBlock.reason='Double-precision SSE opcode ('..mnemonic..').'
    elseif mnemonic=='fld' or mnemonic=='fst' or mnemonic=='fstp' then
      if decodeResult.operand_size==32 then
        typeBlock.suggested_type='Float'
        typeBlock.category='float'
        typeBlock.confidence='medium'
        typeBlock.status='candidate'
        typeBlock.reason='x87 dword memory operand.'
      elseif decodeResult.operand_size==64 then
        typeBlock.suggested_type='Double'
        typeBlock.category='double'
        typeBlock.confidence='medium'
        typeBlock.status='candidate'
        typeBlock.reason='x87 qword memory operand.'
      end
    else
      typeBlock.status='not_applicable'
      typeBlock.reason='Opcode does not imply a floating-point value type.'
    end
  end

  -- Detect a target change during the inspection; never mix two states.
  local pidAfter=n(api and api.getOpenedProcessID and U.call(api,'getOpenedProcessID'))
  if type(pid)=='number' and type(pidAfter)=='number' and pidAfter~=pid then
    status='invalidated'
    diagnostics[#diagnostics+1]=newDiagnostic('PROCESS_CHANGED','high','invalidated',
      'The opened process changed during the inspection.','runtime_read')
    region.status='invalidated'
    bytesBlock.status='invalidated'
    instruction.status='invalidated'
    effective.status='invalidated'
    typeBlock.status='invalidated'
  end

  local limitations=U.array({
    'Evidence is a single bounded snapshot; the target may change afterwards.',
    'Effective addresses that depend on registers are not computed without a register context.',
    'Instruction decoding is a conservative whitelist; other opcodes stay unsupported.',
    'Symbol lookup is not collected: it can invoke table-provided symbol callbacks.',
    'Module sizes may be unavailable; membership is not claimed without a provable range.',
    'Region enumeration may be incomplete; unmapped results are not absolute proof.'
  })

  local completed=os.date('!%Y-%m-%dT%H:%M:%SZ')
  return {
    schema_version='0.1',
    title='CESuite Address Evidence',
    core_version='0.1.9',
    suite_version='0.3.0',
    generated_at=started,
    completed_at=completed,
    observation_only=true,
    status=status,
    query=query,
    target={attached=attached,pid=pid or U.null,architecture=arch,
      pointer_size=ptr or U.null,
      process_name=attached and ((type(api and api.process)=='string') and api.process or U.null) or U.null,
      status=(attached and 'observed') or (pid_candidate and 'detached' or 'unknown'),
      provenance=(attached and 'runtime_read' or 'unavailable')},
    module=moduleBlock,
    symbol={has_symbol=false,symbol_name=U.null,symbol_offset=U.null,
      symbol_source='not_collected'},
    region=region,
    bytes=bytesBlock,
    instruction=instruction,
    memory_operand=memoryOperand,
    effective_address=effective,
    type_advisory=typeBlock,
    diagnostics=diagnostics,
    limits=limits,
    limitations=limitations
  }
end

M.MAX_BYTES=MAX_BYTES
return M
