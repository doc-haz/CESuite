package.path='ce/modules/?.lua;'..package.path
-- Reporting and UX integration tests (030E).
local Simple=require('simplereport')
local Dynamic=require('dynamic')
local Coverage=require('coverage')
local U=require('util')

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
  local f=assert(io.open(path,'rb'))
  local t=f:read('*a')
  f:close()
  return t
end

local SCRIPT95=read('ce/tests/fixtures/dynamic/script95.lua')
local UE=read('ce/tests/fixtures/dynamic/ue.lua')
local LOADER=read('ce/tests/fixtures/dynamic/loader.lua')

local function baseAssessment()
  return {
    schema_version='0.1',
    generated_at='2026-10-25T12:00:00Z',
    completed_at='2026-10-25T12:00:01Z',
    mode='table',
    scope={
      attached=false,
      pid=U.null,
      process_name=U.null,
      module_count=0,
      script_count=1,
      aob_count=0,
      dependency_occurrence_count=0,
      static_candidate_count=31
    },
    counts={total=0,problems=0,healthy=0,advisory=0,not_assessed=0},
    headline='Static source review.',
    statements=U.array({}),
    diagnostics=U.array({}),
    repair_path=U.array({}),
    limitations=U.array({})
  }
end

test('Coverage.summaryText renders clean compact block',function()
  local dyn=Dynamic.analyze({{script_id='script-95',text=SCRIPT95}},{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}},
    loader=LOADER
  })
  local cov=Coverage.for_static(dyn,{{text=SCRIPT95}},{})
  local text=Coverage.summaryText(cov)
  assert(text:find('Coverage Summary',1,true),'missing header')
  assert(text:find('Collection',1,true),'missing collection')
  assert(text:find('Status: complete',1,true),'missing collection complete')
  assert(text:find('Discovery',1,true),'missing discovery')
  assert(text:find('Status: partial',1,true),'missing discovery partial')
  assert(text:find('Entities: 52',1,true),'missing entities count')
  assert(text:find('Candidates: 31',1,true),'missing candidates count')
  assert(text:find('Linked: 31',1,true),'missing linked count')
  assert(text:find('Validation',1,true),'missing validation')
  assert(text:find('Status: unavailable',1,true),'missing validation unavailable')
  assert(text:find('Attempted: 0 / 31',1,true),'missing attempted count')
  assert(text:find('Validated: 0',1,true),'missing validated count')
  assert(not text:find('0%%',1,true),'must not display 0% for unavailable')
  assert(not text:find('100%%',1,true),'must not display 100% for incomplete')
end)

test('script-95 UX acceptance in Simple Report',function()
  local dyn=Dynamic.analyze({{script_id='script-95',text=SCRIPT95}},{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}},
    loader=LOADER
  })
  local cov=Coverage.for_static(dyn,{{text=SCRIPT95}},{})
  local assessment=baseAssessment()
  local report={
    scripts={{text=SCRIPT95}},
    dynamic_analysis=dyn,
    coverage=cov,
    target={attached=false}
  }
  local text=Simple.render(assessment,report)

  assert(text:find('## Coverage Summary',1,true),'missing Coverage Summary section')
  assert(text:find('Collection',1,true),'missing collection')
  assert(text:find('Discovery',1,true),'missing discovery')
  assert(text:find('Validation',1,true),'missing validation')
  assert(text:find('Candidates: 31 from 52 entities (31 linked)',1,true),'missing candidates link ratio')
  assert(text:find('Attempted: 0 of 31 candidate(s)',1,true),'missing attempted line')
  assert(text:find('Validated: 0',1,true),'missing validated line')
  assert(text:find('Static source analysis completed; runtime validation was unavailable because no live target was attached.',1,true),
    'missing detached explanation')

  assert(text:find('## Dynamic Analysis & Provenance',1,true),'missing Dynamic Analysis section')
  assert(text:find('### Discovered Candidates',1,true),'missing candidates section')
  assert(text:find('Showing top 10 of 31 candidate(s)',1,true),'missing top 10 limit note')
  assert(text:find('### Unresolved Dependencies',1,true),'missing unresolved section')
  assert(text:find('LaunchUEInfoScanner',1,true),'missing LaunchUEInfoScanner')
  assert(text:find('### Provenance Relationships',1,true),'missing provenance section')
  assert(text:find('### Providers & Consumers',1,true),'missing providers section')

  -- Terminology safety
  assert(not text:find('working signature',1,true),'forbidden terminology: working signature')
  assert(not text:find('31 working',1,true),'forbidden terminology: 31 working')
  assert(not text:find('100% validated',1,true),'forbidden terminology: 100% validated')
  assert(not text:find('auto-repaired',1,true),'forbidden terminology: auto-repaired')
end)

test('detached UX explains static completion and validation unavailability',function()
  local dyn=Dynamic.analyze({{script_id='probe',text='local t = {}\nRegister.onEnable(t)'}})
  local cov=Coverage.for_runtime({scripts={{text='x'}},aobs={},target={attached=false}},dyn,{})
  local report={target={attached=false},coverage=cov,dynamic_analysis=dyn}
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Static source analysis completed; runtime validation was unavailable because no live target was attached.',1,true),
    'detached explanation missing')
end)

test('zero candidates UX presents not applicable without 0 percent',function()
  local dyn=Dynamic.analyze({{script_id='probe',text='local x = 123'}})
  local cov=Coverage.for_static(dyn,{{text='local x = 123'}},{})
  local report={target={attached=true},coverage=cov,dynamic_analysis=dyn}
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Status: not applicable',1,true),'must be not applicable')
  assert(not text:find('0.0% validated',1,true),'must not display 0.0% validated')
  assert(text:find('No signature candidates discovered; runtime validation is not applicable.',1,true),
    'zero candidate note missing')
end)

test('limit reached UX displays warning and specific limitations',function()
  local dyn=Dynamic.analyze({{script_id='probe',text='local t = {}\nRegister.onEnable(t)'}},{
    limits={max_entries=1}
  })
  dyn.status='limit_reached'
  dyn.limits.table_limit_hit=true
  local cov=Coverage.for_static(dyn,{{text='probe'}},{})
  local report={target={attached=false},coverage=cov,dynamic_analysis=dyn}
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Analysis limit reached',1,true),'limit warning missing')
  assert(text:find('Table entries exceeded configured maximum',1,true),'table limit explanation missing')
end)

test('unknown wrapper displays unknown universe and consumer',function()
  local dyn=Dynamic.analyze({{script_id='probe',text="local config = { ['K'] = { {'a','90 90'} } }\nUnknownWrapper(config)"}})
  local cov=Coverage.for_static(dyn,{{text='x'}},{})
  local report={target={attached=false},coverage=cov,dynamic_analysis=dyn}
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Discovery universe is not fully known',1,true),'unknown universe note missing')
end)

test('missing helper candidate details display derivation status',function()
  local dyn=Dynamic.analyze({{script_id='probe',text="local t = { ['K'] = { {'s', UE.Sig.SomePattern} } }\nRegister.onEnable(t)"}})
  local cov=Coverage.for_static(dyn,{{text='x'}},{})
  local report={target={attached=false},coverage=cov,dynamic_analysis=dyn}
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Derived from helper',1,true),'helper derivation missing')
  assert(text:find('Derivation status: unresolved',1,true),'unresolved derivation status missing')
end)

test('runtime replay candidate validation shows unique and ambiguous states',function()
  local dyn=Dynamic.analyze({{script_id='probe',text="local t = { ['K'] = { {'sym1','90 90'}, {'sym2','90 90'} } }\nRegister.onEnable(t)"}})
  local aobs={
    {symbol='sym1',uniqueness='unique',status='observed',match_count=1},
    {symbol='sym2',uniqueness='ambiguous',status='observed',match_count=2}
  }
  local report={
    target={attached=true},
    aobs=aobs,
    dynamic_analysis=dyn,
    coverage=Coverage.for_runtime({scripts={{text='x'}},aobs=aobs,target={attached=true}},dyn,{})
  }
  local text=Simple.render(baseAssessment(),report)
  assert(text:find('Runtime validation: validated (unique)',1,true),'unique validation label missing')
  assert(text:find('Runtime validation: ambiguous',1,true),'ambiguous validation label missing')
end)

test('simple report rendering with dynamic coverage is deterministic',function()
  local dyn=Dynamic.analyze({{script_id='script-95',text=SCRIPT95}},{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}},
    loader=LOADER
  })
  local cov=Coverage.for_static(dyn,{{text=SCRIPT95}},{})
  local report={scripts={{text=SCRIPT95}},dynamic_analysis=dyn,coverage=cov,target={attached=false}}
  local a=baseAssessment()
  local t1=Simple.render(a,report)
  local t2=Simple.render(a,report)
  eq(t1,t2,'rendering must be byte-identical across runs')
end)

print(string.format('%d reporting tests passed (presentation only)',tests))
