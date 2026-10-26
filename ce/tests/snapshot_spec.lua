package.path='ce/modules/?.lua;'..package.path
local S=require('snapshot')
local D=require('snapshotdiff')
local U=require('util')
local E=require('exporter')

local tests=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(a,b,label) assert(a==b,(label or 'value')..': expected '..tostring(b)..' got '..tostring(a)) end
local function contains(s,needle) assert(s:find(needle,1,true),'missing '..needle) end

local function base(opts)
  opts=opts or {}
  local scripts=opts.scripts or {{id='script-1',language='Lua',text='local t = {}\n'}}
  local patterns=opts.patterns or {{
    id='dyn-1',symbol='read_inventory',kind='literal_pattern',pattern='48 89 5C 24',
    source_script='script-1',source_line=10,consumer='Register.onEnable',status='candidate',
    runtime_validated=false,provenance={{kind='lua_literal'},{kind='wrapper'}},
    derivation={source_file='UE.lua',path='UE.Sig.X'}
  }}
  local counts=opts.counts or {entries=1,specs=1,literal=1,literal_unique=1,derived=0,
    conditional=0,symbol_only=0,symbol_only_pure=0,unique_symbols=1,candidates=1,runtime_validated=0}
  local cov=opts.coverage or {
    collection={status='complete',complete=true,units_discovered=2,units_processed=2,
      universe_known=true,denominator='captured_units',percentage=100,limitations={}},
    discovery={status='complete',complete=true,entities_discovered=1,patterns_discovered=1,
      patterns_literal=1,patterns_derived=0,patterns_conditional=0,patterns_symbol_only=0,
      candidates=1,linked=1,unresolved=0,unsupported=0,universe_known=true,
      denominator='discovered_entities',percentage=100,limitations={}},
    validation={status='unavailable',complete=false,candidates=1,runtime_attempted=0,
      runtime_validated=0,runtime_unique=0,runtime_ambiguous=0,runtime_no_match=0,
      runtime_error=0,runtime_unavailable=0,unresolved=0,unsupported=0,
      universe_known=false,denominator='validation_candidates',percentage=U.null,
      limitations={'No runtime scan was attempted.'}}
  }
  return {
    target={attached=true,name='Game.exe',architecture='x64',pid=1234},
    modules={{name='Game.exe',size=1000,base=0x140000000,timestamp='2026-01-01'}},
    records={{id=1}},scripts=scripts,aobs=opts.aobs or {},
    coverage=cov,dynamic_analysis={counts=counts,patterns=patterns,
      edges={{relation='defines',provenance='lua_local'},{relation='constructs',provenance='wrapper'}},
      unresolved={{code='CONDITIONAL_DEPENDENCY',name='LaunchUEInfoScanner',line=9,source_script='script-1'}}},
    dependencies={{name='read_inventory',relation='reads',scope='local'},
      {name='read_inventory',relation='reads',scope='local'}},
    limitations={'Static analysis only.'},
    operation={status='complete',source_complete=true,metrics={
      parse_ms=10,scan_ms=0,duration_ms=10,source_bytes=14,items_total=0,items_processed=0}}
  }
end
local function capture(opts)
  opts=opts or {}
  return S.capture(opts.report or base(opts),{created_at=opts.created_at or '2026-10-26T12:00:00Z',
    suite_version='0.3.1',include_pid=opts.include_pid})
end
local function ok(s) local valid,errs=S.validate(s);assert(valid,table.concat(errs,'; '));return s end

test('capture has the required v1 surface and validates',function()
  local s=ok(capture())
  eq(s.snapshot_version,1);eq(s.schema_id,'cesuite.evidence_snapshot')
  eq(type(s.snapshot_id),'string');eq(s.snapshot_id:sub(1,5),'snap-')
  eq(#s.candidates,1);eq(s.candidates[1].symbol,'read_inventory')
  eq(s.candidates[1].pattern,'48895c24')
  eq(s.candidates[1].provider,'UE.lua');eq(s.candidates[1].helper,'UE.Sig.X')
  eq(#s.dependencies,1);eq(s.dependencies[1].count,2)
  eq(s.source.kind,'runtime_report');eq(s.source.fingerprint_scope,'captured_scripts')
  eq(s.target.build_fingerprint_known,true)
  eq(s.operation.total_ms,10)
end)

test('snapshot serializes deterministically and contains no local path/PID',function()
  local s=ok(capture())
  local a=E.encode(s);local b=E.encode(s)
  eq(a,b)
  eq(a:find('C:\\',1,true),nil)
  eq(a:find('"pid_context":1234',1,true),nil)
  contains(a,'"snapshot_version":1')
end)

test('same evidence with different time/timings gives the same id',function()
  local r1=base();local r2=base()
  r2.operation.metrics.parse_ms=999;r2.target.pid=9999
  local a=capture({report=r1,created_at='2026-10-26T12:00:00Z'})
  local b=capture({report=r2,created_at='2026-10-27T12:00:00Z'})
  eq(a.snapshot_id,b.snapshot_id)
end)

test('PID is context only and never part of the snapshot id',function()
  local a=capture({include_pid=true})
  local r=base();r.target.pid=9999
  local b=capture({report=r,include_pid=true})
  assert(a.target.pid_context~=U.null);assert(b.target.pid_context~=U.null)
  eq(a.snapshot_id,b.snapshot_id)
end)

test('source change changes the source fingerprint',function()
  local a=capture()
  local r=base();r.scripts[1].text='local t = {1}\n'
  local b=capture({report=r})
  assert(a.source.fingerprint~=b.source.fingerprint)
  assert(a.snapshot_id~=b.snapshot_id)
end)

test('target module size changes the target fingerprint, not PID',function()
  local a=capture()
  local r=base();r.modules[1].size=2000
  local b=capture({report=r})
  assert(a.target.fingerprint~=b.target.fingerprint)
  local c=capture({report=base()})
  eq(a.target.fingerprint,c.target.fingerprint)
end)

test('duplicate candidates get deterministic occurrences',function()
  local p1={id='1',symbol='dup',kind='literal_pattern',pattern='11 22',source_script='s',source_line=10,consumer='C',status='candidate'}
  local p2={id='2',symbol='dup',kind='literal_pattern',pattern='11 22',source_script='s',source_line=20,consumer='C',status='candidate'}
  local s=ok(capture({patterns={p1,p2}}))
  eq(#s.candidates,2)
  assert(s.candidates[1].identity.key~=s.candidates[2].identity.key)
  eq(s.candidates[1].identity.occurrence,1);eq(s.candidates[2].identity.occurrence,2)
end)

test('pattern change keeps identity and is reported as changed',function()
  local a=capture()
  local r=base();r.dynamic_analysis.patterns[1].pattern='48 89 5C 25'
  local b=capture({report=r})
  eq(a.candidates[1].identity.key,b.candidates[1].identity.key)
  local d=S.compare(a,b)
  eq(#d.candidates.changed,1)
  eq(d.candidates.changed[1].fields[1].field,'pattern')
end)

test('provider change is reported without a verdict',function()
  local a=capture()
  local r=base();r.dynamic_analysis.patterns[1].derivation.source_file='Other.lua'
  local b=capture({report=r})
  local d=S.compare(a,b)
  eq(#d.candidates.changed,1)
  local found=false
  for _,f in ipairs(d.candidates.changed[1].fields) do if f.field=='provider' then found=true end end
  eq(found,true)
end)

test('consumer change appears as added/removed identity',function()
  local a=capture()
  local r=base();r.dynamic_analysis.patterns[1].consumer='OtherConsumer'
  local b=capture({report=r})
  local d=S.compare(a,b)
  eq(#d.candidates.added,1);eq(#d.candidates.removed,1)
end)

test('validation state change is first-class evidence',function()
  local a=capture()
  local r=base();r.aobs={{pattern='48 89 5C 24',status='observed',match_count=0,uniqueness='no_match'}}
  local b=capture({report=r})
  eq(a.candidates[1].validation.state,'not_attempted')
  eq(b.candidates[1].validation.state,'no_match')
  local d=S.compare(a,b)
  eq(#d.candidates.changed,1)
  local found=false
  for _,f in ipairs(d.candidates.changed[1].fields) do if f.field=='validation_state' then found=true end end
  eq(found,true)
end)

test('unique observed AOB maps to a unique candidate state',function()
  local r=base();r.aobs={{pattern='48 89 5C 24',status='observed',match_count=1,uniqueness='unique_current_scan'}}
  local s=ok(capture({report=r}))
  eq(s.candidates[1].validation.state,'unique')
  eq(s.candidates[1].runtime_validated,true)
end)

test('candidate added and removed are classified',function()
  local r=base()
  r.dynamic_analysis.patterns[2]={id='2',symbol='other',kind='literal_pattern',pattern='aa bb',source_script='s',source_line=20,consumer='C',status='candidate'}
  local b=capture({report=r})
  local d=S.compare(capture(),b)
  eq(#d.candidates.added,1);eq(#d.candidates.removed,0)
  local d2=S.compare(b,capture())
  eq(#d2.candidates.removed,1)
end)

test('coverage is preserved, including limit and absent validation',function()
  local r=base();r.coverage.collection={status='limit_reached',complete=false,units_discovered=2,
    units_processed=2,universe_known=false,denominator='captured_units',percentage=U.null,
    limitations={'TABLE_LIMIT'}}
  local s=ok(capture({report=r}))
  eq(s.coverage.collection.status,'limit_reached')
  eq(s.coverage.collection.complete,false)
  eq(s.coverage.collection.percentage,U.null)
  eq(s.coverage.validation.status,'unavailable')
  eq(s.coverage.validation.attempted,0)
end)

test('comparability distinguishes same source and different source',function()
  local a=capture()
  local d=S.compare(a,capture())
  eq(d.comparability.status,'comparable');eq(d.comparability.same_source,true)
  local r=base();r.scripts[1].text='local other = 1\n'
  local e=S.compare(a,capture({report=r}))
  eq(e.comparability.status,'partial_comparison')
  eq(e.comparability.same_source,false)
  eq(e.comparability.source_changed,true)
  eq(e.comparability.candidate_comparable,true)
  eq(e.comparability.strong_identity_only,true)
  eq(e.candidates.status,'partial')
end)

test('different target is explicit and not a candidate verdict',function()
  local a=capture()
  local r=base();r.target.name='Other.exe'
  local d=S.compare(a,capture({report=r}))
  eq(d.comparability.different_target,true)
  eq(d.comparability.status,'different_target')
end)

test('target build unknown when only the name is available',function()
  local a=capture()
  local r=base();r.modules={};r.target.attached=true
  local b=capture({report=r})
  eq(b.target.build_fingerprint_known,false)
  local d=S.compare(a,b)
  eq(d.comparability.target_build_unknown,true)
end)

test('normalization sorts candidates and dependencies and recomputes stable id',function()
  local r=base()
  r.dynamic_analysis.patterns[2]={id='2',symbol='aaa',kind='literal_pattern',pattern='aa',source_script='s',source_line=2,consumer='C',status='candidate'}
  local s=ok(capture({report=r}))
  local n1=S.normalize(s);local n2=S.normalize(n1)
  eq(n1.snapshot_id,n2.snapshot_id)
  eq(n1.candidates[1].identity.key..'|'..n1.candidates[2].identity.key,
     n2.candidates[1].identity.key..'|'..n2.candidates[2].identity.key)
  eq(n1.dependencies[1].name,'read_inventory')
end)

test('validate rejects unsupported version and missing fields',function()
  local s=capture()
  s.snapshot_version=2
  local ok1= S.validate(s);eq(ok1,false)
  local t=capture();t.candidates=nil
  local ok2= S.validate(t);eq(ok2,false)
end)

test('validate rejects oversized arrays',function()
  local s=capture()
  s.candidates={}
  for i=1,S.MAX_CANDIDATES+1 do s.candidates[i]={} end
  local ok1=S.validate(s);eq(ok1,false)
end)

test('target path is reduced to a name and not stored',function()
  local r=base();r.target.name='C:\\Games\\Game.exe'
  local s=ok(capture({report=r}))
  eq(s.target.process_name,'Game.exe')
  eq(E.encode(s):find('C:\\',1,true),nil)
end)

test('provider and helper paths are sanitized and redactions are populated',function()
  local r=base()
  r.dynamic_analysis.patterns[1].derivation={
    source_file='C:\\Users\\Name\\UE.lua',
    path='C:\\Users\\Name\\UE.Sig.X'
  }
  r.limitations={'C:\\Users\\Name\\secret.txt'}
  local s=ok(capture({report=r}))
  eq(s.candidates[1].provider,'UE.lua')
  eq(s.candidates[1].helper,'UE.Sig.X')
  assert(#s.redactions>0,'redactions must not be empty')
  local sorted=true
  for i=2,#s.redactions do if s.redactions[i-1]>s.redactions[i] then sorted=false end end
  eq(sorted,true)
  local text=E.encode(s)
  eq(text:find('Users',1,true),nil)
  eq(text:find('C:\\',1,true),nil)
  assert(text:find('provider_path',1,true)~=nil or #s.redactions>0)
end)

test('PII in limitations is sanitized and recorded',function()
  local r=base();r.limitations={'local path C:\\Users\\Name\\private.txt'}
  local s=ok(capture({report=r}))
  assert(#s.redactions>0)
  eq(E.encode(s):find('Users',1,true),nil)
  eq(s.limitations[1]:find('private.txt',1,true),nil)
end)

test('pattern diff works across changed source with strong identity',function()
  local a=capture()
  local r=base();r.scripts[1].text='local changed = 1\n'
  r.dynamic_analysis.patterns[1].pattern='48 8D xx'
  local d=S.compare(a,capture({report=r}))
  eq(d.comparability.status,'partial_comparison')
  eq(d.comparability.source_changed,true)
  eq(d.comparability.same_source,false)
  eq(d.comparability.candidate_comparable,true)
  eq(d.comparability.strong_identity_only,true)
  eq(#d.candidates.changed,1)
  eq(d.candidates.changed[1].fields[1].field,'pattern')
  eq(d.candidates.changed[1].status,'changed')
  eq(d.candidates.changed[1].changed.pattern,true)
end)

test('weak identity across changed source is not compared',function()
  local r=base();r.dynamic_analysis.patterns[1].symbol=nil
  r.dynamic_analysis.patterns[1].source_line=10
  local a=capture({report=r})
  r.scripts[1].text='local changed = 1\n'
  local b=capture({report=r})
  local d=S.compare(a,b)
  eq(d.comparability.status,'partial_comparison')
  eq(d.comparability.strong_identity_only,true)
  eq(d.comparability.candidate_comparable,false)
  eq(d.candidates.status,'not_comparable')
  eq(#d.candidates.added,0);eq(#d.candidates.removed,0)
  eq(#d.candidates.unknown,2)
end)

test('process_name is used to resolve the main module',function()
  local r=base()
  r.target={attached=true,process_name='Game.exe',architecture='x64',pid=1234}
  r.modules={{name='ntdll.dll',size=500},{name='Game.exe',size=1000,timestamp='2026-01-01'}}
  local s=ok(capture({report=r}))
  eq(s.target.process_name,'Game.exe')
  eq(s.target.main_module.name,'Game.exe')
  eq(s.target.fingerprint,capture().target.fingerprint)
end)

test('known different build is distinct from unknown build',function()
  local a=capture()
  local r=base();r.modules[1].size=2000
  local d=S.compare(a,capture({report=r}))
  eq(d.comparability.different_target_build,true)
  eq(d.comparability.same_target_build,false)
  eq(d.comparability.target_build_unknown,false)
  eq(d.comparability.status,'different_target_build')
end)

test('duplicate occurrence does not move when one pattern changes',function()
  local p1={id='1',symbol='dup',kind='literal_pattern',pattern='11 22',source_script='s',source_line=10,consumer='C',status='candidate'}
  local p2={id='2',symbol='dup',kind='literal_pattern',pattern='33 44',source_script='s',source_line=20,consumer='C',status='candidate'}
  local a=capture({patterns={p1,p2}})
  local r=base();r.dynamic_analysis.patterns={p1,p2}
  r.dynamic_analysis.patterns[1].pattern='55 66'
  local b=capture({report=r})
  eq(a.candidates[1].identity.occurrence,1)
  eq(b.candidates[1].identity.occurrence,1)
  local d=S.compare(a,b)
  eq(#d.candidates.changed,1)
  eq(d.candidates.changed[1].key,a.candidates[1].identity.key)
  eq(d.candidates.changed[1].fields[1].field,'pattern')
end)

test('identity delimiter collision is impossible',function()
  local p1={symbol='e',kind='literal_pattern',pattern='11',source_script='a|b',source_line=1,consumer='c',status='candidate'}
  local p2={symbol='e',kind='literal_pattern',pattern='11',source_script='a',source_line=1,consumer='b|c',status='candidate'}
  local s=capture({patterns={p1,p2}})
  assert(s.candidates[1].identity.key~=s.candidates[2].identity.key)
end)

test('wildcards xx and ?? normalize to one canonical form',function()
  local r=base();r.dynamic_analysis.patterns[1].pattern='48 xx 5C'
  local a=capture({report=r})
  r.dynamic_analysis.patterns[1].pattern='48 ?? 5C'
  local b=capture({report=r})
  eq(a.candidates[1].pattern,b.candidates[1].pattern)
  eq(a.candidates[1].pattern,'48xx5c')
end)

test('internal candidate truncation is explicit in limitations',function()
  local pats={}
  for i=1,S.MAX_CANDIDATES+1 do
    pats[i]={symbol='s'..i,kind='literal_pattern',pattern='aa',source_script='s',source_line=i,consumer='C',status='candidate'}
  end
  local s=ok(capture({patterns=pats}))
  eq(#s.candidates,S.MAX_CANDIDATES)
  local found=false
  for _,v in ipairs(s.limitations) do if v=='SNAPSHOT_CANDIDATE_LIMIT' then found=true end end
  eq(found,true)
end)

test('dependency truncation is explicit in limitations',function()
  local r=base();r.dependencies={}
  for i=1,S.MAX_DEPENDENCIES+1 do r.dependencies[i]={name='d'..i,relation='reads',scope='local'} end
  local s=ok(capture({report=r}))
  eq(#s.dependencies,S.MAX_DEPENDENCIES)
  local found=false
  for _,v in ipairs(s.limitations) do if v=='SNAPSHOT_DEPENDENCY_LIMIT' then found=true end end
  eq(found,true)
end)

test('condition dependencies are sanitized',function()
  local r=base()
  r.dynamic_analysis.patterns[1].condition={kind='conditional_expression',text='x',dependencies={'C:\\\\Users\\\\Name\\\\dep'},resolution='unknown',fallback='start'}
  local s=ok(capture({report=r}))
  assert(#s.redactions>0)
  local dep=s.candidates[1].condition.dependencies[1]
  assert(dep:find('Users',1,true)==nil)
  eq(dep,'<redacted-path>')
end)

test('user limitations reserve system truncation slots',function()
  local r=base();r.limitations={}
  for i=1,200 do r.limitations[i]='user limitation '..i end
  local pats={}
  for i=1,S.MAX_CANDIDATES+1 do pats[i]={symbol='s'..i,kind='literal_pattern',pattern='aa',source_script='s',source_line=i,consumer='C',status='candidate'} end
  r.dynamic_analysis.patterns=pats
  local s=ok(capture({report=r}))
  assert(#s.limitations<=S.MAX_LIMITATIONS)
  local candidate,limitation=false,false
  for _,v in ipairs(s.limitations) do
    if v=='SNAPSHOT_CANDIDATE_LIMIT' then candidate=true end
    if v=='SNAPSHOT_LIMITATION_LIMIT' then limitation=true end
  end
  eq(candidate,true);eq(limitation,true)
end)

test('symbol-only and conditional rows are evidence, not candidates',function()
  local r=base()
  r.dynamic_analysis.patterns={
    {symbol='lit',kind='literal_pattern',pattern='aa',source_script='s',source_line=1,consumer='C',status='candidate'},
    {symbol='sym',kind='symbol_only',pattern=nil,source_script='s',source_line=2,consumer='C',status='not_applicable'},
    {kind='conditional_pattern',pattern=nil,source_script='s',source_line=3,consumer='C',status='unresolved'}
  }
  local s=ok(capture({report=r}))
  eq(#s.candidates,1)
  eq(s.candidates[1].symbol,'lit')
end)

test('summary reports counts and states',function()
  local s=capture()
  local sum=S.summary(s)
  eq(sum.candidates,1);eq(sum.validated,0)
  eq(sum.collection_status,'complete');eq(sum.validation_status,'unavailable')
end)

test('diff output contains no automatic verdict language',function()
  local a=capture()
  local r=base();r.dynamic_analysis.patterns[1].pattern='48 89 5C 25'
  r.aobs={{pattern='48 89 5C 25',status='observed',match_count=0,uniqueness='no_match'}}
  r.coverage.validation.status='partial';r.coverage.validation.runtime_attempted=1;r.coverage.validation.runtime_no_match=1
  local d=S.compare(a,capture({report=r}))
  local text=E.encode(d):lower()
  for _,word in ipairs({'fixed','broken','regressed','compatible','incompatible','working'}) do
    eq(text:find(word,1,true),nil,'forbidden word '..word)
  end
  contains(text,'changed')
end)

test('unknown identity is partial, not guessed',function()
  local a=capture();local b=capture()
  a.candidates[1].identity={key=U.null,kind='unknown',occurrence=1}
  b.candidates[1].identity={key=U.null,kind='unknown',occurrence=1}
  local d=S.compare(a,b)
  eq(d.candidates.status,'partial')
  eq(#d.candidates.unknown,2)
end)

test('static report uses derived source fingerprint and unknown universe',function()
  local r=base()
  r.scripts={}
  r.observations=r.dynamic_analysis.patterns
  r.dynamic_analysis.patterns=nil
  r.coverage.discovery.universe_known=false
  r.coverage.discovery.status='unknown'
  local s=ok(capture({report=r}))
  eq(s.source.kind,'static_lua_report')
  eq(s.source.fingerprint_scope,'derived_candidates')
  eq(s.coverage.discovery.universe_known,false)
end)

local out=CESUITE_TEST_OUTPUT
if type(out)=='string' and out~='' then
  local a=capture();local r=base()
  r.dynamic_analysis.patterns[1].pattern='48 89 5C 25'
  r.aobs={{pattern='48 89 5C 25',status='observed',match_count=0,uniqueness='no_match'}}
  r.coverage.validation.status='partial';r.coverage.validation.runtime_attempted=1;r.coverage.validation.runtime_no_match=1
  local b=capture({report=r})
  local f=assert(io.open(out..'/snapshot_a.json','wb'));f:write(S.encode(a));f:close()
  local g=assert(io.open(out..'/snapshot_b.json','wb'));g:write(S.encode(b));g:close()
  local h=assert(io.open(out..'/diff.json','wb'));h:write(E.encode(S.compare(a,b)));h:close()
end
print(string.format('%d snapshot tests passed (pure model)',tests))
