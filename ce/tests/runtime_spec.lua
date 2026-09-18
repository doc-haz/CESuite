package.path='ce/modules/?.lua;'..package.path
local U=require('util')
local P=require('parser')
local A=require('aob')
local D=require('disassembly')
local E=require('exporter')
local CT=require('ct')
local Env=require('environment')
local tests=0
local function test(name,fn)
  fn();tests=tests+1;print('PASS '..name)
end
local function eq(actual,expected) assert(actual==expected,tostring(actual)..' ~= '..tostring(expected)) end
local function report(source)
  local r={aobs=U.array(),scripts=U.array(),resources=U.array(),diagnostics=U.array(),records=U.array(),
    modules=U.array({{name='test.exe',base='0x1000',size=0x100}}),target={attached=true,pid=7,architecture='x64'}}
  if source then local s={id='s',text=source,record_key='r',language='AA'};r.scripts[1]=s;P.inspect(s,r) end
  return r
end
local function mock(addresses,options)
  options=options or {}
  local calls,freed={},{}
  local api={soExactValue=0,vtByteArray=8,rtRounded=0,fsmNotAligned=0,getOpenedProcessID=function() return 7 end}
  api.createMemScan=function()
    local ms={ErrorString=options.scanError or ''}
    if options.noErrorProperty then ms.ErrorString=nil end
    ms.firstScan=function(...) calls[#calls+1]={...};if options.firstError then error('firstScan failed') end end
    ms.waitTillDone=function() if options.changePid then api.getOpenedProcessID=function() return 8 end end end
    ms.destroy=function() freed[#freed+1]='scan' end
    return ms
  end
  api.createFoundList=function()
    local a={};for i,v in ipairs(addresses) do a[i-1]=v end
    return {Count=#addresses,Address=a,initialize=function() if options.initError then error('initialize failed') end end,
      destroy=function() freed[#freed+1]='list' end}
  end
  return api,calls,freed
end
local function context() return {synthetic=true} end
test('AA numbers are hex, Lua is decimal',function()
  eq(U.number('17'),23);eq(U.number('#17'),17);eq(U.number('0x17'),23);eq(17,17)
end)
test('quoted commas and nested arguments',function()
  local a=P.arguments('s,"a,b.exe",f(1,2),AA ??');eq(#a,4);eq(a[2],'"a,b.exe"')
end)
test('comments and embedded Lua never become scans',function()
  local r=report([=[
{ aobscan(fake,90) }
/* aobscan(fake,91) */
{$lua}
error('MUST NEVER EXECUTE')
aobscan(fake,92)
{$asm}
[ENABLE]
aobscan(real,AA ??) // comment
[DISABLE]
]=])
  eq(#r.aobs,1);eq(r.aobs[1].symbol,'real');eq(r.scripts[2].language,'Lua')
  local empty=false;for _,w in ipairs(r.diagnostics) do if w.rule=='EMPTY-DISABLE' then empty=true end end;assert(empty)
end)
test('all three scopes retain their exact scan bounds',function()
  local r=report('aobscan(p,AA BB)\naobscanmodule(m,"test.exe",AA BB)\naobscanregion(r,test.exe+10,test.exe+30,AA BB)')
  local api,calls,freed=mock({'1017'})
  A.validate(api,r,context)
  eq(#calls,3);eq(calls[1][6],0);eq(calls[1][7],-1)
  eq(calls[2][6],0x1000);eq(calls[2][7],0x1100)
  eq(calls[3][6],0x1010);eq(calls[3][7],0x1030)
  eq(calls[1][8],'*X*C*W');eq(calls[1][9],0)
  eq(r.aobs[1].uniqueness,'unique_current_scan');eq(#freed,6);eq(freed[1],'list');eq(freed[2],'scan')
end)
test('zero and multiple counts are explicit',function()
  for _,values in ipairs({{}, {'1000','1010'}}) do
    local r=report('aobscan(p,AA BB)');A.validate(mock(values),r,context)
    eq(r.aobs[1].match_count,#values);eq(r.aobs[1].uniqueness,#values==0 and 'no_match' or 'multiple_matches')
  end
end)
test('unresolved scope never broadens and arbitrary expressions never execute',function()
  local r=report('aobscanmodule(p,missing.exe,AA BB)\naobscanregion(r,os.execute("bad"),2000,AA BB)')
  local api,calls=mock({'1000'});A.validate(api,r,context);eq(#calls,0);eq(r.aobs[1].status,'unresolved');eq(r.aobs[2].status,'unresolved')
end)
test('hook candidate offset is AA hexadecimal, anchor remains separate',function()
  local r=report('aobscan(p,AA BB)\ndefine(h,p+17)\nh:\njmp allocated')
  A.validate(mock({'1000'}),r,context)
  eq(r.aobs[1].matches[1].signature_anchor,'0x1000');eq(r.aobs[1].hook_candidates[1].hook_address,'0x1017')
  eq(r.aobs[1].hook_candidates[1].evidence,'static_candidate')
end)
test('multiple matches do not resolve one hook address',function()
  local r=report('aobscan(p,AA BB)\np+10:\njmp x');A.validate(mock({'1000','2000'}),r,context)
  eq(r.aobs[1].hook_candidates[1].hook_address,U.null)
end)
test('scan failures remain unknown and release owned resources',function()
  for _,opt in ipairs({{firstError=true},{initError=true},{scanError='access failure'}}) do
    local r=report('aobscan(p,AA BB)');local api,_,freed=mock({},opt);A.validate(api,r,context)
    eq(r.aobs[1].status,'error');eq(r.aobs[1].match_count,U.null);eq(r.aobs[1].uniqueness,'unverified');eq(freed[#freed],'scan')
  end
end)
test('missing error API does not certify uniqueness',function()
  local r=report('aobscan(p,AA BB)');A.validate(mock({'1000'},{noErrorProperty=true}),r,context)
  eq(r.aobs[1].uniqueness,'unverified');eq(r.aobs[1].match_count,1)
end)
test('process change invalidates scan',function()
  local r=report('aobscan(p,AA BB)');A.validate(mock({'1000'},{changePid=true}),r,context)
  eq(r.aobs[1].status,'invalidated');eq(r.aobs[1].match_count,U.null);eq(#r.aobs[1].matches,0)
end)
test('export truncation preserves full count',function()
  local r=report('aobscan(p,AA BB)');local addresses={};for i=1,300 do addresses[i]=string.format('%X',0x1000+i) end
  A.validate(mock(addresses),r,context);eq(r.aobs[1].match_count,300);eq(#r.aobs[1].matches,256);eq(r.aobs[1].matches_truncated,true)
end)
test('unsupported patterns stay unverified',function()
  local r=report('aobscan(p,?? ??)\naobscan(q,pattern_macro)\naobscanmodule(broken,AA)')
  local api,calls=mock({});A.validate(api,r,context);eq(#calls,0)
  for _,a in ipairs(r.aobs) do eq(a.status,'unsupported') end
  eq(A.pattern('4? ?F **'),'4? ?f ??')
end)
test('define cycles cannot loop',function()
  eq(A.resolve('a',{}, {a='b',b='a'}),nil)
end)
test('RIP-relative subset and unknown coverage',function()
  eq(D.rip({0x48,0x8B,0x05,1,2,3,4},'x64'),'rip_relative')
  eq(D.rip({0x67,0x48,0x8B,0x05,1,2,3,4},'x64'),'not_rip_relative')
  eq(D.rip({0x48,0x8B,0x45,0x08},'x64'),'not_rip_relative')
  eq(D.rip({0xC5,0xFA},'x64'),'unknown');eq(D.rip({0x8B,0x05},'x86'),'not_applicable')
end)
test('disassembly metadata, forward alignment and cleanup',function()
  local destroyed=false
  local api={readBytes=function() return {0x90} end,createDisassembler=function()
    return {disassemble=function() return 'call 2000' end,getLastDisassembleData=function()
      return {bytes={0xE8,0,0,0,0},opcode='call',isCall=true,parameterValueType=1,parameterValue=0x2000} end,
      destroy=function() destroyed=true end}
  end}
  local c=D.capture(api,0x1000,'x64');eq(c.status,'partial');eq(#c.instructions,8);eq(c.instructions[2].address,'0x1005')
  eq(c.instructions[1].branch,'call');eq(c.instructions[1].parameter_address,'0x2000');assert(destroyed)
end)
test('JSON empty arrays, null, Unicode, escaping and cycles',function()
  eq(E.encode({a=U.array(),b={},c=U.null}),'{'..'"a":[],"b":{},"c":null}')
  eq(E.encode('ñ\n"\\'), '"ñ\\n\\"\\\\"')
  local t={};t.self=t;assert(not pcall(E.encode,t));assert(not pcall(E.encode,0/0))
end)
test('CT hierarchy, repeated IDs, selection and no activation',function()
  local parent={ID=1,Description='group',Type=0,OffsetCount=0}
  local child={ID=1,Description='script',Type=11,Script='[ENABLE]\naobscan(p,AA BB)\n[DISABLE]',Parent=parent,Active=false,OffsetCount=0}
  local al={Count=2,SelectedRecord=child,getMemoryRecord=function(i) return ({parent,child})[i+1] end}
  local api={vtAutoAssembler=11,getAddressList=function() return al end,getLuaEngine=function() return {mScript={Lines={Text='error("never execute")'}}} end}
  local r=report();CT.capture(api,r,false);eq(#r.records,2);eq(r.records[2].parent_key,'record-1');eq(child.Active,false)
  eq(r.ct.table_lua_status,'editor_snapshot');eq(#r.scripts,2)
  r=report();CT.capture(api,r,true);eq(#r.records,1);eq(r.records[1].key,'record-2')
end)
test('no process is not x86',function()
  local r=report();Env.capture({getOpenedProcessID=function() return 0 end},r)
  eq(r.target.architecture,'unknown');eq(r.target.attached,false)
end)
test('CE wrapper identity does not break hierarchy or selection',function()
  local api={vtAutoAssembler=11,getAddressList=function() return {Count=2,SelectedRecord={Index=1},
    getMemoryRecord=function(i) return {ID=1,Index=i,Type=0,Parent=i==1 and {Index=0} or nil} end} end}
  local r=report();CT.capture(api,r,true);eq(#r.records,1);eq(r.records[1].parent_key,'record-1')
end)
test('repeated symbols and defines do not invent a hook',function()
  local r=report('aobscan(p,AA BB)\naobscan(p,CC DD)\np+10:\njmp x\ndefine(a,10)\ndefine(a,20)\ndefine(a,30)')
  A.validate(mock({'1000'}),r,context);eq(#r.aobs[1].hook_candidates,0);eq(r.scripts[1].defines.a,false)
end)
test('bundle installs, replaces and cleans only its own menu; export is fresh',function()
  local installed,destroyed=0,0
  getMainForm=function() return {Menu={Items={add=function() installed=installed+1 end}}} end
  createMenuItem=function() return {add=function() end,destroy=function() destroyed=destroyed+1 end} end
  getOpenedProcessID=function() return 0 end
  getCEVersion=function() return 7.7 end
  local core=dofile('releases/CESuite_Core.lua');eq(installed,1)
  core=dofile('releases/CESuite_Core.lua');eq(installed,2);eq(destroyed,1)
  local r=core.analyze('export');eq(r.target.attached,false)
  core.export('ce/tests/generated-report.json')
  local fake=mock({'1010'})
  for k,v in pairs(fake) do _G[k]=v end
  process='test.exe';targetIs64Bit=function() return true end
  enumModules=function() return {{Name='test.exe',Address=0x1000,Is64Bit=true,PathToFile='synthetic/test.exe'}} end
  getModuleSize=function() return 0x100 end
  vtAutoAssembler=11
  getAddressList=function() return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
    return {ID=1,Description='Synthetic only',Type=11,OffsetCount=0,Script='[ENABLE]\naobscanmodule(p,test.exe,48 8B ??)\np+17:\njmp x\n[DISABLE]'} end} end
  getLuaEngine=function() return {mScript={Lines={Text='-- synthetic table Lua'}}} end
  readBytes=function() local b={};for i=1,48 do b[i]=0x90 end;return b end
  createDisassembler=function() return {disassemble=function() return 'nop' end,
    getLastDisassembleData=function() return {opcode='nop',bytes={0x90},isCall=false,isJump=false,isRet=false} end,destroy=function() end} end
  r=core.analyze('export');eq(r.aobs[1].uniqueness,'unique_current_scan')
  core.export('ce/tests/generated-observed.json')
  core.shutdown();eq(destroyed,2)
end)
print(string.format('%d Lua tests passed (synthetic CE API mocks; no live CE validation)',tests))
