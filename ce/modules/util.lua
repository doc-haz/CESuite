local M = {}
M.null = setmetatable({}, {__json_null = true})
function M.array(t) return setmetatable(t or {}, {__json_array = true}) end
function M.trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
function M.hex(n) return type(n) == 'number' and string.format('0x%X', n) or M.null end
function M.get(obj, key)
  local ok, value = pcall(function() return obj[key] end)
  if ok then return value end
end
function M.call(api, name, ...)
  if type(api[name]) ~= 'function' then return nil, name .. ' unavailable' end
  local ok, value = pcall(api[name], ...)
  if ok then return value end
  return nil, tostring(value)
end
function M.warn(report, rule, message, script, line)
  table.insert(report.diagnostics, {rule=rule, severity='review', evidence='unverified',
    message=message, script_id=script or M.null, line=line or M.null})
end
function M.number(s)
  s = M.trim(s)
  if s:match('^#%d+$') then return tonumber(s:sub(2), 10) end
  if s:match('^0[xX]%x+$') then return tonumber(s:sub(3), 16) end
  if s:match('^%$%x+$') then return tonumber(s:sub(2), 16) end
  if s:match('^%x+$') then return tonumber(s, 16) end
end
function M.unquote(s)
  local a,b=s:sub(1,1),s:sub(-1)
  if (a=='"' or a=="'") and a==b then return s:sub(2,-2) end
  return s
end
function M.moduleNorm(value)
  if type(value)~='string' then return nil end
  value=M.trim(M.unquote(M.trim(value))):gsub('\\','/'):lower()
  return value~='' and value or nil
end
function M.moduleMatch(query,modules)
  query=M.moduleNorm(query)
  if not query then return nil,'invalid empty module query' end
  local found,count=nil,0
  local basename=not query:find('/',1,true)
  for _,m in ipairs(modules) do
    local name,path=M.moduleNorm(m.name),M.moduleNorm(m.path)
    if name==query or path==query or (basename and
      ((name and name:match('[^/]+$')==query) or (path and path:match('[^/]+$')==query))) then
      found=m;count=count+1
    end
  end
  if count>1 then return nil,'ambiguous module: '..query end
  return found,count==0 and 'unresolved module: '..query or nil
end
return M
