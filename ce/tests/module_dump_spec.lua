package.path='ce/modules/?.lua;'..package.path
local Dump=require('moduledump')
local count=0
local path=os.tmpname()..'-CESuite-module-test.bin'
local function clean()
  for _,suffix in ipairs({'','.partial','.json'}) do
    os.remove(path..suffix)
    os.remove(path..suffix..'.previous')
    os.remove(path..suffix..'.previous.1')
  end
end
local function api()
  return {
    getOpenedProcessID=function() return 7 end,
    enumModules=function() return {{Name='game.exe',Address=0x140000000,PathToFile='game.exe'}} end,
    readSmallInteger=function(a) return a==0x140000000 and 0x5A4D or 0x20B end,
    readInteger=function(a)
      if a==0x14000003C then return 0x80 end
      if a==0x140000080 then return 0x4550 end
      if a==0x1400000D0 then return 65540 end
      error('unexpected integer read')
    end,
    readBytes=function(a,n,asTable)
      assert(asTable==true)
      local t={};for i=1,n do t[i]=(a+i-1)%256 end;return t
    end
  }
end
local function test(name,fn)
  clean();fn()
  if CESUITE_TEST_OUTPUT then
    local f=io.open(path..'.json','rb')
    if f then
      local text=f:read('*a');f:close()
      if text:find('"schema_version":"module-dump-1"',1,true) then
        local out=assert(io.open(CESUITE_TEST_OUTPUT..'/dump-'..(count+1)..'.json','wb'))
        out:write(text);out:close()
      end
    end
  end
  clean();count=count+1;print('PASS '..name)
end
local function fails(fn) local ok=pcall(fn);assert(not ok) end
test('complete mapped image and sidecar; bounded reads and exact bytes',function()
  local a=api();local read=a.readBytes;local sizes={}
  a.readBytes=function(address,n,t) sizes[#sizes+1]=n;return read(address,n,t) end
  local r=Dump.write(a,'GAME.EXE',path)
  assert(r.status=='complete' and r.bytes_written==65540 and r.atomic_snapshot==false, tostring(r.error))
  assert(#sizes==2 and sizes[1]==65536 and sizes[2]==4)
  local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close()
  assert(#s==65540 and s:sub(1,4)==string.char(0,1,2,3))
  local m=assert(io.open(path..'.json','rb'));local text=m:read('*a');m:close()
  assert(text:find('"status":"complete"',1,true))
end)
test('unreadable block is partial without fabricated padding',function()
  local a=api();local read=a.readBytes
  a.readBytes=function(address,n,t) if n==4 then return nil end;return read(address,n,t) end
  local r=Dump.write(a,'game.exe',path)
  assert(r.status=='partial' and r.bytes_written==65536 and #r.unreadable_ranges==1)
  assert(not io.open(path,'rb'))
  local f=assert(io.open(path..'.partial','rb'));assert(f:seek('end')==65536);f:close()
end)
test('process change invalidates dump',function()
  local a=api();local read=a.readBytes;local changed=false
  a.getOpenedProcessID=function() return changed and 8 or 7 end
  a.readBytes=function(...) changed=true;return read(...) end
  local r=Dump.write(a,'game.exe',path);assert(r.status=='partial' and r.error:find('Process changed',1,true))
end)
test('module change invalidates dump',function()
  local a=api();local reads=0;local read=a.readBytes
  a.readBytes=function(...) reads=reads+1;return read(...) end
  a.enumModules=function() return {{Name='game.exe',Address=reads>0 and 0x150000000 or 0x140000000}} end
  local r=Dump.write(a,'game.exe',path);assert(r.status=='partial' and r.error:find('Module changed',1,true))
end)
test('existing destination and sidecar are not overwritten',function()
  for _,suffix in ipairs({'','.partial','.json'}) do
    clean();local f=assert(io.open(path..suffix,'wb'));f:write('keep');f:close()
    fails(function() Dump.write(api(),'game.exe',path) end)
    f=assert(io.open(path..suffix,'rb'));assert(f:read('*a')=='keep');f:close()
  end
end)
test('invalid headers, unknown module and no process fail before output',function()
  local a=api();a.readSmallInteger=function() return 0 end
  fails(function() Dump.write(a,'game.exe',path) end)
  fails(function() Dump.write(api(),'unknown.exe',path) end)
  a=api();a.getOpenedProcessID=function() return 0 end
  fails(function() Dump.write(a,'game.exe',path) end)
  assert(not io.open(path..'.partial','rb'))
end)
test('duplicate module names reject before headers or output',function()
  local a=api()
  a.enumModules=function() return {{Name='game.exe',Address=4096,PathToFile='C:/one/game.exe'},
    {Name='GAME.EXE',Address=8192,PathToFile='D:/two/game.exe'}} end
  a.readSmallInteger=function() error('ambiguous module must not be read') end
  local ok,err=pcall(function() Dump.write(a,'game.exe',path) end)
  assert(not ok and tostring(err):lower():find('ambiguous'),tostring(err))
  assert(not io.open(path..'.partial','rb'))
end)

test('read exception and short reads stay partial',function()
  for _,fn in ipairs({function() error('read failed') end,function() return {1} end}) do
    clean();local a=api();a.readBytes=fn
    local r=Dump.write(a,'game.exe',path);assert(r.status=='partial' and r.bytes_written==0)
  end
end)
test('cancel before first read closes partial and records cancellation',function()
  local a=api();a.readBytes=function() error('must not read') end
  local r=Dump.write(a,'game.exe',path,{progress=function(done,total)
    assert(done==0 and total==65540);return false
  end})
  assert(r.status=='partial' and r.cancelled==true and r.bytes_written==0)
end)
test('cancel after first block retains only completed bytes',function()
  local r=Dump.write(api(),'game.exe',path,{progress=function(done) return done==0 end})
  assert(r.status=='partial' and r.cancelled==true and r.bytes_written==65536)
end)
test('progress callback process change is detected before read',function()
  local a=api();a.readBytes=function() error('must not read changed process') end
  local r=Dump.write(a,'game.exe',path,{progress=function()
    a.getOpenedProcessID=function() return 99 end;return true
  end})
  assert(r.status=='partial' and r.bytes_written==0 and r.error:find('Process changed',1,true))
end)
test('byte conversion rejects invalid byte values',function()
  local a=api();a.readBytes=function(_,n)
    local t={};for i=1,n do t[i]=0 end;t[1]=256;return t
  end
  local r=Dump.write(a,'game.exe',path);assert(r.status=='partial' and r.bytes_written==0)
end)
test('overwrite decline preserves all outputs without reading memory',function()
  for _,suffix in ipairs({'','.partial','.json'}) do
    local f=assert(io.open(path..suffix,'wb'));f:write('keep'..suffix);f:close()
  end
  local a=api();a.readBytes=function() error('must not read') end
  local r=Dump.write(a,'game.exe',path,{confirmOverwrite=function(files)
    assert(#files==3);return false
  end})
  assert(r.status=='cancelled')
  for _,suffix in ipairs({'','.partial','.json'}) do
    local f=assert(io.open(path..suffix,'rb'));assert(f:read('*a')=='keep'..suffix);f:close()
  end
end)
test('confirmed overwrite preserves all three previous outputs and backup collisions',function()
  for _,suffix in ipairs({'','.partial','.json','.previous'}) do
    local f=assert(io.open(path..suffix,'wb'));f:write('old'..suffix);f:close()
  end
  local r=Dump.write(api(),'game.exe',path,{confirmOverwrite=function(files) assert(#files==3);return true end})
  assert(r.status=='complete' and #r.previous_files==3)
  for _,suffix in ipairs({'','.partial','.json'}) do
    local saved=path..suffix..'.previous'..(suffix=='' and '.1' or '')
    local f=assert(io.open(saved,'rb'));assert(f:read('*a')=='old'..suffix);f:close()
  end
  local f=assert(io.open(path..'.previous','rb'));assert(f:read('*a')=='old.previous');f:close()
end)
test('cancellation after confirmation retains old complete dump as backup',function()
  local f=assert(io.open(path,'wb'));f:write('old complete');f:close()
  local r=Dump.write(api(),'game.exe',path,{confirmOverwrite=function() return true end,
    progress=function() return false end})
  assert(r.status=='partial' and r.cancelled==true)
  f=assert(io.open(path..'.previous','rb'));assert(f:read('*a')=='old complete');f:close()
end)
print(count..' module dump tests passed')
