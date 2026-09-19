-- Execute the actual extracted ZIP and CT Lua using synthetic CE objects only.
local root=assert(CESUITE_TEST_PACKAGE):gsub('\\','/')
local autorun=root..'/autorun/CESuite_Autorun.lua'
local portable=root..'/portable.lua'
local tests=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local menus,messages,created,failAt
local function reset()
  CESuiteCore=nil;CESuiteLoading=nil
  menus={Count=0};messages={};created=0;failAt=nil
  menus.add=function(item) menus[menus.Count]=item;menus.Count=menus.Count+1 end
  getMainForm=function() return {Menu={Items=menus}} end
  getAutorunPath=function() return root..'/autorun/' end
  showMessage=function(message) messages[#messages+1]=message end
  createMenuItem=function(owner)
    created=created+1
    if created==failAt then error('synthetic menu failure') end
    local item={children={}}
    item.add=function(child) item.children[#item.children+1]=child end
    item.destroy=function()
      for i=0,menus.Count-1 do
        if menus[i]==item then
          for j=i,menus.Count-2 do menus[j]=menus[j+1] end
          menus[menus.Count-1]=nil;menus.Count=menus.Count-1;break
        end
      end
    end
    return item
  end
end
local function test(name,fn) reset();fn();tests=tests+1;print('PASS '..name) end

test('autorun then CT then autorun preserves instance, report and one menu',function()
  local core=assert(dofile(autorun));eq(core.status,'ready');eq(core.distribution,'autorun')
  core.last_report={sentinel=true}
  eq(dofile(portable),core);eq(dofile(autorun),core);eq(core.last_report.sentinel,true)
  eq(menus.Count,1);eq(created,8)
  eq(core.install(),core);eq(menus.Count,1)
end)
test('CT then autorun preserves portable instance',function()
  local core=assert(dofile(portable));eq(dofile(autorun),core);eq(menus.Count,1)
  eq(core.distribution,'portable')
end)
test('remove and reload restores one menu and exposes status',function()
  local core=assert(dofile(autorun))
  menus[0].children[7].OnClick();eq(core.status,'stopped');eq(menus.Count,0)
  eq(dofile(portable),core);eq(core.status,'ready');eq(menus.Count,1)
  menus[0].children[6].OnClick();assert(messages[1]:find(core.version,1,true))
end)
test('partial menu failure cleans up and permits retry',function()
  failAt=3
  local core,err=dofile(autorun);eq(core,nil);assert(err);eq(menus.Count,0)
  eq(CESuiteCore,nil);eq(CESuiteLoading,nil);eq(#messages,1)
  failAt=nil;assert(dofile(autorun));eq(menus.Count,1)
end)
test('missing module fails without a partial singleton and can recover',function()
  local path=root..'/autorun/cesuite/aob.lua'
  assert(os.rename(path,path..'.bak'))
  local core,err=dofile(autorun)
  assert(os.rename(path..'.bak',path))
  eq(core,nil);assert(err:find('aob.lua',1,true));eq(CESuiteCore,nil);eq(CESuiteLoading,nil)
  eq(menus.Count,0);assert(dofile(autorun));eq(menus.Count,1)
end)
test('syntax error is reported and can recover',function()
  local path=root..'/autorun/cesuite/ui.lua'
  local f=assert(io.open(path,'rb'));local original=f:read('*a');f:close()
  f=assert(io.open(path,'wb'));f:write('invalid Lua !');f:close()
  local core,err=dofile(autorun)
  f=assert(io.open(path,'wb'));f:write(original);f:close()
  eq(core,nil);assert(err);eq(menus.Count,0);eq(CESuiteLoading,nil)
  assert(dofile(autorun));eq(menus.Count,1)
end)
test('relative path rejected and missing getAutorunPath handled',function()
  getAutorunPath=function() return 'relative/' end
  eq(dofile(autorun),nil);eq(menus.Count,0)
  getAutorunPath=nil;eq(dofile(autorun),nil);eq(#messages,2)
end)
test('absolute paths do not consult ambient require or package.path',function()
  local savedRequire,savedPath=require,package.path
  require=function() error('ambient require must not run') end;package.path=''
  local core,err=dofile(autorun)
  require=savedRequire;package.path=savedPath
  assert(core,err);eq(menus.Count,1)
end)
test('different version preserves existing instance and asks for restart',function()
  local core=assert(dofile(autorun));core.version='999.0.0'
  local again,err=dofile(portable);eq(again,core);assert(err);eq(menus.Count,1)
  eq(#messages,1)
end)
test('foreign or legacy global is preserved',function()
  local foreign={version='0.1.0',shutdown=function() error('do not call') end}
  CESuiteCore=foreign;eq(dofile(autorun),nil);eq(CESuiteCore,foreign);eq(menus.Count,0)
end)
test('reentrant load does not construct another Core',function()
  CESuiteLoading=true;eq(dofile(autorun),nil);eq(menus.Count,0)
end)
test('orphan named menu is preserved without a duplicate',function()
  menus.add({Name='CESuiteCoreMenu'})
  eq(dofile(portable),nil);eq(menus.Count,1);eq(CESuiteCore,nil)
end)
print(string.format('%d distribution tests passed (synthetic CE objects; not live CE)',tests))
