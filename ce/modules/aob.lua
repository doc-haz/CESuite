local U=require('util')
local M={}
-- Resolve only numbers, enumerated modules and simple +/- constants. No CE symbol
-- lookup: registered callbacks can execute arbitrary table code during lookup.
function M.resolve(expression, modules, defines, seen)
  if type(expression)~='string' then return nil end
  local s=U.trim(expression)
  seen=seen or {}
  if seen[s:lower()] then return nil end
  seen[s:lower()]=true
  if defines and defines[s:lower()]~=nil then
    if not defines[s:lower()] then return nil end
    return M.resolve(defines[s:lower()],modules,defines,seen)
  end
  local n=U.number(s)
  if n then return n end
  local name=U.unquote(s):lower()
  for _,m in ipairs(modules) do
    if m.name:lower()==name and type(m.base)=='string' then return tonumber(m.base:sub(3),16) end
  end
  local base,op,offset=s:match('^(.-)%s*([+-])%s*([%x#xX$]+)$')
  if base then
    local b=M.resolve(base,modules,defines,seen)
    local o=U.number(offset)
    if b and o then local v=b+(op=='+' and o or -o);if v>=0 then return v end end
  end
end
function M.pattern(s)
  if type(s)~='string' then return nil end
  local bytes,known={},false
  for token in s:gmatch('%S+') do
    token=token:gsub('%*','?'):lower()
    if token=='?' then token='??' end
    if #token~=2 or token:find('[^%x?]') then return nil end
    if token:find('%x') then known=true end
    bytes[#bytes+1]=token
  end
  if #bytes==0 or #bytes>4096 or not known then return nil end
  return table.concat(bytes,' ')
end
function M.bounds(a,report,script)
  if a.scope=='process' then return 0,-1 end -- unsigned all-addresses sentinel, no symbol lookup
  if a.scope=='module' then
    local name=U.unquote(a.arguments[2]):lower()
    for _,m in ipairs(report.modules) do
      if m.name:lower()==name and type(m.base)=='string' and type(m.size)=='number' and m.size>0 then
        local base=tonumber(m.base:sub(3),16)
        -- AA passes module base + image size as its stop argument too.
        return base,base+m.size
      end
    end
    return nil,nil,'Module name/size unavailable; scope was not broadened.'
  end
  local first=M.resolve(a.arguments[2],report.modules,script.defines)
  local last=M.resolve(a.arguments[3],report.modules,script.defines)
  if not first or not last or first>last then return nil,nil,'Region expression unresolved or reversed; scope was not broadened.' end
  return first,last
end
local function hookOffset(expr,symbol,defines,seen)
  expr=U.trim(expr);seen=seen or {}
  if seen[expr:lower()] then return nil end
  seen[expr:lower()]=true
  if expr:lower()==symbol:lower() then return 0 end
  if defines[expr:lower()] then return hookOffset(defines[expr:lower()],symbol,defines,seen) end
  local base,sign,num=expr:match('^(.-)%s*([+-])%s*([%x#xX$]+)$')
  if base then
    local b=hookOffset(base,symbol,defines,seen)
    local n=U.number(num)
    if b and n then return b+(sign=='+' and n or -n) end
  end
end
function M.hooks(a,script)
  for _,label in ipairs(script.labels) do
    local offset=hookOffset(label.expression,a.symbol,script.defines)
    if offset then a.hook_candidates[#a.hook_candidates+1]={expression=label.expression,
      line=label.line,offset_bytes=offset,evidence='static_candidate',hook_address=U.null,
      note='AA placement label relative to signature; patch intent and instruction boundary unverified.'} end
  end
  if a.match_count==1 and #a.matches==1 then
    local anchor=tonumber(a.matches[1].signature_anchor:sub(3),16)
    for _,h in ipairs(a.hook_candidates) do if anchor+h.offset_bytes>=0 then h.hook_address=U.hex(anchor+h.offset_bytes) end end
  end
end
function M.validate(api,report,context)
  local scripts,providers={},{}
  for _,s in ipairs(report.scripts) do scripts[s.id]=s end
  for _,a in ipairs(report.aobs) do
    local key=a.script_id..':'..a.symbol:lower()
    providers[key]=(providers[key] or 0)+1
  end
  for _,a in ipairs(report.aobs) do
    local script=scripts[a.script_id]
    local pattern=M.pattern(a.pattern)
    a.observed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
    local first,last,reason
    if a.syntax_supported then first,last,reason=M.bounds(a,report,script) end
    local pid=U.call(api,'getOpenedProcessID')
    if not report.target.attached or pid~=report.target.pid then a.status='unavailable';reason='No attached process or process changed.'
    elseif not a.syntax_supported or not pattern then a.status='unsupported';reason='Only literal byte/nibble wildcard patterns with correct argument count are supported; all-wildcard scans are refused.'
    elseif first==nil then a.status='unresolved'
    else
      a.scan={start=U.hex(first),stop=type(last)=='string' and '0x'..last or U.hex(last),
        protection_flags='*X*C*W',alignment='none',method='MemScan/FoundList',
        stop_semantics='CE firstScan stop argument; same bounds as AA',error_visibility='unknown'}
      local ms,fl
      local ok,err=xpcall(function()
        ms=assert(api.createMemScan(),'createMemScan failed')
        ms.OnlyOneResult=false
        ms.IsUnique=false
        ms.firstScan(api.soExactValue,api.vtByteArray,api.rtRounded,pattern,'',first,last,
          '*X*C*W',api.fsmNotAligned,'1',true,false,false,false)
        ms.waitTillDone()
        local failure=U.get(ms,'ErrorString')
        a.scan.error_visibility=type(failure)=='string' and 'available' or 'unavailable'
        if type(failure)=='string' and failure~='' then error(failure) end
        fl=assert(api.createFoundList(ms),'createFoundList failed')
        fl.initialize()
        local count=fl.Count
        assert(type(count)=='number' and count>=0,'FoundList count unavailable')
        a.match_count=count
        a.matches_truncated=count>256
        for i=0,math.min(count,256)-1 do
          local address=tonumber(fl.Address[i],16)
          assert(address,'Invalid match address')
          local match={signature_anchor=U.hex(address)}
          if context and i<8 then match.context=context(api,address,report.target.architecture) end
          a.matches[#a.matches+1]=match
        end
        a.status='observed'
        a.uniqueness=count==1 and 'unique_current_scan' or (count==0 and 'no_match' or 'multiple_matches')
        if a.scan.error_visibility=='unavailable' then
          a.uniqueness='unverified'
          U.warn(report,'SCAN-ERROR-VISIBILITY','CE does not expose scan ErrorString; count is retained but uniqueness is unverified.',a.script_id,a.line)
        end
      end,function(e) return tostring(e) end)
      -- Release only objects created by this scan, found list before its owner.
      if fl then pcall(function() fl.destroy() end) end
      if ms then pcall(function() ms.destroy() end) end
      if not ok then a.status='error';reason=err;a.match_count=U.null;a.uniqueness='unverified';a.matches=U.array();a.matches_truncated=false end
      if U.call(api,'getOpenedProcessID')~=report.target.pid then
        a.status='invalidated';reason='Process changed during scan.';a.uniqueness='unverified';a.match_count=U.null;a.matches=U.array();a.matches_truncated=false
      end
    end
    if reason then a.message=reason end
    if providers[a.script_id..':'..a.symbol:lower()]==1 then M.hooks(a,script)
    else U.warn(report,'AMBIGUOUS-ANCHOR','Repeated AOB symbol in this script; hook inference omitted.',a.script_id,a.line) end
    if a.status=='observed' then
      for i,h in ipairs(a.hook_candidates) do
        if context and i<=8 and type(h.hook_address)=='string' then h.context=context(api,tonumber(h.hook_address:sub(3),16),report.target.architecture) end
      end
    end
  end
end
return M
