package.path='ce/modules/?.lua;'..package.path
local S=require('snapshot')
local UI=require('snapshotui')
local E=require('exporter')
local U=require('util')
local tests=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(a,b,label) assert(a==b,(label or 'value')..': expected '..tostring(b)..' got '..tostring(a)) end
local function load(name)
  local f=assert(io.open('ce/tests/fixtures/corpus/snapshots/'..name..'.json','rb'))
  local text=f:read('*a');f:close()
  local s,err=S.decode(text)
  assert(s,err and (err.code..': '..tostring(err.message)))
  return s
end
local function pair(name) return load(name..'-a'),load(name..'-b') end

test('all snapshot fixtures decode and validate',function()
  local count=0
  for _,name in ipairs({'identical-a','identical-b','candidate-added-a','candidate-added-b',
    'candidate-removed-a','candidate-removed-b','pattern-changed-a','pattern-changed-b',
    'validation-changed-a','validation-changed-b','provider-changed-a','provider-changed-b',
    'different-source-a','different-source-b','different-target-a','different-target-b',
    'different-build-a','different-build-b','unknown-build-a','unknown-build-b',
    'coverage-changed-a','coverage-changed-b','limit-reached','privacy-sanitized','ffrs-reference'}) do
    assert(load(name));count=count+1
  end
  eq(count,25)
end)

test('identical snapshots are comparable and unchanged',function()
  local a,b=pair('identical')
  eq(a.snapshot_id,b.snapshot_id)
  local d=S.compare(a,b)
  eq(d.comparability.status,'comparable')
  eq(d.candidates.unchanged,1)
end)

test('candidate added and removed are neutral classifications',function()
  local a,b=pair('candidate-added')
  local d=S.compare(a,b);eq(#d.candidates.added,1);eq(#d.candidates.changed,0)
  local c,e=pair('candidate-removed')
  local r=S.compare(c,e);eq(#r.candidates.removed,1);eq(#r.candidates.added,0)
end)

test('pattern and validation changes are field-level evidence',function()
  local a,b=pair('pattern-changed')
  local d=S.compare(a,b)
  eq(d.comparability.status,'comparable')
  eq(d.candidates.changed[1].changed.pattern,true)
  local c,e=pair('validation-changed')
  local r=S.compare(c,e)
  eq(r.candidates.changed[1].changed.validation_state,true)
  eq(r.coverage.validation.changed,true)
end)

test('provider change is visible without a verdict',function()
  local a,b=pair('provider-changed')
  local d=S.compare(a,b)
  eq(d.candidates.changed[1].changed.provider,true)
  local text=E.encode(d):lower()
  for _,word in ipairs({'fixed','broken','regressed','compatible','incompatible','working'}) do
    eq(text:find(word,1,true),nil,'forbidden word '..word)
  end
end)

test('different source is partial with strong identities only',function()
  local a,b=pair('different-source')
  local d=S.compare(a,b)
  eq(d.comparability.status,'partial_comparison')
  eq(d.comparability.source_changed,true)
  eq(d.comparability.same_source,false)
  eq(d.comparability.candidate_comparable,true)
  eq(d.comparability.strong_identity_only,true)
  local text=UI.renderDiff(d)
  assert(text:find('Partial comparison',1,true))
  assert(text:find('Strong identities only',1,true))
end)

test('different target and known build states are distinct',function()
  local a,b=pair('different-target')
  eq(S.compare(a,b).comparability.status,'different_target')
  local c,d=pair('different-build')
  local r=S.compare(c,d)
  eq(r.comparability.different_target_build,true)
  eq(r.comparability.target_build_unknown,false)
  local e,f=pair('unknown-build')
  local u=S.compare(e,f)
  eq(u.comparability.target_build_unknown,true)
  eq(u.comparability.different_target_build,false)
end)

test('coverage and limit fixtures preserve observed states',function()
  local a,b=pair('coverage-changed')
  local d=S.compare(a,b)
  eq(d.coverage.discovery.changed,true)
  eq(d.coverage.collection.changed,false)
  local limit=load('limit-reached')
  eq(limit.coverage.collection.status,'limit_reached')
  eq(limit.coverage.collection.percentage,U.null)
end)

test('privacy fixture is sanitized and records redactions',function()
  local s=load('privacy-sanitized')
  assert(#s.redactions>0)
  eq(E.encode(s):find('Users',1,true),nil)
  eq(E.encode(s):find('C:\\\\',1,true),nil)
  eq(s.candidates[1].provider,'UE.lua')
  eq(s.candidates[1].helper,'UE.Sig.X')
end)

test('FFRS fixture preserves known evidence without runtime validation',function()
  local s=load('ffrs-reference')
  eq(#s.candidates,31)
  eq(s.source.record_count,47)
  eq(s.coverage.discovery.entities_discovered,52)
  eq(s.coverage.discovery.candidates,31)
  eq(s.coverage.validation.validated,0)
  eq(s.coverage.validation.status,'unavailable')
  local found=false
  for _,u in ipairs(s.unresolved) do if u.name=='LaunchUEInfoScanner' then found=true end end
  eq(found,true)
end)

test('viewer render is sectioned and does not expose raw JSON as primary UX',function()
  local s=load('ffrs-reference')
  local text=UI.render(s)
  for _,section in ipairs({'Overview','Target','Source','Coverage','Candidates','Validation','Provenance','Dependencies','Unresolved','Limitations','Modules','Address Evidence'}) do
    assert(text:find('## '..section,1,true),'missing section '..section)
  end
  eq(text:sub(1,1),'#')
  assert(not text:find('{"snapshot_version"',1,true))
  eq(text:find('"candidates":',1,true),nil)
  assert(text:find('showing up to 50',1,true))
end)

test('viewer diff renders comparability header and groups',function()
  local a,b=pair('pattern-changed')
  local text=UI.renderDiff(S.compare(a,b))
  for _,word in ipairs({'Comparable','Changed','Added','Removed','Unknown'}) do
    assert(text:find(word,1,true),'missing '..word)
  end
end)

print(string.format('%d snapshot corpus/UI tests passed',tests))
