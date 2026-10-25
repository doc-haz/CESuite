package.path='ce/modules/?.lua;'..package.path
-- Freeze observation timestamps only in the isolated fixture-generation state.
-- Production modules and standalone live observations retain the real clock.
if CESUITE_TEST_OUTPUT then
  local realDate=os.date
  os.date=function(format,...)
    if format=='!%Y-%m-%dT%H:%M:%SZ' then return '2026-10-22T00:00:00Z' end
    return realDate(format,...)
  end
  -- Fixture generation must be byte-reproducible: operational durations are
  -- non-deterministic in live use, so freeze the clock only in this mode.
  getTickCount=function() return 0 end
end

local U=require('util')
local P=require('parser')
local A=require('aob')
local D=require('disassembly')
local E=require('exporter')
local CT=require('ct')
local Env=require('environment')

local tests=0

local function test(name,fn)
  fn()
  tests=tests+1
  print('PASS '..name)
end

local function eq(actual,expected)
  assert(actual==expected,tostring(actual)..' ~= '..tostring(expected))
end

for _,case in ipairs({'numeric','text','missing','throwing'}) do
  test('P0-04 version evidence remains literal: '..case,function()
    local calls=0
    local api={getOpenedProcessID=function() return 0 end}
    if case~='missing' then
      api.getCEVersion=function()
        calls=calls+1
        if case=='throwing' then error('unavailable') end
        return case=='numeric' and 7.71 or '7.71'
      end
    end
    local core=assert(loadfile('ce/CESuite_Core.lua','t',
      setmetatable({api=api,require=require},{__index=_G})))()
    for _,mode in ipairs({'process','table','selected','validate','export'}) do
      local r=core.analyze(mode)
      local p=r.semantics_profile
      local expected=(case=='missing' or case=='throwing') and 'unknown' or '7.71'
      eq(r.ce_version,expected);eq(p.runtime_profile.api_version,r.ce_version)
      eq(p.runtime_profile.declared_version,U.null)
      eq(p.runtime_profile.declared_version_basis,'not_available')
      eq(p.runtime_profile.file_version,U.null);eq(p.runtime_profile.binary_sha256,U.null)
      eq(p.source_runtime_equivalence,'unverified')
      -- Every analysis receives fresh metadata, including nested release-note rows.
      p.source_profile.commit='mutated'
      p.known_post_source_changes[1].runtime_validation='mutated'
      local fresh=require('semantics').profile(r.ce_version)
      eq(fresh.source_profile.commit,'ec45d5f47f92a239ba0bf51ec5d04a7509c3fd37')
      eq(fresh.known_post_source_changes[1].runtime_validation,'not_performed')
    end
    eq(calls,case=='missing' and 0 or 5)
  end)
end

test('P0-04 metadata leaves existing report semantics unchanged',function()
  local api={getOpenedProcessID=function() return 0 end,vtAutoAssembler=11,
    getAddressList=function() return {Count=1,getMemoryRecord=function()
      return {ID=1,Type=11,OffsetCount=0,Script='[ENABLE]\nalloc(buffer,16)\nregistersymbol(buffer)\n[DISABLE]\ndealloc(buffer)'}
    end} end}
  local function core(loader)
    return assert(loadfile('ce/CESuite_Core.lua','t',
      setmetatable({api=api,require=loader},{__index=_G})))()
  end
  local normal=core(require).analyze('table')
  local without=core(function(name)
    if name=='semantics' then return {profile=function() return nil end} end
    return require(name)
  end).analyze('table')
  assert(#normal.dependencies>0 and #normal.resources>0)
  for _,row in ipairs(normal.dependencies) do eq(row.status,'unverified') end
  normal.semantics_profile=nil
  normal.generated_at=without.generated_at;normal.completed_at=without.completed_at
  -- Timings are non-deterministic operational metadata; compare evidence only.
  normal.operation=nil;without.operation=nil
  eq(E.encode(normal),E.encode(without))
end)

test('operation telemetry is separated and never changes evidence',function()
  local api={getOpenedProcessID=function() return 0 end,vtAutoAssembler=11,
    getAddressList=function() return {Count=1,getMemoryRecord=function()
      return {ID=1,Type=11,OffsetCount=0,Script='[ENABLE]\nalloc(buffer,16)\n[DISABLE]\ndealloc(buffer)'}
    end} end}
  local function load()
    return assert(loadfile('ce/CESuite_Core.lua','t',
      setmetatable({api=api,require=require},{__index=_G})))()
  end
  local instrumented=load().analyze('table')
  assert(instrumented.operation,'operation block missing')
  eq(instrumented.operation.provenance,'instrumented')
  eq(instrumented.operation.cancelled,false)
  eq(instrumented.operation.metrics.items_total,0)
  assert(type(instrumented.operation.metrics.parse_ms)=='number' and
    instrumented.operation.metrics.parse_ms>=0,'parse_ms must be non-negative')
  assert(type(instrumented.operation.metrics.scan_ms)=='number' and
    instrumented.operation.metrics.scan_ms>=0,'scan_ms must be non-negative')
  eq(instrumented.operation.source_complete,false,'no live target means incomplete source')
  assert(type(instrumented.operation.metrics.source_bytes)=='number' and
    instrumented.operation.metrics.source_bytes>0,'source_bytes expected')
  -- With no clock the report keeps identical evidence and null timings.
  local savedGet,savedClock=getTickCount,os.clock
  getTickCount=nil
  os.clock=function() error('clock unavailable') end
  local degraded=load().analyze('table')
  getTickCount,os.clock=savedGet,savedClock
  eq(degraded.operation.metrics.parse_ms,U.null)
  eq(degraded.operation.timing_source,'unavailable')
  instrumented.operation=nil;degraded.operation=nil
  instrumented.generated_at=degraded.generated_at
  instrumented.completed_at=degraded.completed_at
  eq(E.encode(instrumented),E.encode(degraded))
end)

local function report(source)
  local r={
    aobs=U.array(),
    scripts=U.array(),
    resources=U.array(),
    diagnostics=U.array(),
    records=U.array(),
    modules=U.array({
      {
        name='test.exe',
        base='0x1000',
        size=0x100
      }
    }),
    target={
      attached=true,
      pid=7,
      architecture='x64'
    }
  }

  if source then
    local s={
      id='s',
      text=source,
      record_key='r',
      language='AA'
    }

    r.scripts[1]=s
    P.inspect(s,r)
  end

  return r
end

local function mock(addresses,options)
  options=options or {}

  local calls,freed={},{}

  local api={
    soExactValue=0,
    vtByteArray=8,
    rtRounded=0,
    fsmNotAligned=0,
    getOpenedProcessID=function()
      return 7
    end
  }

  api.createMemScan=function()
    local ms={
      ErrorString=options.scanError or ''
    }

    if options.noErrorProperty then
      ms.ErrorString=nil
    end

    ms.firstScan=function(...)
      calls[#calls+1]={...}

      if options.firstError then
        error('firstScan failed')
      end
    end

    ms.waitTillDone=function()
      if options.changePid then
        api.getOpenedProcessID=function()
          return 8
        end
      end
    end

    ms.destroy=function()
      freed[#freed+1]='scan'
    end

    return ms
  end

  api.createFoundList=function()
    local a={}

    for i,v in ipairs(addresses) do
      a[i-1]=v
    end

    return {
      Count=#addresses,
      Address=a,
      initialize=function()
        if options.initError then
          error('initialize failed')
        end
      end,
      destroy=function()
        freed[#freed+1]='list'
      end
    }
  end

  return api,calls,freed
end

local function context()
  return {
    synthetic=true
  }
end

test('summary collapses same-line locations but preserves every AA and Lua occurrence',function()
  local S=require('dependencies')
  local r=report('registersymbol(shared,shared)\n{$lua}\nprint(GAME_STATE,GAME_STATE)\n{$asm}')
  local before=E.encode(r)
  local g=S.summarize(r.dependencies)
  eq(#r.dependencies,6);eq(#g,3)
  for _,v in ipairs(g) do
    eq(v.occurrence_count,2);eq(v.location_count,1);eq(v.status,'unverified')
    eq(v.locations[1].occurrence_count,2);eq(#v.locations[1].occurrence_indices,2)
  end
  eq(g[1].locations[1].occurrence_indices[1],1)
  eq(g[1].locations[1].occurrence_indices[2],3)
  eq(E.encode(r),before);eq(E.encode(S.summarize(r.dependencies)),E.encode(g))
end)

test('summary preserves cross-script provenance sections and both relations',function()
  local S=require('dependencies')
  local r=report('[ENABLE]\n{$lua}\nGAME_STATE=GAME_STATE or {}\n[DISABLE]\nGAME_STATE=nil\n{$asm}')
  P.inspect({id='second:script',text='[ENABLE]\n{$lua}\nprint(GAME_STATE)\n{$asm}'},r)
  local g=S.summarize(r.dependencies)
  eq(#g,2);eq(g[1].relation,'provides');eq(g[1].occurrence_count,1)
  eq(g[2].relation,'requires');eq(g[2].occurrence_count,3);eq(g[2].location_count,3)
  eq(table.concat(g[2].script_ids,','),'s,second:script')
  eq(table.concat(g[2].sections,','),'enable,disable')
  eq(g[2].locations[1].line,3);eq(g[2].locations[2].section,'disable')
  eq(g[2].locations[3].script_id,'second:script')
  eq(_G.GAME_STATE,nil)
end)

test('summary does not conflate namespaces case commands or separate lines',function()
  local S=require('dependencies')
  local r=report('alloc(GAME_STATE,16)\nlabel(GAME_STATE)\nlabel(GAME_STATE)\nlabel(game_state)\n{$lua}\nGAME_STATE={}\n{$asm}')
  local g=S.summarize(r.dependencies)
  eq(#g,4);eq(g[1].kind,'resource');eq(g[2].kind,'symbol')
  eq(g[2].occurrence_count,3);eq(g[2].location_count,3)
  eq(g[3].name,'game_state');eq(g[4].kind,'lua_global')
  local copy={}
  for k,v in pairs(r.dependencies[2]) do copy[k]=v end
  copy.command='label';r.dependencies[#r.dependencies+1]=copy
  eq(S.summarize(r.dependencies)[2].location_count,4)
end)

test('summary is empty for absent dependencies and excluded false positives',function()
  local S=require('dependencies')
  eq(E.encode(S.summarize(nil)),'[]')
  local r=report([=[{$lua}
error('MUST NEVER EXECUTE')
local TEST_LOCAL={};print(TEST_LOCAL)
local t={TEST_KEY=true};t.TEST_FIELD=true
local s="TEST_STRING"
-- TEST_COMMENT={}
{$asm}
label("quoted")
label(DEADBEEF)
registersymbol(*)
]=])
  eq(E.encode(S.summarize(r.dependencies)),'[]')
end)

test('dependency occurrences retain provenance and unresolved lifecycle',function()
  local r=report('define(alias,external)\n[ENABLE]\nalloc(buffer,1024,anchor)\nregistersymbol(buffer,shared)\nlabel(returnhere)\nreturnhere:\n[DISABLE]\nunregistersymbol(buffer)\ndealloc(buffer)')
  local d=r.dependencies
  eq(#d,13)
  eq(d[1].name,'alias');eq(d[1].relation,'provides');eq(d[1].section,'common')
  eq(d[2].name,'external');eq(d[2].relation,'requires')
  eq(d[3].kind,'resource');eq(d[3].line,3);eq(d[3].section,'enable')
  eq(d[5].name,'anchor');eq(d[5].relation,'requires')
  eq(d[6].kind,'symbol');eq(d[7].kind,'registered_symbol')
  eq(d[10].command,'label');eq(d[10].relation,'provides')
  eq(d[11].command,'address_label');eq(d[11].relation,'requires')
  eq(d[12].section,'disable');eq(d[12].line,8)
  eq(d[13].kind,'resource');eq(d[13].relation,'requires')
  eq(#r.resources,4);eq(#r.scripts[1].labels,1)
  for _,v in ipairs(d) do
    eq(v.source,'lexical');eq(v.status,'unverified');eq(v.script_id,'s')
  end
end)

test('dependencies never execute source or interpret Lua comments and expressions',function()
  local r=report([[// alloc(fake,1)
{ registersymbol(fake) }
/* label(fake) */
{$lua}
error('INSPECTED LUA MUST NOT RUN')
alloc(fake,1)
{$asm}
alloc(buffer+10,1)
registersymbol(*)
unregistersymbol(*)
dealloc()
label("quoted")
DEADBEEF:
buffer+10:
define(alias,external+10)
alloc(buffer)
aobscan(anchor)
]])
  -- Unknown Lua call/root names are now generic requirements, never AA resources.
  eq(#r.dependencies,3);eq(r.dependencies[1].name,'alloc')
  eq(r.dependencies[1].kind,'lua_global');eq(r.dependencies[1].relation,'requires')
  eq(r.dependencies[2].name,'fake');eq(r.dependencies[3].name,'alias')
  for _,resource in ipairs(r.resources) do assert(resource.command~='lua_rva_hook') end
  eq(r.scripts[1].dynamic,true)
end)

test('AOB global resources and duplicate names stay lexical in every section',function()
  local r=report('aobscan(anchor,90)\naobscanmodule(modanchor,test.exe,90)\naobscanregion(regionanchor,1000,2000,90)\nglobalalloc(shared,16)\n[DISABLE]\nalloc(buffer,16)\nlabel(shared)')
  eq(#r.dependencies,7)
  eq(r.dependencies[1].name,'anchor');eq(r.dependencies[2].name,'modanchor')
  eq(r.dependencies[3].kind,'resource');eq(r.dependencies[5].section,'disable')
  P.inspect({id='second',text='registersymbol(shared)\nregistersymbol(shared)'},r)
  eq(#r.dependencies,11)
  eq(r.dependencies[8].script_id,'second');eq(r.dependencies[10].line,2)
  eq(r.dependencies[8].status,'unverified')
end)

test('generic globals provide without a naming prefix or capitalization rule',function()
  local r=report('{$lua}\nGAME_STATE={}\nmodPlayer=1\n_privateFlag=false\nfunction customHelper() end\n{$asm}')
  eq(#r.dependencies,4)
  local names={'GAME_STATE','modPlayer','_privateFlag','customHelper'}
  for i,d in ipairs(r.dependencies) do
    eq(d.name,names[i]);eq(d.relation,'provides')
    eq(d.source,'lua_lexical');eq(d.status,'unverified')
  end
end)

test('generic reads unknown calls and member roots remain unverified requirements',function()
  local r=report('{$lua}\nlocal x=MOD_PLAYER\nprint(modPlayer.value)\ncustomHelper(TEST_GLOBAL)\n{$asm}')
  local names={'MOD_PLAYER','modPlayer','customHelper','TEST_GLOBAL'}
  eq(#r.dependencies,#names)
  for i,d in ipairs(r.dependencies) do
    eq(d.name,names[i]);eq(d.relation,'requires');eq(d.status,'unverified')
  end
end)

test('locals parameters loop variables and implicit method self are excluded',function()
  local r=report([=[{$lua}
local first,second={},{}
local function helper(param) return param,first,second end
for index=1,10 do helper(index) end
for key,value in pairs({}) do helper(key,value) end
local object={}
function object:method(argValue) self.value=argValue end
local constant <const> = 1
print(constant)
{$asm}]=])
  eq(#r.dependencies,0)
end)

test('Lua keywords and standard environment names are excluded without execution',function()
  local names=require('luanames')
  local text={'{$lua}',"error('MUST NOT EXECUTE')"}
  for name in pairs(names.builtins) do text[#text+1]='print('..name..')' end
  text[#text+1]='if true and not false then repeat break until nil else return end'
  text[#text+1]='{$asm}'
  eq(#report(table.concat(text,'\n')).dependencies,0)
end)

test('known CE globals APIs and constants are excluded by exact spelling',function()
  local r=report([=[{$lua}
if syntaxcheck then return end
local address=getAddressSafe(process)
local bytes=readBytes(address,16,true)
local scan=AOBScan('90')
pause();unpause();speedhack_setSpeed(1)
local record=memrec or getAddressList().SelectedRecord
local t=createTimer(nil);t.Enabled=false
print(MainForm,AddressList,vtByte,caHide,mrOK,mbOK,alClient,VK_F1)
getCustomValue(TEST_GLOBAL)
{$asm}]=])
  eq(#r.dependencies,2);eq(r.dependencies[1].name,'getCustomValue')
  eq(r.dependencies[2].name,'TEST_GLOBAL')
end)

test('generic comments and strings stay masked while real names are retained',function()
  local r=report([==[{$lua}
-- COMMENT_GLOBAL={}
--[=[ LONG_COMMENT_GLOBAL ]=]
local s="STRING_GLOBAL"
local t=[=[LONG_STRING_GLOBAL]=]
print(TEST_GLOBAL)
{$asm}]==])
  eq(#r.dependencies,1);eq(r.dependencies[1].name,'TEST_GLOBAL')
end)

test('numerals labels and field names do not become generic globals',function()
  local r=report([=[{$lua}
local n={0xFF,0x1.Ap+2,0x.8p1,0x.8,2e10,.5e-2,17.25}
::retryLabel::
if false then goto retryLabel end
local t={key=1};t.field=2
print('prefix'..GAME_STATE..MOD_PLAYER)
{$asm}]=])
  eq(#r.dependencies,2);eq(r.dependencies[1].name,'GAME_STATE')
  eq(r.dependencies[2].name,'MOD_PLAYER')
end)

test('ambient globals do not change lexical dependency results',function()
  local original=rawget(_G,'TEST_AMBIENT')
  local text='{$lua}\nprint(TEST_AMBIENT)\n{$asm}'
  local before=E.encode(report(text).dependencies)
  _G.TEST_AMBIENT=function() error('must not call ambient values') end
  local after=E.encode(report(text).dependencies)
  _G.TEST_AMBIENT=original
  eq(before,after);eq(#report(text).dependencies,1)
end)

test('Lua globals produce lexical occurrences with parent lines and sections',function()
  local r=report('[ENABLE]\n{$lua}\nlocal s=MOD_PLAYER\nassert(MOD_PLAYER.enabled)\nMOD_GODMODE={enabled=true}\nMOD_GODMODE.enabled=false\n[DISABLE]\nMOD_GODMODE=nil\n{$asm}')
  local d=r.dependencies
  eq(#d,5);eq(d[1].line,3);eq(d[1].name,'MOD_PLAYER')
  eq(d[1].relation,'requires');eq(d[3].relation,'provides')
  eq(d[4].relation,'requires');eq(d[5].relation,'requires')
  eq(d[5].section,'disable');eq(d[5].line,8)
  for _,v in ipairs(d) do
    eq(v.kind,'lua_global');eq(v.source,'lua_lexical');eq(v.status,'unverified');eq(v.script_id,'s')
  end
end)

test('Lua strings comments fields and locals do not create global dependencies',function()
  local r=report([==[{$lua}
-- TEST_COMMENT={}
--[=[ TEST_COMMENT2={}
{$asm}
[DISABLE]
]=]
local text="escaped \" TEST_STRING"
local long=[===[TEST_LONG
{$asm}
[DISABLE]
]===]
local TEST_LOCAL, TEST_LOCAL2={},{}
print(TEST_LOCAL,TEST_LOCAL2)
local f=function(TEST_PARAM) return TEST_PARAM end
for TEST_LOOP in pairs({}) do print(TEST_LOOP) end
local t={TEST_KEY=true, TEST_KEY2=false; TEST_KEY3=true}
t.TEST_FIELD=true
t:TEST_METHOD()
local s=TEST_REAL -- TEST_FAKE
{$asm}
]==])
  eq(#r.dependencies,1);eq(r.dependencies[1].name,'TEST_REAL')
  eq(r.dependencies[1].section,'common');eq(r.dependencies[1].line,19)
end)

test('Lua comparisons and self reads stay requirements and never execute',function()
  local r=report([=[{$lua}
error('MUST NOT EXECUTE')
GAME_STATE=GAME_STATE or {}
assert(GAME_STATE==nil or TEST_OTHER~=nil)
{$asm}
]=])
  eq(#r.dependencies,4);eq(r.dependencies[1].relation,'provides')
  for i=2,4 do eq(r.dependencies[i].relation,'requires') end
  eq(_G.GAME_STATE,nil)
end)

test('Lua long literals unfinished comments and chunk boundaries stay conservative',function()
  local r=report('{$lua}\nlocal x="TEST_FAKE"; TEST_FIRST={}\n{$asm}\n[DISABLE]\n{$lua}\nlocal s=TEST_FIRST\n--[==[ TEST_NEVER={}\nTEST_NEVER2={}\n')
  eq(#r.dependencies,2);eq(r.dependencies[1].relation,'provides')
  eq(r.dependencies[2].section,'disable');eq(r.dependencies[2].line,6)
end)

test('Lua named global functions and AA-looking literals remain lexical',function()
  local r=report('[ENABLE]\n{$lua}\nfunction TEST_HELPER() return TEST_PLAYER end\nlocal s=[=[\n{$lua}\n[DISABLE]\n]=]\nTEST_LAST={}\n{$asm}')
  eq(#r.dependencies,3);eq(r.dependencies[1].relation,'provides')
  eq(r.dependencies[2].relation,'requires');eq(r.dependencies[3].name,'TEST_LAST')
  eq(r.dependencies[3].section,'enable');eq(r.dependencies[3].line,8)
end)

test('AA numbers are hex, Lua is decimal',function()
  eq(U.number('17'),23)
  eq(U.number('#17'),17)
  eq(U.number('0x17'),23)
  eq(17,17)
end)

test('quoted commas and nested arguments',function()
  local a=P.arguments('s,"a,b.exe",f(1,2),AA ??')

  eq(#a,4)
  eq(a[2],'"a,b.exe"')
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

  eq(#r.aobs,1)
  eq(r.aobs[1].symbol,'real')
  eq(r.scripts[2].language,'Lua')

  local empty=false

  for _,w in ipairs(r.diagnostics) do
    if w.rule=='EMPTY-DISABLE' then
      empty=true
    end
  end

  assert(empty)
end)

test('classic scopes retain exact bounds; post-source region stays opaque',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'aobscanmodule(m,"test.exe",AA BB)\n'..
    'aobscanregion(r,test.exe+10,test.exe+30,AA BB)'
  )

  local api,calls,freed=mock({'1017'})

  A.validate(api,r,context)

  eq(#calls,2)
  eq(#r.aobs,2)
  eq(calls[1][6],0)
  eq(calls[1][7],-1)

  eq(calls[2][6],0x1000)
  eq(calls[2][7],0x1100)


  eq(calls[1][8],'*X*C*W')
  eq(calls[1][9],0)

  eq(r.aobs[1].uniqueness,'unique_current_scan')
  eq(#freed,4)
  eq(freed[1],'list')
  eq(freed[2],'scan')
end)

test('zero and multiple counts are explicit',function()
  for _,values in ipairs({
    {},
    {'1000','1010'}
  }) do
    local r=report('aobscan(p,AA BB)')

    A.validate(mock(values),r,context)

    eq(r.aobs[1].match_count,#values)
    eq(
      r.aobs[1].uniqueness,
      #values==0 and 'no_match' or 'multiple_matches'
    )
  end
end)

test('unresolved scope never broadens and arbitrary expressions never execute',function()
  local r=report(
    'aobscanmodule(p,missing.exe,AA BB)\n'..
    'aobscanregion(r,os.execute("bad"),2000,AA BB)'
  )

  local api,calls=mock({'1000'})

  A.validate(api,r,context)

  eq(#calls,0)
  eq(r.aobs[1].status,'unresolved')
  eq(#r.aobs,1)
end)

test('hook candidate offset is AA hexadecimal, anchor remains separate',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'define(h,p+17)\n'..
    'h:\n'..
    'jmp allocated'
  )

  A.validate(mock({'1000'}),r,context)

  eq(r.aobs[1].matches[1].signature_anchor,'0x1000')
  eq(r.aobs[1].hook_candidates[1].hook_address,'0x1017')
  eq(r.aobs[1].hook_candidates[1].evidence,'static_candidate')
end)

test('multiple matches do not resolve one hook address',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'p+10:\n'..
    'jmp x'
  )

  A.validate(mock({'1000','2000'}),r,context)

  eq(
    r.aobs[1].hook_candidates[1].hook_address,
    U.null
  )
end)

test('scan failures remain unknown and release owned resources',function()
  for _,opt in ipairs({
    {firstError=true},
    {initError=true},
    {scanError='access failure'}
  }) do
    local r=report('aobscan(p,AA BB)')
    local api,_,freed=mock({},opt)

    A.validate(api,r,context)

    eq(r.aobs[1].status,'error')
    eq(r.aobs[1].match_count,U.null)
    eq(r.aobs[1].uniqueness,'unverified')
    eq(freed[#freed],'scan')
  end
end)

test('missing error API does not certify uniqueness',function()
  local r=report('aobscan(p,AA BB)')

  A.validate(
    mock(
      {'1000'},
      {noErrorProperty=true}
    ),
    r,
    context
  )

  eq(r.aobs[1].uniqueness,'unverified')
  eq(r.aobs[1].match_count,1)
end)

test('process change invalidates scan',function()
  local r=report('aobscan(p,AA BB)')

  A.validate(
    mock(
      {'1000'},
      {changePid=true}
    ),
    r,
    context
  )

  eq(r.aobs[1].status,'invalidated')
  eq(r.aobs[1].match_count,U.null)
  eq(#r.aobs[1].matches,0)
end)

test('export truncation preserves full count',function()
  local r=report('aobscan(p,AA BB)')
  local addresses={}

  for i=1,300 do
    addresses[i]=string.format(
      '%X',
      0x1000+i
    )
  end

  A.validate(
    mock(addresses),
    r,
    context
  )

  eq(r.aobs[1].match_count,300)
  eq(#r.aobs[1].matches,256)
  eq(r.aobs[1].matches_truncated,true)
end)

test('unsupported patterns stay unverified',function()
  local r=report(
    'aobscan(p,?? ??)\n'..
    'aobscan(q,pattern_macro)\n'..
    'aobscanmodule(broken,AA)'
  )

  local api,calls=mock({})

  A.validate(api,r,context)

  eq(#calls,0)

  for _,a in ipairs(r.aobs) do
    eq(a.status,'unsupported')
  end

  eq(A.pattern('4? ?F **'),'4? ?f ??')
end)

test('define cycles cannot loop',function()
  eq(
    A.resolve(
      'a',
      {},
      {
        a='b',
        b='a'
      }
    ),
    nil
  )
end)

test('RIP-relative subset and unknown coverage',function()
  eq(
    D.rip(
      {0x48,0x8B,0x05,1,2,3,4},
      'x64'
    ),
    'rip_relative'
  )

  eq(
    D.rip(
      {0x67,0x48,0x8B,0x05,1,2,3,4},
      'x64'
    ),
    'not_rip_relative'
  )

  eq(
    D.rip(
      {0x48,0x8B,0x45,0x08},
      'x64'
    ),
    'not_rip_relative'
  )

  eq(
    D.rip(
      {0xC5,0xFA},
      'x64'
    ),
    'unknown'
  )

  eq(
    D.rip(
      {0x8B,0x05},
      'x86'
    ),
    'not_applicable'
  )
end)

test('disassembly wrapper omits context without CE API access',function()
  local calls=0
  local api=setmetatable({}, {__index=function()
    calls=calls+1
    error('No CE API access allowed')
  end})
  eq(D.capture(api,0x1000,'x64'),nil)
  eq(calls,0)
end)

for _,mode in ipairs({'table','selected','validate','export','dependency_summary'}) do
  test('P0-03 passive core never disassembles: '..mode,function()
    local api,scans=mock({'1010'})
    local calls=0
    local function trap()
      calls=calls+1
      error('Unaudited API or disassembly wrapper invoked')
    end
    for _,name in ipairs({'disassemble','createDisassembler','getVisibleDisassembler',
      'getDefaultDisassembler','getInstructionSize','splitDisassembledString',
      'getPreviousOpcode','getLastDisassembleData','readBytes','getAddress',
      'getAddressSafe','getNameFromAddress','autoAssemble','autoAssembleCheck',
      'loadTable','saveTable','getLuaEngine'}) do api[name]=trap end
    api.getCEVersion=function() return 7.7 end
    api.targetIs64Bit=function() return true end
    api.enumModules=function() return {{Name='test.exe',Address=0x1000}} end
    api.getModuleSize=function() return 0x100 end
    api.vtAutoAssembler=11
    local record=setmetatable({ID=1,Index=0,Type=11,OffsetCount=0,Script=[[
[ENABLE]
aobscanmodule(p,test.exe,48 8B ??)
p+17:
{$lua}
error('INSPECTED SOURCE MUST NEVER EXECUTE')
P0_STATE=P0_STATE or {}
{$asm}
[DISABLE]
]]}, {__index=function(_,key)
      if key=='Address' or key=='Value' or key=='CurrentAddress' then return trap() end
    end})
    api.getAddressList=function()
      return {Count=1,SelectedRecord=record,getMemoryRecord=function() return record end}
    end
    local function loader(name)
      if name=='disassembly' then return {capture=trap} end
      return require(name)
    end
    local core=assert(loadfile('ce/CESuite_Core.lua','t',
      setmetatable({api=api,require=loader},{__index=_G})))()
    local r
    if mode=='export' then
      local path=os.tmpname()
      core.export(path)
      local f=assert(io.open(path,'rb'));local text=f:read('*a');f:close();os.remove(path)
      assert(not text:find('"context":',1,true))
      r=core.last_report
    else
      r=core.analyze(mode=='dependency_summary' and 'table' or mode)
    end
    eq(#r.records,1);eq(#r.scripts,2);eq(#r.aobs,1)
    assert(#r.dependencies>0 and #r.dependency_summary>0)
    if mode=='validate' or mode=='export' then
      eq(#scans,1);eq(r.aobs[1].match_count,1)
      eq(r.aobs[1].uniqueness,'unique_current_scan')
      eq(r.aobs[1].matches[1].signature_anchor,'0x1010')
      eq(r.aobs[1].matches[1].context,nil)
      eq(r.aobs[1].hook_candidates[1].hook_address,'0x1027')
      eq(r.aobs[1].hook_candidates[1].context,nil)
    else eq(#scans,0) end
    eq(calls,0)
  end)
end

test('JSON empty arrays, null, Unicode, escaping and cycles',function()
  eq(
    E.encode({
      a=U.array(),
      b={},
      c=U.null
    }),
    '{'..
    '"a":[],'..
    '"b":{},'..
    '"c":null}'
  )

  eq(
    E.encode('ñ\n"\\'),
    '"ñ\\n\\"\\\\"'
  )

  local t={}
  t.self=t

  assert(not pcall(E.encode,t))
  assert(not pcall(E.encode,0/0))
end)

test('CT hierarchy, repeated IDs, selection and no activation',function()
  local parent={
    ID=1,
    Description='group',
    Type=0,
    OffsetCount=0
  }

  local child={
    ID=1,
    Description='script',
    Type=11,
    Script='[ENABLE]\naobscan(p,AA BB)\n[DISABLE]',
    Parent=parent,
    Active=false,
    OffsetCount=0
  }

  local al={
    Count=2,
    SelectedRecord=child,

    getMemoryRecord=function(i)
      return ({
        parent,
        child
      })[i+1]
    end
  }

  local api={
    vtAutoAssembler=11,

    getAddressList=function()
      return al
    end,

    getLuaEngine=function()
      return {
        mScript={
          Lines={
            Text='error("never execute")'
          }
        }
      }
    end
  }

  local r=report()

  CT.capture(
    api,
    r,
    false
  )

  eq(#r.records,2)
  eq(r.records[2].parent_key,'record-1')
  eq(child.Active,false)
  eq(r.ct.table_lua_status,'unavailable')
  eq(#r.scripts,1)

  r=report()

  CT.capture(
    api,
    r,
    true
  )

  eq(#r.records,1)
  eq(r.records[1].key,'record-2')
end)

for _,selectedOnly in ipairs({false,true}) do
  for _,throws in ipairs({false,true}) do
    test('passive table Lua unavailable: '..(selectedOnly and 'selected' or 'full')..(throws and ' throwing trap' or ' editor trap'),function()
      local calls,windows,editorReads=0,0,0
      local engineText='error("LUA ENGINE TEXT MUST NOT EXECUTE") -- ENGINE_ONLY_SENTINEL'
      local source='[ENABLE]\n{$lua}\nerror("INSPECTED SOURCE MUST NOT EXECUTE")\n{$asm}\n[DISABLE]'
      local parent={ID=1,Index=0,Description='Group',Type=0,OffsetCount=0}
      local child={ID=2,Index=1,Parent=parent,Description='AA source',Type=11,
        Script=source,Active=false,OffsetCount=1,OffsetText={[0]='10'}}
      local api={vtAutoAssembler=11,getAddressList=function()
        return {Count=2,SelectedRecord=child,LoadedTableVersion=45,
          getMemoryRecord=function(i) return ({parent,child})[i+1] end}
      end,getLuaEngine=function()
        calls=calls+1
        windows=windows+1
        if throws then error('Passive capture opened Lua Engine') end
        return setmetatable({},{__index=function(_,key)
          if key=='mScript' then
            editorReads=editorReads+1
            return {Lines={Text=engineText}}
          end
        end})
      end}
      local r=report()
      CT.capture(api,r,selectedOnly)
      eq(calls,0)
      eq(windows,0)
      eq(editorReads,0)
      eq(r.ct.status,'captured')
      eq(r.ct.table_lua_status,'unavailable')
      eq(r.ct.selection_only,selectedOnly)
      eq(r.ct.loaded_table_version,45)
      eq(#r.records,selectedOnly and 1 or 2)
      local row=r.records[#r.records]
      eq(row.key,'record-2')
      eq(row.parent_key,'record-1')
      eq(row.offsets[1],'10')
      eq(child.Active,false)
      eq(#r.scripts,2)
      eq(r.scripts[2].language,'Lua')
      eq(r.scripts[2].origin,'embedded')
      eq(row.scripts[1],r.scripts[1].id)
      eq(r.scripts[1].language,'AA')
      eq(r.scripts[1].origin,'MemoryRecord.Script')
      eq(r.scripts[1].text,source)
      assert(not E.encode(r):find('ENGINE_ONLY_SENTINEL',1,true))
      if not selectedOnly then
        local warned=false
        for _,d in ipairs(r.diagnostics) do
          if d.rule=='TABLE-LUA-UNAVAILABLE' then warned=true end
        end
        assert(warned)
      end
    end)
  end
end

for _,dynamic in ipairs({false,true}) do
  test('passive capture never reads Address: '..(dynamic and 'dynamic offsets' or 'simple record'),function()
    local reads=0
    local source='[ENABLE]\n{$lua}\nerror("INSPECTED SOURCE MUST NOT EXECUTE")\n{$asm}\nregistersymbol(example)\n[DISABLE]'
    local record=setmetatable({
      ID=42,Index=0,Description='Passive fixture',Type=11,Active=false,
      Script=source,OffsetCount=dynamic and 2 or 0,
      OffsetText=dynamic and {[0]='10',[1]='error("DYNAMIC OFFSET MUST NOT EXECUTE")'} or {}
    },{__index=function(_,key)
      if key=='Address' then reads=reads+1;error('Address getter accessed') end
      if key=='CurrentAddress' or key=='Value' or key=='Offset' then
        error('Unsafe replacement property accessed: '..key)
      end
    end})
    local api={vtAutoAssembler=11,getAddressList=function()
      return {Count=1,SelectedRecord=record,LoadedTableVersion=45,
        getMemoryRecord=function() return record end}
    end}
    for _,selectedOnly in ipairs({false,true}) do
      local r=report()
      CT.capture(api,r,selectedOnly)
      eq(reads,0)
      eq(r.ct.status,'captured')
      eq(r.ct.selection_only,selectedOnly)
      eq(r.ct.loaded_table_version,45)
      eq(#r.records,1)
      local row=r.records[1]
      eq(row.address,U.null)
      eq(row.id,42)
      eq(row.description,'Passive fixture')
      eq(row.variable_type,11)
      eq(row.active,false)
      eq(#row.offsets,dynamic and 2 or 0)
      if dynamic then
        eq(row.offsets[1],'10')
        eq(row.offsets[2],record.OffsetText[1])
      end
      eq(#row.scripts,1)
      eq(r.scripts[1].text,source)
      eq(r.dependencies[1].name,'example')
      assert(E.encode(r):find('"address":null',1,true))
    end
    eq(reads,0)
  end)
end

test('no process is not x86',function()
  local r=report()

  Env.capture(
    {
      getOpenedProcessID=function()
        return 0
      end
    },
    r
  )

  eq(r.target.architecture,'unknown')
  eq(r.target.attached,false)
end)

test('CE wrapper identity does not break hierarchy or selection',function()
  local api={
    vtAutoAssembler=11,

    getAddressList=function()
      return {
        Count=2,
        SelectedRecord={
          Index=1
        },

        getMemoryRecord=function(i)
          return {
            ID=1,
            Index=i,
            Type=0,
            Parent=i==1 and {
              Index=0
            } or nil
          }
        end
      }
    end
  }

  local r=report()

  CT.capture(
    api,
    r,
    true
  )

  eq(#r.records,1)
  eq(r.records[1].parent_key,'record-1')
end)

test('repeated symbols and defines do not invent a hook',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'aobscan(p,CC DD)\n'..
    'p+10:\n'..
    'jmp x\n'..
    'define(a,10)\n'..
    'define(a,20)\n'..
    'define(a,30)'
  )

  A.validate(
    mock({'1000'}),
    r,
    context
  )

  eq(#r.aobs[1].hook_candidates,0)
  eq(r.scripts[1].defines.a,false)
end)

test('Lua static RVA hook is inventoried without execution',function()
  local r=report([=[
[ENABLE]
{$lua}
if syntaxcheck then return end
local base=getAddress('sample.exe')
local source=base+0x5F33B4A
local expected={0x48,0x8B,0x4B,0x10,0x48,0x8B,0xD0,0xE8,0xDA,0x33,0x13,0xFB,0x84,0xC0,0x0F,0x84}
local original={0x48,0x8B,0x4B,0x10,0x48,0x8B,0xD0}
local cave=allocateMemory(4096,source,0x40)
local assembly=string.format([[nop]])
local ok,err=autoAssemble(assembly)
{$asm}
[DISABLE]
]=])

  eq(#r.resources,1)

  local resource=r.resources[1]

  eq(resource.command,'lua_rva_hook')

  local hook=resource.hook

  eq(hook.kind,'lua_rva_hook')
  eq(hook.module,'sample.exe')
  eq(hook.rva,'0x5F33B4A')
  eq(hook.expected_bytes,16)
  eq(hook.original_bytes,7)
  eq(hook.allocation,true)
  eq(hook.dynamic_aa,true)

  eq(hook.expected[1],0x48)
  eq(hook.expected[16],0x84)

  eq(hook.original[1],0x48)
  eq(hook.original[7],0xD0)

  local found=false

  for _,w in ipairs(r.diagnostics) do
    if w.rule=='LUA-RVA-HOOK' then
      found=true
    end
  end

  assert(found)
end)

test('bundle installs once and cleans only its own menu; export is fresh',function()
  local installed,destroyed=0,0

  getMainForm=function()
    return {
      Menu={
        Items={
          add=function()
            installed=installed+1
          end
        }
      }
    }
  end

  createMenuItem=function()
    return {
      add=function()
      end,

      destroy=function()
        destroyed=destroyed+1
      end
    }
  end

  getOpenedProcessID=function()
    return 0
  end

  getCEVersion=function()
    return 7.7
  end

  local core=dofile('releases/CESuite_Core.lua')

  eq(installed,1)

  local again=dofile('releases/CESuite_Core.lua')

  eq(again,core)
  eq(installed,1)
  eq(destroyed,0)

  local r=core.analyze('export')

  eq(r.target.attached,false)

  core.export(
    (CESUITE_TEST_OUTPUT or 'ce/tests')..'/generated-report.json'
  )

  local fake=mock({'1010'})

  for k,v in pairs(fake) do
    _G[k]=v
  end

  process='test.exe'

  targetIs64Bit=function()
    return true
  end

  enumModules=function()
    return {
      {
        Name='test.exe',
        Address=0x1000,
        Is64Bit=true,
        PathToFile='synthetic/test.exe'
      }
    }
  end

  getModuleSize=function()
    return 0x100
  end

  vtAutoAssembler=11

  getAddressList=function()
    return {
      Count=1,
      LoadedTableVersion=45,

      getMemoryRecord=function()
        return {
          ID=1,
          Description='Synthetic only',
          Type=11,
          OffsetCount=0,
          Script=
            '[ENABLE]\n'..
            'aobscanmodule(p,test.exe,48 8B ??)\n'..
            'p+17:\n'..
            'jmp x\n'..
            '[DISABLE]'
        }
      end
    }
  end

  local engineCalls=0
  getLuaEngine=function()
    engineCalls=engineCalls+1
    error('Passive core analysis must not open Lua Engine')
  end

  local disassemblyCalls=0
  local function disassemblyTrap()
    disassemblyCalls=disassemblyCalls+1
    error('Bundle must not capture disassembly context')
  end
  readBytes=disassemblyTrap
  disassemble=disassemblyTrap
  createDisassembler=disassemblyTrap
  getInstructionSize=disassemblyTrap
  getVisibleDisassembler=disassemblyTrap
  getDefaultDisassembler=disassemblyTrap

  r=core.analyze('export')

  eq(
    r.aobs[1].uniqueness,
    'unique_current_scan'
  )

  core.export(
    (CESUITE_TEST_OUTPUT or 'ce/tests')..'/generated-observed.json'
  )

  getAddressList=function()
    return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
      return {ID=2,Type=11,Description='Dependency fixture',OffsetCount=0,Script=[[
[ENABLE]
alloc(buffer,16)
registersymbol(buffer)
{$lua}
error('SOURCE MUST NEVER EXECUTE')
local s=MOD_PLAYER
MOD_GODMODE={enabled=true}
local base = getAddress('test.exe')
local source = base + 0x10
local expected = {0x90}
local original = {0x90}
{$asm}
[DISABLE]
unregistersymbol(buffer)
dealloc(buffer)
]]}
    end}
  end
  core.export((CESUITE_TEST_OUTPUT or 'ce/tests')..'/generated-dependencies.json')
  for _,mode in ipairs({'table','selected'}) do
    local captured=core.analyze(mode)
    eq(captured.ct.table_lua_status,'unavailable')
  end
  eq(engineCalls,0)
  eq(disassemblyCalls,0)

  core.shutdown()

  eq(destroyed,1)
end)


test('P0-05 luacode masks commands and fake exits in long comments',function()
  for _,ending in ipairs({'', '\n{$asm}\nalloc(real,16)'}) do
    local r=report('{$luacode someArg}\n{$lua}\nalloc(fake,16)\naobscanmodule(fake,game.exe,90)\nregistersymbol(fake)\n--[=[\n{$asm}\nalloc(commentFake,16)\n]=]'..ending)
    eq(#r.aobs,0);eq(#r.resources,ending=='' and 0 or 1)
    eq(#r.dependencies,ending=='' and 0 or 2)
    eq(#r.scripts,1)
    if ending~='' then eq(r.resources[1].arguments[1],'real') end
  end
end)

test('P0-05 incomplete Lua comments cannot escape opaque luacode',function()
  local r=report('{$luacode}\n--[[\n{$asm}\nalloc(fake,16)')
  eq(#r.resources,0);eq(#r.dependencies,0);eq(#r.aobs,0)
end)

test('P0-05 nested unknown branches and unmatched endif stay lexical',function()
  local r=report('{$ifdef X}\nalloc(fake,16)\n{$ifndef Y}\naobscan(fake,90)\n{$endif}\n{$endif}\n{$endif}\nalloc(real,16)')
  eq(#r.aobs,0);eq(#r.resources,1);eq(r.resources[1].arguments[1],'real')
  local unmatched=false
  for _,w in ipairs(r.diagnostics) do if w.rule=='CONDITIONAL-UNMATCHED' then unmatched=true end end
  assert(unmatched)
  local incomplete=report('{$ifdef X}\nregistersymbol(fake)')
  eq(#incomplete.dependencies,0)
end)

test('P0-05 post-source complex arguments never become classic semantics',function()
  for _,cmd in ipairs({'HOOK','UNHOOK','HOOK5','aobscanfunction','aobscanregion'}) do
    local r=report(cmd..'(symbol,fn("a,b",nested(1,2)),90)\nalloc(real,16)')
    eq(#r.aobs,0);eq(#r.resources,1);eq(#r.dependencies,2)
    local opaque=false
    for _,w in ipairs(r.diagnostics) do if w.rule=='OPAQUE-COMMAND' then opaque=true end end
    assert(opaque)
  end
end)

test('P0-06 duplicate names and paths abstain before checking metadata',function()
  local modules={{name='game.exe',path='C:/one/game.exe',base='0x1000',size=256},
    {name='GAME.EXE',path='D:/two/game.exe',base='0x2000',size=512}}
  local value,reason=A.resolve('game.exe+10',modules)
  eq(value,nil);assert(reason:find('ambiguous'))
  eq(A.resolve('C:\\one\\game.exe',modules),0x1000)
  eq(A.resolve('alias',modules,{alias='game.exe'}),nil)
  local r=report('aobscanmodule(p,game.exe,90)');r.modules=modules
  local api,calls=mock({'1000'});A.validate(api,r,context)
  eq(#calls,0);eq(r.aobs[1].status,'unresolved');assert(r.aobs[1].message:find('ambiguous'))
  modules[2].base=nil
  eq(A.resolve('game.exe',modules),nil)
  modules[2].name='other.exe'
  eq(A.resolve('game.exe',modules),nil) -- path basename is still ambiguous
  modules[2].path=modules[1].path
  eq(A.resolve('C:/one/game.exe',modules),nil)
end)

test('P0-06 duplicate snapshot skips ambiguous size API',function()
  local calls=0
  local r={diagnostics=U.array()}
  Env.capture({getOpenedProcessID=function() return 123 end,
    enumModules=function() return {{Name='game.exe',Address=4096},{Name='GAME.EXE',Address=8192}} end,
    getModuleSize=function() calls=calls+1;return 100 end},r)
  eq(calls,0);eq(r.modules[1].size,U.null);eq(r.modules[2].size,U.null)
  eq(r.diagnostics[1].rule,'MODULE-SNAPSHOT-INCOMPLETE')
end)


test('F-01 incomplete luacode fails closed',function()
  local r=report('{$luacode\nalloc(fake,16)\naobscan(fake,90)\nlabel(fake)\ndefine(fake,real)\nfake:')
  eq(#r.resources,0);eq(#r.dependencies,0);eq(#r.aobs,0)
  eq(#r.scripts[1].labels,0);eq(next(r.scripts[1].defines),nil)
  local incomplete=false
  for _,w in ipairs(r.diagnostics) do if w.rule=='OPAQUE-INCOMPLETE' then incomplete=true end end
  assert(incomplete)
end)
test('F-02 embedded luacode masks whole line and body',function()
  local r=report('alloc(prefix,16) {$luacode}\nalloc(fake,16)\n{$asm}\nalloc(real,16)')
  eq(#r.resources,1);eq(r.resources[1].arguments[1],'real');eq(#r.dependencies,2)
end)
test('F-03 every conditional on a line updates depth',function()
  for _,prefix in ipairs({'{$ifdef X}{$endif}','{$ifndef X}{$endif}',
    '{$ifdef X}{$ifndef Y}{$endif}{$endif}','{$ifdef X}{$endif}{$endif}'}) do
    local r=report(prefix..'\nalloc(real,16)');eq(#r.resources,1)
    eq(r.resources[1].arguments[1],'real')
  end
end)
test('F-04 conditional sections stay unknown until explicit header',function()
  for _,header in ipairs({'[ENABLE]','[DISABLE]'}) do
    local r=report('[ENABLE]\n{$ifdef X}\n'..header..'\n{$endif}\nalloc(real,16)\naobscan(anchor,90)\n[DISABLE]\ndealloc(real)')
    eq(r.resources[1].section,'unknown');eq(r.aobs[1].section,'unknown')
    eq(r.dependencies[1].section,'unknown');eq(r.resources[2].section,'disable')
  end
end)
test('F-05 empty and invalid module queries never scan',function()
  for _,query in ipairs({'','   ','""',false,42,U.null}) do
    eq(U.moduleNorm(query),nil)
    local m,reason=U.moduleMatch(query,{{name='test.exe',path=U.null}})
    eq(m,nil);assert(reason:find('invalid'))
  end
  local r=report('aobscanmodule(x,,90)');r.modules[1].path=U.null
  local api,calls=mock({'1000'});A.validate(api,r,context)
  eq(#calls,0);eq(r.aobs[1].status,'unresolved')
end)
test('F-06 snapshot and resolver share name and path ambiguity',function()
  local cases={
    {{Name='game.exe',PathToFile='C:/one/game.exe',Address=4096},{Name='GAME.EXE',PathToFile='D:/two/game.exe',Address=8192}},
    {{Name='one.exe',PathToFile='C:/same/game.exe',Address=4096},{Name='other.exe',PathToFile='c:\\SAME\\GAME.EXE',Address=8192}},
    {{Name='game.exe',PathToFile='C:/one/game.exe',Address=4096},{Name='other.exe',PathToFile='D:/two/game.exe',Address=8192}},
    {{Name='one.exe',PathToFile=U.null,Address=4096},{Name='two.exe',Address=8192}},
    {{Name='C:/one/game.exe',PathToFile='C:/one/game.exe',Address=4096},{Name='D:/two/game.exe',PathToFile='D:/two/game.exe',Address=8192}}
  }
  for _,modules in ipairs(cases) do
    local lookups={};local r={diagnostics=U.array()}
    Env.capture({getOpenedProcessID=function() return 7 end,enumModules=function() return modules end,
      getModuleSize=function(name) lookups[name]=true;return 256 end},r)
    for i,m in ipairs(modules) do
      local found=U.moduleMatch(m.Name,r.modules)
      local _,pathReason=U.moduleMatch(m.PathToFile,r.modules)
      if pathReason and pathReason:find('ambiguous') then found=nil end
      eq(r.modules[i].size,found and 256 or U.null)
      eq(lookups[m.Name] or false,found and true or false)
    end
  end
  local modules={{name='game.exe',path='C:/one/game.exe',base='0x1000',size=256},
    {name='game.exe',path='D:/two/game.exe',base='0x2000',size=512}}
  eq(A.resolve('C:/one/game.exe',modules),4096)
  eq(A.resolve('game.exe',modules),nil)
  modules[2].path='c:\\ONE\\GAME.EXE'
  eq(A.resolve('C:/one/game.exe',modules),nil)
  local r=report('aobscanmodule(x,C:/one/game.exe,90)');r.modules=modules
  local api,calls=mock({'1000'});A.validate(api,r,context)
  eq(#calls,0);eq(r.aobs[1].status,'unresolved')
end)

test('F-04 Lua RVA and globals retain unknown section provenance',function()
  local r=report('[ENABLE]\n{$ifdef X}\n[DISABLE]\n{$endif}\n{$lua}\nlocal base = getAddress("game.exe")\nlocal source = base + 0x10\nSHARED_GLOBAL=OTHER_GLOBAL\n{$asm}')
  eq(#r.resources,1);eq(r.resources[1].command,'lua_rva_hook')
  eq(r.resources[1].section,'unknown')
  for _,d in ipairs(r.dependencies) do eq(d.section,'unknown') end
end)

print(
  string.format(
    '%d Lua tests passed (synthetic CE API mocks; no live CE validation)',
    tests
  )
)
