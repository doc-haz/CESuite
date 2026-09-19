-- Shared by both distributions. Dependencies are private to each new instance.
local function notify(message)
  if type(api.showMessage)=='function' then pcall(api.showMessage,message)
  elseif type(api.print)=='function' then pcall(api.print,message) end
end
local existing=rawget(api,'CESuiteCore')
if existing~=nil then
  if type(existing)~='table' or existing.identity~='CESuiteCore' then
    local err='CESuiteCore is already occupied (possibly an older Core). Restart CE before upgrading.'
    notify(err);return nil,err
  end
  if existing.version~=version then
    local err='CESuite '..tostring(existing.version)..' is already loaded; requested '..version..'. Restart CE to change versions.'
    notify(err);return existing,err
  end
  local ok,err=pcall(existing.install)
  if not ok then notify('CESuite: '..tostring(err));return nil,err end
  return existing
end
if rawget(api,'CESuiteLoading') then return nil,'CESuite is already loading' end
api.CESuiteLoading=true
local core
local ok,err=pcall(function()
  core=factory()
  assert(core.version==version,'CESuite package version mismatch')
  core.distribution=mode
  core.install()
  api.CESuiteCore=core
end)
api.CESuiteLoading=nil
if not ok then
  if core then pcall(core.shutdown) end
  notify('CESuite failed to load: '..tostring(err))
  return nil,err
end
return core
