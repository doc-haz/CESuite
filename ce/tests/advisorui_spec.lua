package.path='ce/modules/?.lua;'..package.path
local UI=require('advisorui')
local U=require('util')

local tests=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function arr(...) return U.array({...}) end
local function report(opts)
  opts=opts or {}
  return {
    advisor_version=1,advisor_report_id='adv-0123456789abcdef0123456789abcdef',
    ruleset_version=1,suite_version='0.3.2',generated_at='2026-01-01T00:00:00Z',
    truncated=opts.truncated or false,
    truncation={findings_capped=opts.truncated or false,fields_capped=false,limitations_capped=false},
    input={type='snapshot_diff',input_id='a:b',snapshot_a='a',snapshot_b='b',
      comparability=opts.comparability or 'comparable'},
    findings=opts.findings or arr({
      finding_id='advf-0123456789abcdef0123456789abcdef',rule_id='PATTERN_CHANGED',
      code='PATTERN_CHANGED',category='pattern_change',severity='MEDIUM',confidence='exact',
      status='observed',precedence=4,truncated=false,
      rule_metadata={rule_id='PATTERN_CHANGED',category='pattern_change',severity='MEDIUM',
        default_confidence='exact',precedence=4,required_evidence=arr({'candidate.pattern'})},
      evidence_refs=arr({source='snapshot_a',entity='candidate',id='c1',field='pattern',value='aa'}),
      observations=arr('A.pattern = aa','B.pattern = bb'),
      interpretation='The observed pattern differs between snapshots.',
      likely_causes=arr('The source pattern was edited.'),
      suggested_next_steps=arr({action='VALIDATE_CANDIDATE',detail='Validate it.'}),
      do_not_assume=arr('Do not assume the new pattern is equivalent.'),
      limitations=arr('Limited to captured evidence.')
    }),
    limitations=opts.limitations or arr('Captured evidence only.'),
    summary={finding_count=opts.count or 1,by_severity={INFO=0,LOW=0,MEDIUM=1,HIGH=0,CRITICAL=0},
      by_category=arr({category='pattern_change',count=1}),headline='1 finding.'}
  }
end

test('render includes all required sections',function()
  local t=UI.render(report())
  for _,s in ipairs({'# Evidence Advisor Report','## Overview','## Findings',
    '**Observed Evidence**','**Evidence References**','**Interpretation**',
    '**Possible causes**','**Suggested Next Steps**','**Do Not Assume**','**Limitations**',
    'Rule: PATTERN_CHANGED'}) do
    assert(t:find(s,1,true),s)
  end
  assert(not t:find('table: 0',1,true),t)
end)

test('partial comparison is visibly partial',function()
  local t=UI.render(report({comparability='partial_comparison'}))
  assert(t:find('Only evidence with strong identity was compared.',1,true))
end)

test('not comparable is visibly unavailable',function()
  local t=UI.render(report({comparability='not_comparable'}))
  assert(t:find('Candidate-level causal interpretation is unavailable.',1,true))
end)

test('truncated report is announced at the top',function()
  local t=UI.render(report({truncated=true}))
  assert(t:find('This Advisor report was truncated by configured bounds.',1,true))
  assert(t:find('Truncated: yes',1,true))
end)

test('empty findings are neutral',function()
  local r=report({findings=U.array(),count=0})
  local t=UI.render(r)
  assert(t:find('No meaningful changes were identified by the current ruleset.',1,true))
  assert(not t:find('working',1,true))
end)

test('next-step IDs are translated, relocation is text-only',function()
  local r=report()
  r.findings[1].suggested_next_steps=arr(
    {action='VALIDATE_CANDIDATE',detail='Validate it.'},
    {action='REQUEST_RELOCATION_CANDIDATES',detail='Future.'})
  local t=UI.render(r)
  assert(t:find('Validate the candidate against the observed target.',1,true))
  assert(t:find('A future relocation analysis may be useful.',1,true))
  assert(not t:find('Find replacement',1,true))
  assert(not t:find('Apply',1,true))
end)

test('evidence text is inert and bounded',function()
  local r=report()
  r.findings[1].observations=arr('markdown **not bold** \\1 <script>', string.rep('x',900))
  local t=UI.render(r)
  assert(not t:find('table:',1,true))
  assert(t:find('markdown',1,true))
  assert(t:find('[clipped]',1,true))
end)

test('render error is controlled and structured',function()
  local t=UI.renderError({code='advisor_unavailable'},{{code='MALFORMED_ID',path='x',message='bad'}})
  assert(t:find('Advisor report unavailable',1,true))
  assert(t:find('MALFORMED_ID',1,true))
end)

test('null evidence values render literally',function()
  local r=report()
  r.findings[1].evidence_refs[1].id=U.null
  r.findings[1].evidence_refs[1].value=U.null
  local t=UI.render(r)
  assert(t:find('null',1,true))
  assert(not t:find('table: 0',1,true))
end)

print(string.format('%d advisor UI tests passed (pure presentation)',tests))
