package.path='ce/modules/?.lua;'..package.path
-- Coverage model tests: static discovery and runtime validation are separate.
local D=require('dynamic')
local U=require('util')
local C=require('coverage')

local tests=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(a,b,label)
  assert(a==b,(label or 'value')..': expected '..tostring(b)..' got '..tostring(a))
end
local function read(path)
  local f=assert(io.open(path,'rb'));local t=f:read('*a');f:close();return t
end
local SCRIPT95=read('ce/tests/fixtures/dynamic/script95.lua')
local UE=read('ce/tests/fixtures/dynamic/ue.lua')
local function analyze(text,opts)
  return D.analyze({{script_id='probe',text=text}},opts or {})
end
local function analyze95(opts)
  opts=opts or {}
  return D.analyze({{script_id='script-95',text=SCRIPT95}},{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}},
    limits=opts.limits
  })
end
local function aob(count,uniqueness,status)
  return {status=status or 'observed',match_count=count,uniqueness=uniqueness}
end

test('empty source is a known empty collection',function()
  local cov=C.for_static(nil,{}, {})
  eq(cov.collection.units_discovered,0)
  eq(cov.collection.complete,true)
  eq(cov.collection.percentage,U.null)
  eq(cov.discovery.candidates,0)
  eq(cov.validation.status,'not_applicable')
  eq(cov.validation.percentage,U.null)
end)

test('no-AOB source has no discovery candidates',function()
  local r=analyze('local x = 1')
  local cov=C.for_static(r,{{text='x'}}, {})
  eq(cov.collection.complete,true)
  eq(cov.discovery.candidates,0)
  eq(cov.discovery.status,'unknown')
  eq(cov.validation.status,'not_applicable')
end)

test('script-95 static coverage separates discovery from validation',function()
  local r=analyze95()
  local cov=C.for_static(r,{{text='x'}}, {})
  eq(cov.collection.complete,true)
  eq(cov.discovery.patterns_literal,28)
  eq(cov.discovery.patterns_derived,3)
  eq(cov.discovery.patterns_conditional,1)
  eq(cov.discovery.patterns_symbol_only,21)
  eq(cov.discovery.candidates,31)
  eq(cov.validation.candidates,31)
  eq(cov.validation.runtime_attempted,0)
  eq(cov.validation.runtime_validated,0)
  eq(cov.validation.status,'unavailable')
  eq(cov.validation.complete,false)
  eq(cov.validation.percentage,U.null)
end)

test('script-95 with known universe still has unresolved discovery',function()
  local r=analyze95()
  local cov=C.for_static(r,{{text='x'}},{universe_known=true})
  eq(cov.discovery.universe_known,true)
  eq(cov.discovery.unresolved,1)
  eq(cov.discovery.complete,false)
  eq(cov.discovery.status,'partial')
  eq(cov.validation.universe_known,false)
  eq(cov.validation.complete,false)
  eq(cov.validation.percentage,U.null)
end)

test('missing helper leaves derived candidates unresolved',function()
  local r=D.analyze({{script_id='s',text=SCRIPT95}},{})
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.discovery.unresolved>=1,true)
  eq(cov.discovery.status,'partial')
  eq(cov.discovery.percentage,U.null)
  eq(cov.validation.runtime_validated,0)
end)

test('unknown wrapper produces no candidates',function()
  local r=analyze("local t = { ['K'] = { {'s','90'} } }\nUnknown.wrap(t)")
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.discovery.candidates,0)
  eq(cov.discovery.status,'unknown')
  eq(cov.validation.status,'not_applicable')
end)

test('token limit makes collection partial and never complete',function()
  local r=analyze("local t = { {'s','90'} }\nRegister.onEnable(t)",{limits={max_tokens=5}})
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,false)
  eq(cov.collection.status,'limit_reached')
  eq(cov.discovery.status,'limit_reached')
  eq(cov.discovery.percentage,U.null)
end)

test('TABLE_LIMIT propagates into coverage',function()
  local r=analyze("local t = { a=1, b=2, c=3 }\nRegister.onEnable(t)",{limits={max_entries=2}})
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,false)
  eq(cov.collection.status,'limit_reached')
  eq(#cov.collection.limitations>0,true)
end)

test('EDGE_LIMIT propagates into coverage',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t); Register.onEnable(t)",{limits={max_edges=1}})
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,false)
  eq(cov.collection.status,'limit_reached')
end)

test('CANDIDATE_LIMIT propagates into coverage',function()
  local r=analyze("local t = { ['K'] = { {'a','90'}, {'b','91'} } }\nRegister.onEnable(t)",{limits={max_candidates=1}})
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,false)
  eq(cov.collection.status,'limit_reached')
end)

test('detached runtime keeps collection complete and validation unavailable',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local report={scripts={{text='x'}},aobs={},target={attached=false},operation={source_complete=false}}
  local cov=C.for_runtime(report,r,{})
  eq(cov.collection.complete,true)
  eq(cov.validation.status,'unavailable')
  eq(cov.validation.runtime_attempted,0)
  eq(cov.validation.runtime_validated,0)
end)

test('attached target without candidates is not applicable',function()
  local report={scripts={},aobs={},target={attached=true}}
  local cov=C.for_runtime(report,analyze('local x=1'),{})
  eq(cov.validation.status,'not_applicable')
  eq(cov.validation.percentage,U.null)
end)

test('attached target with candidates but no scans is unavailable',function()
  local r=analyze95()
  local report={scripts={{text='x'}},aobs={},target={attached=true}}
  local cov=C.for_runtime(report,r,{})
  eq(cov.validation.candidates,31)
  eq(cov.validation.runtime_attempted,0)
  eq(cov.validation.status,'unavailable')
end)

test('runtime unique match increments only runtime validation',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local report={scripts={{text='x'}},aobs={aob(1,'unique_current_scan')},target={attached=true}}
  local cov=C.for_runtime(report,r,{})
  eq(cov.validation.runtime_attempted,1)
  eq(cov.validation.runtime_validated,1)
  eq(cov.validation.runtime_unique,1)
  eq(cov.validation.percentage,U.null)
  eq(cov.validation.complete,false)
end)

test('runtime ambiguous match is classified without validation',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local cov=C.for_runtime({scripts={{text='x'}},aobs={aob(3,'multiple_matches')}},r,{})
  eq(cov.validation.runtime_ambiguous,1)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime no-match is classified without validation',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local cov=C.for_runtime({scripts={{text='x'}},aobs={aob(0,'no_match')}},r,{})
  eq(cov.validation.runtime_no_match,1)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime scan error is attempted but not validated',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local cov=C.for_runtime({scripts={{text='x'}},aobs={aob(nil,nil,'error')}},r,{})
  eq(cov.validation.runtime_attempted,1)
  eq(cov.validation.runtime_error,1)
  eq(cov.validation.runtime_validated,0)
  eq(cov.validation.status,'partial')
end)

test('known universe with complete runtime validation reaches complete',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)")
  local cov=C.for_runtime({scripts={{text='x'}},aobs={aob(1,'unique_current_scan')}},r,{universe_known=true})
  eq(cov.validation.complete,true)
  eq(cov.validation.status,'complete')
  eq(cov.validation.percentage,100)
end)

test('source_complete remains collection-only, not validation',function()
  local report={scripts={{text='x'}},aobs={},target={attached=false},operation={source_complete=false}}
  local cov=C.for_runtime(report,analyze('local x=1'),{})
  eq(cov.collection.complete,true)
  eq(cov.validation.complete,false)
  eq(report.operation.source_complete,false)
end)

test('zero denominator never yields validation 100 percent',function()
  local cov=C.for_static(nil,{}, {})
  eq(cov.validation.candidates,0)
  eq(cov.validation.percentage,U.null)
  eq(cov.validation.status,'not_applicable')
end)

test('coverage is deterministic',function()
  local r=analyze95()
  local a=C.for_static(r,{{text='x'}},{universe_known=true})
  local b=C.for_static(r,{{text='x'}},{universe_known=true})
  eq(a.discovery.candidates,b.discovery.candidates)
  eq(a.validation.status,b.validation.status)
  eq(a.collection.complete,b.collection.complete)
  eq(a.discovery.percentage,b.discovery.percentage)
end)

print(string.format('%d coverage tests passed (text-only)',tests))
