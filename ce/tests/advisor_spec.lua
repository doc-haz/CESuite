package.path='ce/modules/?.lua;'..package.path
local A=require('advisor')
local S=require('snapshot')
local D=require('snapshotdiff')
local Json=require('json')
local R=require('advisorrules')
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
local function arr(...) return U.array({...}) end
local function fields(list) local out=U.array();for i=1,#list do out[i]=list[i] end;return out end

local function base()
  return {
    diff_version=1,
    a={snapshot_id='snap-a'},
    b={snapshot_id='snap-b'},
    comparability={status='comparable',candidate_comparable=true,strong_identity_only=false,
      source_changed=false,different_target_build=false,different_target=false,target_build_unknown=false},
    coverage={
      collection={changed=false,a_status='complete',b_status='complete',limitations=U.array()},
      discovery={changed=false,a_status='partial',b_status='partial',limitations=U.array()},
      validation={changed=false,a_status='complete',b_status='complete',limitations=U.array()}
    },
    candidates={changed=U.array(),added=U.array(),removed=U.array(),unknown=U.array()},
    dependencies={added=U.array(),removed=U.array(),changed=U.array()},
    unresolved={added=U.array(),removed=U.array()},
    modules={changed=false}
  }
end
local function with_change(field,a,b,key)
  local d=base()
  d.candidates.changed[1]={key=key or 'c1',fields=fields({{field=field,a=a,b=b}})}
  return d
end
local function pat_for_id(key)
  local d=base();d.candidates.changed[1]={key=key,fields=fields({{field='pattern',a='aa',b='bb'}})};return d
end
local function analyze(d,opts)
  local r,e=A.analyze(d,opts or {generated_at='2026-01-01T00:00:00Z'})
  assert(r, e and e.code or 'no report')
  return r
end
local function has(r,code)
  for _,f in ipairs(r.findings) do if f.code==code then return f end end
end

test('no meaningful change is an INFO finding',function()
  local r=analyze(base())
  local f=has(r,'NO_MEANINGFUL_CHANGE')
  assert(f);eq(f.severity,'INFO');eq(f.confidence,'exact')
  eq(#r.findings,1)
end)

test('pattern change is neutral and cited',function()
  local r=analyze(with_change('pattern','48 89 5C 24','48 89 5C 25'))
  local f=has(r,'PATTERN_CHANGED');assert(f);eq(f.category,'pattern_change')
  eq(#f.evidence_refs>=2,true);assert(f.observations[1]:find('pattern',1,true))
  assert(f.interpretation:find('differs',1,true))
  assert(not f.interpretation:find('broken',1,true))
end)

test('validation unique to no_match is high, exact',function()
  local r=analyze(with_change('validation_state','unique','no_match'))
  local f=has(r,'PATTERN_NO_LONGER_MATCHES_OBSERVED_TARGET');assert(f)
  eq(f.severity,'HIGH');eq(f.confidence,'exact');eq(f.status,'observed')
  eq(#f.do_not_assume>=1,true)
  eq(#f.evidence_refs,3)
end)

test('validation unique to ambiguous is high',function()
  local r=analyze(with_change('validation_state','unique','ambiguous'))
  local f=has(r,'PATTERN_NOW_MATCHES_MULTIPLE_LOCATIONS');assert(f);eq(f.severity,'HIGH')
end)

test('validation unavailable never claims invalid',function()
  local r=analyze(with_change('validation_state','unique','unavailable'))
  local f=has(r,'VALIDATION_COVERAGE_UNAVAILABLE');assert(f)
  eq(f.category,'runtime_validation_unavailable')
  assert(f.interpretation:find('could not be established',1,true))
  assert(f.do_not_assume[1]:find('Do not assume',1,true))
end)

test('source change is separate from candidate change',function()
  local d=with_change('pattern','aa','bb');d.comparability.source_changed=true
  local r=analyze(d)
  assert(has(r,'SOURCE_CHANGED'));assert(has(r,'PATTERN_CHANGED'))
  eq(has(r,'SOURCE_CHANGED').confidence,'exact')
end)

test('different target build is review context, not incompatibility',function()
  local d=base();d.comparability.different_target_build=true
  local r=analyze(d);local f=has(r,'TARGET_BUILD_CHANGED');assert(f);eq(f.confidence,'exact')
  assert(f.interpretation:find('build context',1,true))
  assert(not f.interpretation:find('incompatible',1,true))
end)

test('target build unknown remains unknown',function()
  local d=base();d.comparability.target_build_unknown=true
  local r=analyze(d);local f=has(r,'TARGET_BUILD_UNKNOWN');assert(f);eq(f.status,'unknown');eq(f.confidence,'unknown')
end)

test('provider and consumer changes are provenance findings',function()
  local d=with_change('provider','helper_a','helper_b');d.candidates.changed[1].fields[2]={field='consumer',a='C1',b='C2'}
  local r=analyze(d)
  assert(has(r,'PROVIDER_CHANGED'));assert(has(r,'CONSUMER_CHANGED'))
end)

test('unresolved added and removed',function()
  local d=base();d.unresolved.added=arr({code='CONDITIONAL_DEPENDENCY',name='Launch'})
  d.unresolved.removed=arr({code='CONDITIONAL_DEPENDENCY',name='Old'})
  local r=analyze(d);assert(has(r,'UNRESOLVED_DEPENDENCY_ADDED'));assert(has(r,'UNRESOLVED_DEPENDENCY_REMOVED'))
end)

test('coverage change is explicit and not a table verdict',function()
  local d=base();d.coverage.discovery.changed=true
  local r=analyze(d);local f=has(r,'DISCOVERY_COVERAGE_CHANGED');assert(f);eq(f.severity,'LOW')
  assert(f.do_not_assume[1]:find('missing',1,true))
end)

test('validation coverage unavailable is explicit',function()
  local d=base();d.coverage.validation.changed=true
  local r=analyze(d);assert(has(r,'VALIDATION_COVERAGE_CHANGED'))
end)

test('limit reached creates bounded-confidence finding',function()
  local d=base();d.coverage.collection.a_status='limit_reached'
  local r=analyze(d);local f=has(r,'EVIDENCE_LIMIT_REACHED');assert(f);eq(f.category,'operation_limit')
end)

test('module inventory change is contextual',function()
  local d=base();d.modules.changed=true
  local r=analyze(d);assert(has(r,'MODULE_INVENTORY_CHANGED'))
end)

test('weak identity is not comparable and never line-matched',function()
  local d=base();d.candidates.unknown=arr({key='u1',symbol='unknown'})
  local r=analyze(d);local f=has(r,'WEAK_CANDIDATE_IDENTITY');assert(f);eq(f.status,'not_comparable')
  assert(f.do_not_assume[1]:find('weak',1,true))
end)

test('not comparable suppresses candidate-level causal findings',function()
  local d=with_change('validation_state','unique','no_match');d.comparability.status='not_comparable'
  local r=analyze(d);assert(has(r,'COMPARISON_NOT_COMPARABLE'));assert(not has(r,'PATTERN_NO_LONGER_MATCHES_OBSERVED_TARGET'))
  eq(#r.findings,1)
end)

test('deterministic report and finding identities',function()
  local d=with_change('pattern','aa','bb')
  local a=analyze(d);local b=analyze(d)
  eq(a.advisor_report_id,b.advisor_report_id);eq(a.findings[1].finding_id,b.findings[1].finding_id)
end)

test('finding order is stable for changed-array order',function()
  local d=base()
  d.candidates.changed=arr({key='b',fields=fields({{field='pattern',a='b1',b='b2'}})},
    {key='a',fields=fields({{field='pattern',a='a1',b='a2'}})})
  local r=analyze(d);eq(r.findings[1].code,r.findings[2].code)
  eq(r.findings[1].evidence_refs[1].id,'a');eq(r.findings[2].evidence_refs[1].id,'b')
end)

test('malformed inputs fail closed',function()
  local r,e=A.analyze(nil);eq(r,nil);eq(e.code,'invalid_input')
  r,e=A.analyze({diff_version=1});eq(r,nil);eq(e.code,'invalid_input')
  r,e=A.analyze({diff_version=2});eq(r,nil);eq(e.code,'unsupported_input')
  r,e=A.analyze('foo');eq(r,nil);eq(e.code,'invalid_input')
  r,e=A.analyze({type='unknown'});eq(r,nil);eq(e.code,'unsupported_input')
end)

test('tampered report fails validation',function()
  local r=analyze(base());r.findings[1].severity='BOGUS'
  local ok,errs=A.validate(r);eq(ok,false);assert(#errs>0)
end)

test('explain returns rule and evidence trace',function()
  local r=analyze(with_change('pattern','aa','bb'));local f=r.findings[1]
  local x,e=A.explain(r,f.finding_id);assert(x,e);eq(x.rule_id,f.rule_id);eq(x.matched_evidence,f.evidence_refs);assert(x.rule_metadata);eq(x.limitations,f.limitations)
end)

test('summary is compact and neutral',function()
  local r=analyze(base());local s=A.summary(r)
  assert(s:find('no automatic change',1,true));assert(not s:find('broken',1,true))
end)

test('single snapshot validation unavailable',function()
  local s={snapshot_version=1,snapshot_id='snap-s',coverage={
    collection={status='complete'},validation={status='unavailable'}},limitations={'SNAPSHOT_PARTIAL'}}
  local r,e=A.analyze(s,{generated_at='2026-01-01T00:00:00Z'});assert(r,e)
  assert(has(r,'VALIDATION_COVERAGE_UNAVAILABLE'))
end)

test('analysis input is accepted minimally',function()
  local a={mode='extensive',suite_version='0.3.2',coverage={
    collection={status='complete'},validation={status='unavailable'}},limitations={}}
  local r,e=A.analyze(a,{generated_at='2026-01-01T00:00:00Z'});assert(r,e)
  assert(has(r,'VALIDATION_COVERAGE_UNAVAILABLE'))
end)

test('oversized candidate input fails closed',function()
  local d=base();local big=U.array()
  for i=1,2001 do big[i]={key='k'..i,fields=U.array()} end
  d.candidates.changed=big
  local r,e=A.analyze(d);eq(r,nil);eq(e.code,'input_limit')
end)

test('malicious pattern text is data, not execution',function()
  local d=with_change('pattern','safe',']]; error("EXECUTED") --')
  local r=analyze(d);assert(r)
  local found=false
  for _,f in ipairs(r.findings) do for _,o in ipairs(f.observations) do if o:find('EXECUTED',1,true) then found=true end end end
  eq(found,true)
end)

test('duplicate changes deduplicate',function()
  local d=base()
  d.candidates.changed=arr({key='same',fields=fields({{field='pattern',a='a',b='b'},{field='pattern',a='a',b='b'}})})
  local r=analyze(d);local n=0
  for _,f in ipairs(r.findings) do if f.code=='PATTERN_CHANGED' then n=n+1 end end
  eq(n,1)
end)

test('contradictory context is preserved, not resolved arbitrarily',function()
  local d=with_change('validation_state','unique','no_match');d.comparability.target_build_unknown=true
  local r=analyze(d)
  assert(has(r,'PATTERN_NO_LONGER_MATCHES_OBSERVED_TARGET'));assert(has(r,'TARGET_BUILD_UNKNOWN'))
  eq(has(r,'TARGET_BUILD_UNKNOWN').status,'unknown')
end)

test('unsupported ruleset is rejected',function()
  local r,e=A.analyze(base(),{ruleset_version=2})
  eq(r,nil);eq(e.code,'unsupported_ruleset')
end)

test('all next steps are review-only',function()
  local d=with_change('validation_state','unique','no_match');d.comparability.source_changed=true
  local r=analyze(d)
  for _,f in ipairs(r.findings) do
    for _,s in ipairs(f.suggested_next_steps) do
      assert(A.ALLOWED_ACTIONS[s.action])
      assert(not s.action:find('replace',1,true));assert(not s.action:find('patch',1,true))
    end
  end
end)

test('real snapshot diff integrates with stable evidence shape',function()
  local function load(name)
    local f=assert(io.open('ce/tests/fixtures/corpus/snapshots/'..name,'rb'));local s=f:read('*a');f:close()
    return assert(Json.decode(s))
  end
  local d=D.compare(load('pattern-changed-a.json'),load('pattern-changed-b.json'))
  local r=analyze(d)
  assert(has(r,'PATTERN_CHANGED'))
  local ok,errs=A.validate(r,d);assert(ok,errs[1] and (errs[1].code..' '..errs[1].path) or 'real diff referential failed')
  local d2=D.compare(load('different-source-a.json'),load('different-source-b.json'))
  local r2=analyze(d2)
  assert(has(r2,'SOURCE_CHANGED'))
  local ok2,errs2=A.validate(r2,d2);assert(ok2,errs2[1] and (errs2[1].code..' '..errs2[1].path) or 'real source referential failed')
end)

test('referential validation accepts generated evidence refs',function()
  local d=with_change('validation_state','unique','no_match')
  local r=analyze(d)
  local ok,errs=A.validate(r,d)
  assert(ok, errs[1] and (errs[1].code..' '..errs[1].path..' '..errs[1].message) or 'referential validation failed')
end)

test('referential validation catches missing candidate',function()
  local d=with_change('pattern','aa','bb');local r=analyze(d)
  r.findings[1].evidence_refs[1].id='does-not-exist'
  local ok,errs=A.validate(r,d);eq(ok,false)
  local found=false
  for _,e in ipairs(errs) do if e.code=='MISSING_CANDIDATE' then found=true end end
  eq(found,true)
end)

test('referential validation catches wrong value and source',function()
  local d=with_change('pattern','aa','bb');local r=analyze(d)
  r.findings[1].evidence_refs[1].value='wrong-value'
  r.findings[1].evidence_refs[2].source='snapshot_bad'
  local ok,errs=A.validate(r,d);eq(ok,false)
  local has_value,has_source=false,false
  for _,e in ipairs(errs) do
    if e.code=='EVIDENCE_VALUE_MISMATCH' then has_value=true end
    if e.code=='UNKNOWN_SOURCE' then has_source=true end
  end
  eq(has_value,true);eq(has_source,true)
end)

test('duplicate evidence refs fail structural validation',function()
  local r=analyze(base())
  r.findings[1].evidence_refs[2]=r.findings[1].evidence_refs[1]
  local ok,errs=A.validate(r);eq(ok,false)
  local found=false
  for _,e in ipairs(errs) do if e.code=='DUPLICATE_EVIDENCE_REF' then found=true end end
  eq(found,true)
end)

test('findings cap is explicit, never silent',function()
  local d=base();local changed=U.array()
  for i=1,70 do
    changed[i]={key='k'..i,fields=fields({{field='pattern',a='a'..i,b='b'..i}})}
  end
  d.candidates.changed=changed
  local r=analyze(d)
  eq(#r.findings,64);eq(r.truncated,true);eq(r.truncation.findings_capped,true)
  local found=false
  for _,v in ipairs(r.limitations) do if v=='ADVISOR_FINDINGS_CAPPED_AT_64' then found=true end end
  eq(found,true)
  eq(r.findings[1].confidence,'strong')
end)

test('limit minus one does not mark truncation',function()
  local d=base();local changed=U.array()
  for i=1,63 do
    changed[i]={key='k'..i,fields=fields({{field='pattern',a='a'..i,b='b'..i}})}
  end
  d.candidates.changed=changed
  local r=analyze(d);eq(#r.findings,63);eq(r.truncated,false)
end)

test('ruleset metadata is consistent and frozen at 26 rules',function()
  local ok,errs=A.validate_ruleset();assert(ok,errs[1] and errs[1].message or 'ruleset invalid')
  eq(#errs,0)
end)

test('target build unknown suppresses build-change claim',function()
  local d=base();d.comparability.different_target_build=true;d.comparability.target_build_unknown=true
  local r=analyze(d)
  assert(has(r,'TARGET_BUILD_UNKNOWN'));assert(not has(r,'TARGET_BUILD_CHANGED'))
end)

test('meaningful findings suppress no-meaningful-change',function()
  local d=base();d.coverage.discovery.changed=true
  local r=analyze(d);assert(not has(r,'NO_MEANINGFUL_CHANGE'))
end)

test('precedence is explicit and non-decreasing',function()
  local d=with_change('validation_state','unique','no_match');d.comparability.source_changed=true
  local r=analyze(d);local last=0
  for _,f in ipairs(r.findings) do assert(f.precedence and f.precedence>=last);last=f.precedence end
end)

test('delimiter collision does not merge distinct evidence keys',function()
  local d=base()
  d.candidates.changed=arr(
    {key='a|b',fields=fields({{field='pattern',a='1',b='2'}})},
    {key='a',fields=fields({{field='pattern',a='3',b='4'}})})
  local r=analyze(d);local n=0
  for _,f in ipairs(r.findings) do if f.code=='PATTERN_CHANGED' then n=n+1 end end
  eq(n,2)
end)

test('findings limit exact and plus one',function()
  local function build(n)
    local d=base();local changed=U.array()
    for i=1,n do changed[i]={key='k'..i,fields=fields({{field='pattern',a='a'..i,b='b'..i}})} end
    d.candidates.changed=changed;return analyze(d)
  end
  local exact=build(64);eq(#exact.findings,64);eq(exact.truncated,false)
  local over=build(65);eq(#over.findings,64);eq(over.truncated,true)
  eq(over.truncation.findings_capped,true)
end)

test('candidate bound exact and plus one',function()
  local function at(n)
    local d=base();local changed=U.array()
    for i=1,n do changed[i]={key='k'..i,fields=U.array()} end
    d.candidates.changed=changed;return A.analyze(d,{generated_at='2026-01-01T00:00:00Z'})
  end
  local r,e=at(2000);assert(r,e and e.code);eq(r.truncated,false)
  local r2,e2=at(2001);eq(r2,nil);eq(e2.code,'input_limit')
end)

test('referential validation catches unknown field/entity and malformed id',function()
  local d=with_change('pattern','aa','bb');local r=analyze(d)
  r.findings[1].evidence_refs[1].field='no.such.field'
  r.findings[1].evidence_refs[2].entity='no_such_entity'
  r.findings[1].evidence_refs[3].id=42
  local ok,errs=A.validate(r,d);eq(ok,false)
  local fields,entities,ids=false,false,false
  for _,e in ipairs(errs) do
    if e.code=='UNKNOWN_FIELD' then fields=true end
    if e.code=='UNKNOWN_ENTITY' then entities=true end
    if e.code=='MALFORMED_ID' then ids=true end
  end
  eq(fields,true);eq(entities,true);eq(ids,true)
end)

test('single snapshot referential validation',function()
  local s={snapshot_version=1,snapshot_id='snap-s',coverage={
    collection={status='complete'},validation={status='unavailable'}},limitations={'SNAPSHOT_PARTIAL'}}
  local r,e=A.analyze(s,{generated_at='2026-01-01T00:00:00Z'});assert(r,e)
  local ok,errs=A.validate(r,s);assert(ok,errs[1] and errs[1].message or 'snapshot referential failed')
end)

test('analysis referential validation',function()
  local a={mode='extensive',suite_version='0.3.2',coverage={
    collection={status='complete'},validation={status='unavailable'}},limitations={}}
  local r,e=A.analyze(a,{generated_at='2026-01-01T00:00:00Z'});assert(r,e)
  local ok,errs=A.validate(r,a);assert(ok,errs[1] and errs[1].message or 'analysis referential failed')
end)

test('shared assumptions retain exact wording',function()
  local d=with_change('validation_state','unique','no_match');d.comparability.source_changed=true
  local r=analyze(d)
  local src=has(r,'SOURCE_CHANGED');assert(src)
  local found=false
  for _,s in ipairs(src.do_not_assume) do if s==A.ASSUMPTIONS.SOURCE_CHANGE_NOT_BREAKAGE then found=true end end
  eq(found,true)
end)

test('finding array bounds are explicit',function()
  local function rejected(mut)
    local r=analyze(base());mut(r.findings[1])
    local ok=A.validate(r);eq(ok,false);return true
  end
  assert(rejected(function(f)
    for i=1,16 do f.evidence_refs[#f.evidence_refs+1]={source='diff',entity='comparability',id=nil,field='x'..i,value=true} end
  end))
  assert(rejected(function(f) for i=1,16 do f.observations[#f.observations+1]='o'..i end end))
  assert(rejected(function(f) for i=1,9 do f.likely_causes[#f.likely_causes+1]='c'..i end end))
  assert(rejected(function(f) for i=1,8 do f.suggested_next_steps[#f.suggested_next_steps+1]={action='REVIEW_EVIDENCE',detail='s'..i} end end))
  assert(rejected(function(f) for i=1,16 do f.do_not_assume[#f.do_not_assume+1]='d'..i end end))
  assert(rejected(function(f) for i=1,17 do f.limitations[#f.limitations+1]='l'..i end end))
end)

test('unexpected report property fails structural parity',function()
  local r=analyze(base());r.unexpected=true
  local ok,errs=A.validate(r);eq(ok,false)
  local found=false
  for _,e in ipairs(errs) do if e.code=='UNEXPECTED_PROPERTY' then found=true end end
  eq(found,true)
end)

test('report identity excludes timestamps',function()
  local d=with_change('pattern','aa','bb')
  local a=analyze(d,{generated_at='2020-01-01T00:00:00Z'})
  local b=analyze(d,{generated_at='2030-01-01T00:00:00Z'})
  eq(a.advisor_report_id,b.advisor_report_id)
  eq(a.findings[1].finding_id,b.findings[1].finding_id)
end)

test('limitations cap is explicit',function()
  local d=base();d.a.limitations=U.array()
  for i=1,40 do d.a.limitations[i]='L'..i end
  local r=analyze(d);eq(r.truncated,true);eq(r.truncation.limitations_capped,true)
  local found=false
  for _,v in ipairs(r.limitations) do if v=='ADVISOR_LIMITATIONS_CAPPED' then found=true end end
  eq(found,true)
end)

test('privacy-sensitive evidence refs are rejected',function()
  local r=analyze(base());r.findings[1].evidence_refs[1].value='C:\\Users\\alice\\secret'
  local ok,errs=A.validate(r);eq(ok,false)
  local found=false
  for _,e in ipairs(errs) do if e.code=='PRIVACY_VIOLATION' then found=true end end
  eq(found,true)
end)

test('malformed candidate entries fail closed',function()
  local d=base();d.candidates.changed=arr('not-a-table')
  local r,e=A.analyze(d);eq(r,nil);eq(e.code,'invalid_input')
end)

test('field-level truncation bounds are exercised directly',function()
  local function b()
    return {evidence_refs=U.array(),observations=U.array(),likely_causes=U.array(),
      suggested_next_steps=U.array(),do_not_assume=U.array(),limitations=U.array()}
  end
  local f=b();for i=1,16 do f.evidence_refs[i]={source='diff',entity='comparability',field='x'..i,value=true} end
  eq(A._bound_finding(f).truncated,false)
  f.evidence_refs[17]={source='diff',entity='comparability',field='x17',value=true}
  eq(A._bound_finding(f).truncated,true)

  f=b();for i=1,16 do f.observations[i]='o'..i end;eq(A._bound_finding(f).truncated,false)
  f.observations[17]='o17';eq(A._bound_finding(f).truncated,true)

  f=b();for i=1,8 do f.likely_causes[i]='c'..i end;eq(A._bound_finding(f).truncated,false)
  f.likely_causes[9]='c9';eq(A._bound_finding(f).truncated,true)

  f=b();for i=1,8 do f.suggested_next_steps[i]={action='REVIEW_EVIDENCE',detail='d'..i} end
  eq(A._bound_finding(f).truncated,false)
  f.suggested_next_steps[9]={action='REVIEW_EVIDENCE',detail='d9'};eq(A._bound_finding(f).truncated,true)

  f=b();for i=1,16 do f.do_not_assume[i]='a'..i end;eq(A._bound_finding(f).truncated,false)
  f.do_not_assume[17]='a17';eq(A._bound_finding(f).truncated,true)

  f=b();for i=1,16 do f.limitations[i]='l'..i end;eq(A._bound_finding(f).truncated,false)
  f.limitations[17]='l17';eq(A._bound_finding(f).truncated,true)
end)

test('finding identity is sensitive to evidence values',function()
  local a=analyze(with_change('pattern','aa','bb'))
  local b=analyze(with_change('pattern','aa','cc'))
  assert(a.findings[1].finding_id~=b.findings[1].finding_id)
end)

test('explain metadata is frozen against ruleset mutation',function()
  local r=analyze(with_change('pattern','aa','bb'));local original=r.findings[1].rule_metadata.severity
  R.RULE_METADATA.PATTERN_CHANGED.severity='LOW'
  local x=assert(A.explain(r,r.findings[1].finding_id))
  eq(x.rule_metadata.severity,original)
  R.RULE_METADATA.PATTERN_CHANGED.severity=original
end)

test('truncation/input/ref type parity',function()
  local r=analyze(base());r.truncation.extra=true
  local ok,errs=A.validate(r);eq(ok,false)
  local found=false;for _,e in ipairs(errs) do if e.code=='UNEXPECTED_PROPERTY' then found=true end end;eq(found,true)

  r=analyze(base());r.findings[1].evidence_refs[1].id=42
  ok,errs=A.validate(r);eq(ok,false)
  found=false;for _,e in ipairs(errs) do if e.code=='MALFORMED_REF' then found=true end end;eq(found,true)

  r=analyze(base());r.input.extra=true
  ok,errs=A.validate(r);eq(ok,false)
  found=false;for _,e in ipairs(errs) do if e.code=='UNEXPECTED_PROPERTY' then found=true end end;eq(found,true)

  r=analyze(base());r.summary.extra=true
  ok,errs=A.validate(r);eq(ok,false)
  found=false;for _,e in ipairs(errs) do if e.code=='UNEXPECTED_PROPERTY' then found=true end end;eq(found,true)

  r=analyze(base());r.findings[1].observations[1]=42
  ok,errs=A.validate(r);eq(ok,false)
  found=false;for _,e in ipairs(errs) do if e.code=='INVALID_FIELD' then found=true end end;eq(found,true)

  r=analyze(base());r.findings[1].rule_metadata.required_evidence[1]=42
  ok,errs=A.validate(r);eq(ok,false)
  found=false;for _,e in ipairs(errs) do if e.code=='INVALID_FIELD' then found=true end end;eq(found,true)
end)

test('ruleset duplicate and mandatory-assumption sabotage are detected',function()
  local extra={};for k,v in pairs(R.RULES[1]) do extra[k]=v end
  local before=#R.RULES;R.RULES[#R.RULES+1]=extra
  local ok,errs=A.validate_ruleset();eq(ok,false)
  local dup=false;for _,e in ipairs(errs) do if e.code=='DUPLICATE_RULE' then dup=true end end;eq(dup,true)
  table.remove(R.RULES)

  local old=R.RULE_METADATA.SOURCE_CHANGED.mandatory_assumptions
  R.RULE_METADATA.SOURCE_CHANGED.mandatory_assumptions={}
  ok,errs=A.validate_ruleset();eq(ok,false)
  local missing=false;for _,e in ipairs(errs) do if e.code=='MISSING_DO_NOT_ASSUME' then missing=true end end;eq(missing,true)
  R.RULE_METADATA.SOURCE_CHANGED.mandatory_assumptions=old
end)

test('dedupe occurs before finding cap',function()
  local d=base();local changed=U.array()
  for i=1,70 do changed[i]={key='same',fields=fields({{field='pattern',a='a',b='b'}})} end
  d.candidates.changed=changed
  local r=analyze(d);eq(#r.findings,1);eq(r.truncated,false);eq(r.truncation.findings_capped,false)
  local found=false;for _,v in ipairs(r.limitations) do if v=='ADVISOR_FINDINGS_CAPPED_AT_64' then found=true end end;eq(found,false)
end)

test('id grammar rejects delimiter/oversized/control',function()
  local function expect_bad(id)
    local d=pat_for_id(id);local r=assert(A.analyze(d,{generated_at='2026-01-01T00:00:00Z'}))
    local ok,errs=A.validate(r,d);eq(ok,false)
    local found=false;for _,e in ipairs(errs) do if e.code=='MALFORMED_ID' then found=true end end
    eq(found,true)
  end
  expect_bad('a|b');expect_bad(string.rep('x',5000));expect_bad('a\1b')
end)

test('UNC privacy is rejected before referential mismatch',function()
  local d=with_change('pattern','aa','bb');local r=analyze(d)
  r.findings[1].evidence_refs[1].value='\\\\server\\share'
  local ok,errs=A.validate(r,d);eq(ok,false)
  local found=false;for _,e in ipairs(errs) do if e.code=='PRIVACY_VIOLATION' then found=true end end
  eq(found,true)
end)

test('invalid source is always UNKNOWN_SOURCE',function()
  local s={snapshot_version=1,snapshot_id='snap-s',coverage={collection={status='complete'},validation={status='unavailable'}},limitations={}}
  local r=assert(A.analyze(s,{generated_at='2026-01-01T00:00:00Z'}))
  r.findings[1].evidence_refs[1].source='snapshot_x'
  local ok,errs=A.validate(r,s);eq(ok,false)
  local found=false;for _,e in ipairs(errs) do if e.code=='UNKNOWN_SOURCE' then found=true end end
  eq(found,true)
end)

test('ruleset detects unknown next-step enum',function()
  A.ALLOWED_ACTIONS.BOGUS_ACTION=true
  local ok,errs=A.validate_ruleset();eq(ok,false)
  local found=false;for _,e in ipairs(errs) do if e.code=='UNKNOWN_NEXT_STEP' then found=true end end
  eq(found,true);A.ALLOWED_ACTIONS.BOGUS_ACTION=nil
end)

test('multiple truncation signals cannot erase each other',function()
  local d=base();local changed=U.array()
  for i=1,70 do changed[i]={key='k'..i,fields=fields({{field='pattern',a='a'..i,b='b'..i}})} end
  d.candidates.changed=changed;d.a.limitations=U.array()
  for i=1,40 do d.a.limitations[i]='L'..i end
  local r=analyze(d)
  eq(r.truncated,true);eq(r.truncation.findings_capped,true);eq(r.truncation.limitations_capped,true)
  local codes={};for _,v in ipairs(r.limitations) do codes[v]=true end
  eq(codes['ADVISOR_FINDINGS_CAPPED_AT_64'],true)
  eq(codes['ADVISOR_LIMITATIONS_CAPPED'],true)
  eq(codes['ADVISOR_CONFIDENCE_DEGRADED_BY_TRUNCATION'],true)
end)

test('field cap signal reaches report',function()
  local raw={rule_id='PATTERN_CHANGED',code='PATTERN_CHANGED',category='pattern_change',
    severity='MEDIUM',status='observed',confidence='exact',precedence=4,_key='field-test',
    evidence_refs=U.array({{source='diff',entity='comparability',id=nil,field='status',value='comparable'}}),
    observations=U.array(),likely_causes=U.array(),suggested_next_steps=U.array(),
    do_not_assume=U.array({'Do not assume this test is evidence.'}),limitations=U.array()}
  for i=1,17 do raw.observations[i]='observation '..i end
  local r=assert(A._debug_report(with_change('pattern','aa','bb'),U.array({raw}),{generated_at='2026-01-01T00:00:00Z'}))
  eq(r.truncated,true);eq(r.truncation.fields_capped,true);eq(r.findings[1].truncated,true)
  local found=false;for _,v in ipairs(r.limitations) do if v=='ADVISOR_FINDING_FIELDS_CAPPED' then found=true end end
  eq(found,true)
end)

test('finding ID is independent of evidence-ref order',function()
  local function raw(refs)
    return U.array({{rule_id='PATTERN_CHANGED',code='PATTERN_CHANGED',category='pattern_change',
      severity='MEDIUM',status='observed',confidence='exact',precedence=4,_key='order-test',
      evidence_refs=refs,observations=U.array({'observation'}),likely_causes=U.array(),
      suggested_next_steps=U.array(),do_not_assume=U.array({'Do not assume this is evidence.'}),
      limitations=U.array()}})
  end
  local r1={source='snapshot_a',entity='candidate',id='c1',field='pattern',value='aa'}
  local r2={source='snapshot_b',entity='candidate',id='c1',field='pattern',value='bb'}
  local d=with_change('pattern','aa','bb')
  local a=assert(A._debug_report(d,raw(U.array({r1,r2})),{generated_at='2026-01-01T00:00:00Z'}))
  local b=assert(A._debug_report(d,raw(U.array({r2,r1})),{generated_at='2026-01-01T00:00:00Z'}))
  eq(a.findings[1].finding_id,b.findings[1].finding_id)
end)

local out=CESUITE_TEST_OUTPUT
if type(out)=='string' and out~='' then
  local d=with_change('validation_state','unique','no_match');d.comparability.source_changed=true
  local r=analyze(d)
  local f=assert(io.open(out..'/advisor-report.json','wb'));f:write(E.encode(r));f:close()
end
print(string.format('%d advisor tests passed (pure evidence rules)',tests))
