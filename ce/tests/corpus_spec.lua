package.path='ce/modules/?.lua;'..package.path
-- Regression corpus harness (030D). Fixtures are text fragments; replay files
-- are test data authored for CESuite, never third-party table source.
local D=require('dynamic')
local C=require('coverage')
local P=require('parser')

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
local function analyze(text,opts)
  return D.analyze({{script_id='corpus',text=text}},opts or {})
end
local function analyze95()
  return D.analyze({{script_id='script-95',text=read('ce/tests/fixtures/dynamic/script95.lua')}},{
    helpers={{name='UE',alias='Obj',text=read('ce/tests/fixtures/dynamic/ue.lua'),file='ue.lua'}},
    loader=read('ce/tests/fixtures/dynamic/loader.lua')})
end
local function edges_with(dyn,relation,provenance)
  local n=0
  for _,e in ipairs(dyn.edges) do
    if e.relation==relation and (not provenance or e.provenance==provenance) then n=n+1 end
  end
  return n
end
local function callback_edges(dyn)
  local n=0
  for _,e in ipairs(dyn.edges) do if e.provenance=='callback' then n=n+1 end end
  return n
end
local function has_edge(dyn,relation,from,to)
  for _,e in ipairs(dyn.edges) do
    if e.relation==relation and (not from or e.from==from) and (not to or e.to==to) then return true end
  end
  return false
end
local function dep_scope(dyn,name)
  local counts={['local']=0,['global']=0}
  for _,d in ipairs(dyn.dependencies) do
    if d.name==name then counts[d.scope]=counts[d.scope]+1 end
  end
  return counts
end
local function replay(path)
  return assert(loadfile(path))()
end
local function replay_coverage(name)
  local case=replay('ce/tests/fixtures/corpus/runtime-replay/'..name..'.lua')
  local dyn=analyze("local t = { ['K'] = { {'a','90 90'} } }\nRegister.onEnable(t)")
  local report={scripts={{text='x'}},aobs=case.aobs,target={attached=true}}
  return C.for_runtime(report,dyn,{}),case
end

test('ffrs-script95-static',function()
  local r=analyze95()
  eq(r.counts.entries,47);eq(r.counts.specs,52)
  eq(r.counts.literal,28);eq(r.counts.literal_unique,27)
  eq(r.counts.derived,3);eq(r.counts.conditional,1)
  eq(r.counts.symbol_only,21);eq(r.counts.symbol_only_pure,20)
  eq(r.counts.unique_symbols,30);eq(r.counts.candidates,31);eq(r.counts.runtime_validated,0)
  eq(#r.unresolved,1);eq(r.unresolved[1].name,'LaunchUEInfoScanner')
  eq(callback_edges(r),0)
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,true)
  eq(cov.discovery.entities_discovered,52)
  eq(cov.discovery.candidates,31)
  eq(cov.validation.status,'unavailable')
  eq(cov.validation.runtime_validated,0)
end)

test('dynamic-local-table',function()
  local r=analyze(read('ce/tests/fixtures/corpus/dynamic/local-table.lua'))
  eq(#r.patterns,1)
  eq(r.counts.specs,1)
  assert(has_edge(r,'passes_to','t','Register.onEnable'),'passes_to missing')
end)

test('dynamic-nested-table',function()
  local r=analyze(read('ce/tests/fixtures/corpus/dynamic/nested-table.lua'))
  eq(r.counts.candidates,2);eq(r.counts.specs,2)
end)

test('callbacks-real',function()
  local r=analyze(read('ce/tests/fixtures/corpus/callbacks/real-callback.lua'))
  assert(callback_edges(r)>0,'callback provenance missing')
  eq(r.counts.candidates,0)
end)

test('callbacks-data-table',function()
  local r=analyze(read('ce/tests/fixtures/corpus/callbacks/data-table.lua'))
  eq(callback_edges(r),0)
  eq(r.counts.candidates,1)
end)

test('negative-unknown-wrapper',function()
  local r=analyze(read('ce/tests/fixtures/corpus/negative/unknown-wrapper.lua'))
  eq(r.counts.candidates,0)
  eq(C.for_static(r,{},{}).discovery.universe_known,false)
end)

test('negative-missing-helper',function()
  local r=analyze(read('ce/tests/fixtures/corpus/negative/missing-helper.lua'))
  eq(r.counts.derived,1)
  eq(r.patterns[1].status,'unresolved')
  eq(r.patterns[1].runtime_validated,false)
end)

test('loaders-include-provider',function()
  local r=D.analyze({}, {loader=read('ce/tests/fixtures/corpus/loaders/include-provider.lua')})
  local providers={}
  for _,p in ipairs(r.providers) do providers[p]=true end
  assert(providers.Register and providers.UE,'include providers missing')
  assert(has_edge(r,'includes','loader','Register.lua'),'include edge missing')
end)

test('loaders-dynamic-binding',function()
  local r=D.analyze({}, {loader=read('ce/tests/fixtures/corpus/loaders/dynamic-binding.lua')})
  eq(#r.providers,0)
end)

test('constructed-aa-contract',function()
  local r=analyze(read('ce/tests/fixtures/corpus/constructed-aa/contract.lua'))
  assert(has_edge(r,'constructs','register.multicustomscan','aobScanRegion'),'constructs missing')
  eq(r.counts.runtime_validated,0)
end)

test('constructed-aa-dynamic-format',function()
  local r=analyze(read('ce/tests/fixtures/corpus/constructed-aa/dynamic-format.lua'))
  eq(r.counts.candidates,0)
end)

test('provenance-multi-edge',function()
  local r=analyze(read('ce/tests/fixtures/corpus/provenance/multi-edge.lua'))
  eq(r.counts.candidates,1)
  assert(has_edge(r,'constructs','register.multicustomscan','aobScanRegion'))
  assert(edges_with(r,'provides')>0)
end)

test('duplicates-func-give-item',function()
  local r=analyze(read('ce/tests/fixtures/corpus/duplicates/func-give-item.lua'))
  eq(r.counts.candidates,2)
  eq(r.counts.literal_unique,1)
  local ids={}
  for _,p in ipairs(r.patterns) do ids[p.id]=true end
  eq(ids[r.patterns[1].id] and ids[r.patterns[2].id],true)
end)

test('scope-local-global',function()
  local r=analyze(read('ce/tests/fixtures/corpus/scope/local-global.lua'))
  local x=dep_scope(r,'x');eq(x['local'],1);eq(x['global'],0)
  local y=dep_scope(r,'y');eq(y['global'],1)
end)

test('scope-shadowing',function()
  local r=analyze(read('ce/tests/fixtures/corpus/scope/shadowing.lua'))
  local x=dep_scope(r,'x');eq(x['local'],2);eq(x['global'],0)
end)

test('scope-shared-locals',function()
  local report={dependencies=require('util').array(),scripts=require('util').array(),diagnostics=require('util').array()}
  local script={id='shared',text=read('ce/tests/fixtures/corpus/scope/shared-locals.lua'),
    record_key=require('util').null,origin='MemoryRecord.Script',language='AA'}
  P.inspect(script,report)
  for _,dep in ipairs(report.dependencies) do
    eq(dep.name=='hidden',false,'sharedLocals must suppress later global')
  end
end)

test('limits-table',function()
  local r=analyze(read('ce/tests/fixtures/corpus/limits/table-limit.lua'),{limits={max_entries=2}})
  eq(r.status,'limit_reached')
  local cov=C.for_static(r,{},{});eq(cov.collection.status,'limit_reached')
end)

test('limits-candidate',function()
  local r=analyze(read('ce/tests/fixtures/corpus/limits/candidate-limit.lua'),{limits={max_candidates=1}})
  eq(r.status,'limit_reached')
end)

test('limits-edge',function()
  local r=analyze(read('ce/tests/fixtures/corpus/limits/edge-limit.lua'),{limits={max_edges=1}})
  eq(r.status,'limit_reached')
end)

test('limits-token',function()
  local r=analyze(read('ce/tests/fixtures/corpus/limits/token-limit.lua'),{limits={max_tokens=5}})
  eq(r.status,'limit_reached')
end)

test('limits-multiple',function()
  local r=analyze(read('ce/tests/fixtures/corpus/limits/multiple.lua'),{limits={max_entries=2,max_candidates=1,max_edges=1}})
  eq(r.status,'limit_reached')
end)

test('coverage-empty',function()
  local cov=C.for_static(nil,{}, {})
  eq(cov.collection.complete,true)
  eq(cov.collection.percentage,require('util').null)
  eq(cov.validation.status,'not_applicable')
end)

test('coverage-zero-candidates',function()
  local r=analyze(read('ce/tests/fixtures/corpus/coverage/zero-candidates.lua'))
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.validation.candidates,0)
  eq(cov.validation.percentage,require('util').null)
end)

test('coverage-script95',function()
  local r=analyze95()
  local cov=C.for_static(r,{{text='x'}},{})
  eq(cov.collection.complete,true)
  eq(cov.discovery.candidates,31)
  eq(cov.validation.status,'unavailable')
  eq(cov.validation.complete,false)
end)

test('coverage-detached',function()
  local r=analyze95()
  local cov=C.for_runtime({scripts={{text='x'}},aobs={},target={attached=false}},r,{})
  eq(cov.collection.complete,true)
  eq(cov.validation.status,'unavailable')
end)

test('runtime-unique',function()
  local cov,case=replay_coverage('unique')
  eq(cov.validation.runtime_validated,case.expect.validated)
  eq(cov.validation.runtime_unique,case.expect.unique)
end)

test('runtime-ambiguous',function()
  local cov,case=replay_coverage('ambiguous')
  eq(cov.validation.runtime_validated,case.expect.validated)
  eq(cov.validation.runtime_ambiguous,case.expect.ambiguous)
end)

test('runtime-no-match',function()
  local cov,case=replay_coverage('no-match')
  eq(cov.validation.runtime_validated,0)
  eq(cov.validation.runtime_no_match,case.expect.no_match)
end)

test('runtime-error',function()
  local cov,case=replay_coverage('error')
  eq(cov.validation.runtime_attempted,case.expect.attempted)
  eq(cov.validation.runtime_error,case.expect.error)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime-invalidated',function()
  local cov,case=replay_coverage('invalidated')
  eq(cov.validation.runtime_unavailable,case.expect.unavailable)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime-unavailable',function()
  local cov,case=replay_coverage('unavailable')
  eq(cov.validation.runtime_attempted,case.expect.attempted)
  eq(cov.validation.runtime_unavailable,case.expect.unavailable)
end)

test('runtime-unsupported',function()
  local cov,case=replay_coverage('unsupported')
  eq(cov.validation.unsupported,case.expect.unsupported)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime-unresolved',function()
  local cov,case=replay_coverage('unresolved')
  eq(cov.validation.unresolved,case.expect.unresolved)
  eq(cov.validation.runtime_validated,0)
end)

test('runtime unique with known universe is complete',function()
  local case=replay('ce/tests/fixtures/corpus/runtime-replay/unique.lua')
  local dyn=analyze("local t = { ['K'] = { {'a','90 90'} } }\nRegister.onEnable(t)")
  local cov=C.for_runtime({scripts={{text='x'}},aobs=case.aobs,target={attached=true}},dyn,{universe_known=true})
  eq(cov.validation.complete,true)
  eq(cov.validation.percentage,100)
end)

print(string.format('%d corpus tests passed (text/replay only)',tests))
