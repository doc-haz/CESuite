-- CESuite @VERSION@. Local files only; no package.path or working-directory lookup.
local api=_G
local function start()
  assert(type(getAutorunPath)=='function','getAutorunPath is unavailable')
  local root=getAutorunPath()
  assert(type(root)=='string' and
    (root:match('^%a:[/\\]') or root:match('^[/\\][/\\]') or root:match('^/')),
    'getAutorunPath must return an absolute path')
  root=root:gsub('[/\\]+$','')..'/cesuite/'
  local loaded={}
  local function module(name)
    assert(name:match('^[a-z]+$'),'Invalid CESuite module name')
    if loaded[name]~=nil then return loaded[name] end
    local environment=setmetatable({api=api},{__index=api})
    environment.require=module
    local chunk,err=loadfile(root..name..'.lua','t',environment)
    assert(chunk,err)
    local result=chunk()
    assert(type(result)=='table','Invalid CESuite module: '..name)
    loaded[name]=result
    return result
  end
  local environment=setmetatable({api=api,version='@VERSION@',mode='autorun',
    factory=function() return module('core') end},{__index=api})
  local bootstrap,err=loadfile(root..'bootstrap.lua','t',environment)
  assert(bootstrap,err)
  return bootstrap()
end
local ok,core,err=pcall(start)
if not ok then
  local message='CESuite autorun failed: '..tostring(core)
  if type(showMessage)=='function' then pcall(showMessage,message) else print(message) end
  return nil,core
end
return core,err
