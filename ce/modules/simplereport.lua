-- Markdown rendering of the diagnostic assessment.
-- Presentation only: it never adds conclusions that are not in the assessment.
local U=require('util')
local M={}

local LIMITS={problem=50,advisory=12,not_assessed=10,healthy=20}

local function clean(value,limit)
  if type(value)=='number' then return tostring(value) end
  if type(value)~='string' then return '' end
  local s=value:gsub('[\r\n\t]+',' '):gsub('%s+',' ')
  s=s:gsub('`',"'"):gsub('<','&lt;'):gsub('>','&gt;')
  limit=limit or 400
  if #s>limit then s=s:sub(1,limit-3)..'...' end
  return s
end

local function code(value,limit)
  return '`'..clean(value,limit or 160)..'`'
end

local function bullets(lines,items,indent)
  if #items==0 then return end
  for _,item in ipairs(items) do
    lines[#lines+1]=(indent or '')..'- '..clean(item,400)
  end
end

local function bySeverity(diagnostics)
  local map={}
  for _,d in ipairs(diagnostics) do map[d.id]=d end
  return map
end

local function orderedByRepairPath(assessment,outcome)
  local map=bySeverity(assessment.diagnostics)
  local list={}
  for _,step in ipairs(assessment.repair_path) do
    local d=map[step.diagnostic_id]
    if d and d.outcome==outcome then list[#list+1]=d end
  end
  return list
end

local function renderDiagnostic(lines,d,index)
  lines[#lines+1]=string.format('### %d. %s',index,clean(d.label,160))
  lines[#lines+1]=''
  lines[#lines+1]=clean(d.summary,300)
  lines[#lines+1]=''
  lines[#lines+1]=string.format('Status: %s | Category: %s | Rule: %s | Confidence: %s',
    clean(d.status),clean(d.category),clean(d.rule),clean(d.confidence))
  lines[#lines+1]=''
  if #d.evidence>0 then
    lines[#lines+1]='**Evidence**'
    lines[#lines+1]=''
    local items={}
    for _,e in ipairs(d.evidence) do
      if type(e)=='table' and type(e.description)=='string' then items[#items+1]=e.description end
    end
    bullets(lines,items)
    lines[#lines+1]=''
  end
  if #d.confidence_reason>0 then
    lines[#lines+1]='**Why this confidence:** '..clean(table.concat(d.confidence_reason,' '),500)
    lines[#lines+1]=''
  end
  if #d.likely_causes>0 then
    lines[#lines+1]='**Possible causes (not proven)**'
    lines[#lines+1]=''
    bullets(lines,d.likely_causes)
    lines[#lines+1]=''
  end
  if #d.suggested_next_steps>0 then
    lines[#lines+1]='**Suggested next steps**'
    lines[#lines+1]=''
    for i,step in ipairs(d.suggested_next_steps) do
      lines[#lines+1]=string.format('%d. %s',i,clean(step,400))
    end
    lines[#lines+1]=''
  end
  if #d.do_not_assume>0 then
    lines[#lines+1]='**Do not assume**'
    lines[#lines+1]=''
    bullets(lines,d.do_not_assume)
    lines[#lines+1]=''
  end
  if #d.limitations>0 then
    lines[#lines+1]='**Limitations**'
    lines[#lines+1]=''
    bullets(lines,d.limitations)
    lines[#lines+1]=''
  end
end

function M.render(assessment,report)
  assert(type(assessment)=='table','simple report requires an assessment')
  report=report or {}
  local lines={}
  lines[#lines+1]='# CESuite Simple Report'
  lines[#lines+1]=''
  lines[#lines+1]='Generated: '..clean(assessment.generated_at,40)
  lines[#lines+1]=''
  lines[#lines+1]='Analysis mode: '..code(assessment.mode or 'unknown',40)
  local scope=assessment.scope or {}
  local target
  if scope.attached then
    target=(type(scope.process_name)=='string' and scope.process_name or 'attached process')..' (pid '..tostring(scope.pid)..')'
  else
    target='no process attached'
  end
  lines[#lines+1]=''
  lines[#lines+1]='Target: '..clean(target,200)
  lines[#lines+1]=''
  lines[#lines+1]='This report explains the evidence CESuite collected. It does not modify the table, the target or any script.'
  lines[#lines+1]=''
  lines[#lines+1]='## What CESuite analyzed'
  lines[#lines+1]=''
  lines[#lines+1]='- Modules enumerated: '..tostring(scope.module_count or 0)
  lines[#lines+1]='- Scripts inventoried: '..tostring(scope.script_count or 0)
  lines[#lines+1]='- AOB records: '..tostring(scope.aob_count or 0)
  lines[#lines+1]='- Dependency occurrences: '..tostring(scope.dependency_occurrence_count or 0)
  lines[#lines+1]='- Static Lua candidates: '..tostring(scope.static_candidate_count or 0)
  lines[#lines+1]=''
  lines[#lines+1]='**'..clean(assessment.headline,300)..'**'
  lines[#lines+1]=''

  local healthy={}
  for _,d in ipairs(assessment.diagnostics) do
    if d.outcome=='healthy' then healthy[#healthy+1]=d end
  end
  lines[#lines+1]='## What looks OK'
  lines[#lines+1]=''
  if #healthy==0 then
    lines[#lines+1]='No passing runtime checks were recorded in this collection.'
  else
    for i,d in ipairs(healthy) do
      if i>LIMITS.healthy then
        lines[#lines+1]=string.format('- ... and %d more passing check(s); see the extensive report.',#healthy-LIMITS.healthy)
        break
      end
      lines[#lines+1]='- '..clean(d.label,120)..': '..clean(d.summary,240)
    end
  end
  lines[#lines+1]=''

  local problems=orderedByRepairPath(assessment,'problem')
  lines[#lines+1]='## Problems'
  lines[#lines+1]=''
  if #problems==0 then
    lines[#lines+1]='No problems were detected in the evidence collected.'
  else
    for i,d in ipairs(problems) do
      if i>LIMITS.problem then
        lines[#lines+1]=string.format('_... and %d more problem(s); see the extensive report._',#problems-LIMITS.problem)
        lines[#lines+1]=''
        break
      end
      renderDiagnostic(lines,d,i)
    end
  end

  local advisories=orderedByRepairPath(assessment,'advisory')
  if #advisories>0 then
    lines[#lines+1]='## Source-only and advisory findings'
    lines[#lines+1]=''
    lines[#lines+1]='These findings come from lexical or static analysis. They are **not** runtime-verified.'
    lines[#lines+1]=''
    for i,d in ipairs(advisories) do
      if i>LIMITS.advisory then
        lines[#lines+1]=string.format('- ... and %d more advisory finding(s); see the extensive report.',#advisories-LIMITS.advisory)
        break
      end
      lines[#lines+1]='### '..clean(d.label,160)
      lines[#lines+1]=''
      lines[#lines+1]=clean(d.summary,300)
      lines[#lines+1]=''
      lines[#lines+1]=string.format('Status: %s | Confidence: %s | Rule: %s',
        clean(d.status),clean(d.confidence),clean(d.rule))
      lines[#lines+1]=''
      if #d.evidence>0 then
        local items={}
        for _,e in ipairs(d.evidence) do
          if type(e)=='table' and type(e.description)=='string' then items[#items+1]=e.description end
        end
        bullets(lines,items)
        lines[#lines+1]=''
      end
      if #d.suggested_next_steps>0 then
        lines[#lines+1]='**Suggested next steps**'
        lines[#lines+1]=''
        for k,step in ipairs(d.suggested_next_steps) do
          lines[#lines+1]=string.format('%d. %s',k,clean(step,400))
        end
        lines[#lines+1]=''
      end
      if #d.do_not_assume>0 then
        lines[#lines+1]='**Do not assume**'
        lines[#lines+1]=''
        bullets(lines,d.do_not_assume)
        lines[#lines+1]=''
      end
    end
    lines[#lines+1]=''
  end

  local notAssessed={}
  for _,d in ipairs(assessment.diagnostics) do
    if d.outcome=='not_assessed' then notAssessed[#notAssessed+1]=d end
  end
  if #notAssessed>0 then
    lines[#lines+1]='## Not assessed'
    lines[#lines+1]=''
    for i,d in ipairs(notAssessed) do
      if i>LIMITS.not_assessed then
        lines[#lines+1]=string.format('- ... and %d more item(s); see the extensive report.',#notAssessed-LIMITS.not_assessed)
        break
      end
      lines[#lines+1]='- '..clean(d.label,120)..': '..clean(d.summary,240)..' ('..clean(d.confidence)..' confidence)'
    end
    lines[#lines+1]=''
  end

  lines[#lines+1]='## Suggested Repair Path'
  lines[#lines+1]=''
  if #assessment.repair_path==0 then
    lines[#lines+1]='No repair step is suggested from the available evidence.'
  else
    lines[#lines+1]='Review in this order. Priority is fixed and does not depend on AI judgement.'
    lines[#lines+1]=''
    for _,step in ipairs(assessment.repair_path) do
      lines[#lines+1]=string.format('%d. %s',step.order,clean(step.action,300))
    end
  end
  lines[#lines+1]=''

  lines[#lines+1]='## How to read this report'
  lines[#lines+1]=''
  lines[#lines+1]='- `observed` means the status comes from a runtime observation recorded in this collection.'
  lines[#lines+1]='- `candidate` means lexical or static evidence only; runtime validity is not established.'
  lines[#lines+1]='- `unknown` means the evidence was insufficient or the operation could not be completed.'
  lines[#lines+1]='- `unsupported` means the construct is outside the analysis CESuite supports.'
  lines[#lines+1]='- Confidence levels: `high` (direct runtime evidence), `medium` (runtime evidence with a stated caveat), `low` (lexical/static inference), `unknown` (insufficient evidence).'
  lines[#lines+1]='- The extensive JSON report contains the same assessment with structured evidence.'
  lines[#lines+1]=''
  lines[#lines+1]='CESuite recommends what to review. It never changes the table, patches memory or generates hooks.'
  lines[#lines+1]=''
  return table.concat(lines,'\n')
end

-- Returns true on success, or nil plus a message. I/O errors are reported to the
-- caller (Core.exportReports returns a status table) instead of throwing.
function M.write(text,path)
  if type(text)~='string' then return nil,'simple report text required' end
  if type(path)~='string' or path=='' then return nil,'simple report path required' end
  local f,err=io.open(path,'wb')
  if not f then return nil,err or ('cannot open '..path) end
  local ok,failure=f:write(text)
  local closed,closeError=f:close()
  if not ok then return nil,failure or 'write failed' end
  if not closed then return nil,closeError or 'close failed' end
  return true
end

M.LIMITS=LIMITS
return M
