local U=require('util')
local M={}
local function quote(s)
  -- CE text is expected to be UTF-8; reject malformed input instead of writing invalid JSON.
  if utf8 and not utf8.len(s) then error('Invalid UTF-8 in report text') end
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
    local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return escapes[c] or string.format('\\u%04x',c:byte())
  end)..'"'
end
function M.encode(value,seen)
  if value==U.null then return 'null' end
  local t=type(value)
  if t=='string' then return quote(value) end
  if t=='boolean' then return tostring(value) end
  if t=='number' then assert(value==value and math.abs(value)~=math.huge,'Non-finite number');return tostring(value) end
  assert(t=='table','Unsupported JSON value: '..t)
  seen=seen or {};assert(not seen[value],'Cyclic JSON value');seen[value]=true
  local parts={}
  if (getmetatable(value) or {}).__json_array then
    for i=1,#value do parts[#parts+1]=M.encode(value[i],seen) end
    seen[value]=nil;return '['..table.concat(parts,',')..']'
  end
  local keys={};for k in pairs(value) do assert(type(k)=='string','JSON object key must be string');keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do parts[#parts+1]=quote(k)..':'..M.encode(value[k],seen) end
  seen[value]=nil;return '{'..table.concat(parts,',')..'}'
end
function M.write(report,path)
  local encoded=M.encode(report)..'\n'
  local f,err=io.open(path,'wb');assert(f,err)
  local ok,failure=f:write(encoded)
  local closed,closeError=f:close()
  assert(ok,failure);assert(closed,closeError)
  return path
end
-- Timing is operational metadata: it never changes the encoded bytes or the
-- write behavior. serialize_ms and write_ms are measured separately.
function M.writeTimed(report,path)
  local Ops=require('operations')
  local started=Ops.begin()
  local serializeStart=Ops.begin()
  local encoded=M.encode(report)..'\n'
  local serializeMs=Ops.elapsed(serializeStart)
  local writeStart=Ops.begin()
  local f,err=io.open(path,'wb');assert(f,err)
  local ok,failure=f:write(encoded)
  local closed,closeError=f:close()
  assert(ok,failure);assert(closed,closeError)
  local writeMs=Ops.elapsed(writeStart)
  local totalMs=Ops.elapsed(started)
  return path,{ok=true,bytes=#encoded,serialize_ms=serializeMs,
    write_ms=writeMs,total_ms=totalMs}
end
return M
