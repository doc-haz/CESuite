-- Advisor UI: presentation only. Never evaluates rules or changes evidence.
local U=require('util')
local M={}
M.VERSION=1
M.MAX_VALUE_LENGTH=512

local STEP_TEXT={
  REVIEW_EVIDENCE='Review the cited evidence.',
  CAPTURE_NEW_SNAPSHOT='Capture a new snapshot when the evidence context changes.',
  COMPARE_TARGET_BUILD='Compare target build metadata.',
  INCREASE_COVERAGE='Increase source coverage if the current evidence is incomplete.',
  VALIDATE_CANDIDATE='Validate the candidate against the observed target.',
  REVIEW_PROVENANCE='Review the candidate provenance.',
  REVIEW_DEPENDENCIES='Review the dependency evidence.',
  RUN_ADDRESS_EVIDENCE='Run Address Evidence for a specific address if needed.',
  REQUEST_RELOCATION_CANDIDATES='A future relocation analysis may be useful.'
}

local function str(v)
  if v==nil or v==U.null then return 'null' end
  return tostring(v)
end
local function clean(v)
  local s=str(v):gsub('\r\n',' '):gsub('[\r\n]',' ')
  s=s:gsub('[%z\1-\8\11\12\14-\31\127]','?')
  if #s>M.MAX_VALUE_LENGTH then s=s:sub(1,M.MAX_VALUE_LENGTH)..' [clipped]' end
  return s
end
local function list(values,empty)
  local out={}
  for _,v in ipairs(values or {}) do out[#out+1]='- '..clean(v) end
  if #out==0 then out[#out+1]='- '..(empty or 'None recorded.') end
  return table.concat(out,'\n')
end
local function refs(values)
  local out={}
  for _,r in ipairs(values or {}) do
    out[#out+1]='- '..clean(r.source)..' / '..clean(r.entity)..
      ' / '..clean(r.id)..' / '..clean(r.field)..' = '..clean(r.value)
  end
  if #out==0 then out[#out+1]='- None recorded.' end
  return table.concat(out,'\n')
end
local function stepText(step)
  local id=step.action or ''
  return '- `'..clean(id)..'` — '..(STEP_TEXT[id] or 'Review this recommendation; no automatic action is available.')
end

function M.nextStepText(action)
  return STEP_TEXT[action] or 'Review this recommendation; no automatic action is available.'
end

function M.render(report)
  assert(type(report)=='table','Advisor report required')
  assert(report.advisor_version==1,'Unsupported Advisor report')
  local lines={}
  local function add(s) lines[#lines+1]=s end
  local function addList(header,values,empty)
    add('**'..header..'**')
    add(list(values,empty))
    add('')
  end

  add('# Evidence Advisor Report')
  add('')
  if report.truncated then
    add('> This Advisor report was truncated by configured bounds.')
    add('')
  end
  if report.input and report.input.comparability=='partial_comparison' then
    add('> Only evidence with strong identity was compared.')
    add('')
  end
  if report.input and report.input.comparability=='not_comparable' then
    add('> Candidate-level causal interpretation is unavailable.')
    add('')
  end

  add('## Overview')
  add('')
  add('- Advisor version: '..clean(report.advisor_version))
  add('- Ruleset version: '..clean(report.ruleset_version))
  add('- Advisor report ID: '..clean(report.advisor_report_id))
  add('- Input type: '..clean(report.input and report.input.type))
  add('- Input ID: '..clean(report.input and report.input.input_id))
  add('- Comparability: '..clean(report.input and report.input.comparability))
  add('- Finding count: '..clean(report.summary and report.summary.finding_count or 0))
  add('- Truncated: '..(report.truncated and 'yes' or 'no'))
  add('')

  add('## Findings')
  add('')
  if not report.findings or #report.findings==0 then
    add('No meaningful changes were identified by the current ruleset.')
    add('')
    local lim=report.limitations or {}
    if #lim>0 then addList('Limitations',lim) end
    return table.concat(lines,'\n')
  end

  for i,f in ipairs(report.findings) do
    add('### '..i..'. '..clean(f.code))
    add('')
    add('- Category: '..clean(f.category))
    add('- Severity: '..clean(f.severity))
    add('- Confidence: '..clean(f.confidence))
    add('- Status: '..clean(f.status))
    add('')
    add('**Observed Evidence**')
    add(list(f.observations))
    add('')
    add('**Evidence References**')
    add(refs(f.evidence_refs))
    add('')
    add('**Interpretation**')
    add('')
    add(clean(f.interpretation))
    add('')
    add('**Possible causes**')
    add(list(f.likely_causes))
    add('')
    add('**Suggested Next Steps**')
    local steps={}
    for _,s in ipairs(f.suggested_next_steps or {}) do steps[#steps+1]=stepText(s) end
    if #steps==0 then steps[#steps+1]='- Review this finding; no automatic action is available.' end
    add(table.concat(steps,'\n'))
    add('')
    add('**Do Not Assume**')
    add(list(f.do_not_assume))
    add('')
    add('**Limitations**')
    add(list(f.limitations))
    add('')
    if f.rule_metadata then
      add('Rule: '..clean(f.rule_metadata.rule_id)..
        '  |  Precedence: '..clean(f.rule_metadata.precedence)..
        '  |  Ruleset: '..clean(report.ruleset_version))
      add('')
    end
  end
  add('## Limitations')
  add('')
  add(list(report.limitations))
  add('')
  return table.concat(lines,'\n')
end

function M.renderError(error,errors)
  local lines={'# Advisor report unavailable',''}
  lines[#lines+1]='The Advisor report was not rendered because validation did not complete.'
  lines[#lines+1]=''
  lines[#lines+1]='**Reason**'
  lines[#lines+1]=''
  lines[#lines+1]='- '..clean(type(error)=='table' and (error.code or error.message) or error)
  for _,e in ipairs(errors or {}) do
    lines[#lines+1]='- '..clean(e.code)..': '..clean(e.path)..' — '..clean(e.message)
  end
  lines[#lines+1]=''
  return table.concat(lines,'\n')
end

return M
