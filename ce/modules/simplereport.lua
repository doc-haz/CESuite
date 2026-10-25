-- Markdown rendering of the diagnostic assessment.
-- Presentation only: it never adds conclusions that are not in the assessment.
local U=require('util')
local M={}

local LIMITS={problem=50,advisory=12,not_assessed=10,healthy=20,candidate=10,unresolved=10}

local STATUS_LABELS = {
  ['complete'] = 'complete',
  ['partial'] = 'partial',
  ['unavailable'] = 'unavailable',
  ['unknown'] = 'unknown',
  ['not_applicable'] = 'not applicable',
  ['limit_reached'] = 'limit reached'
}

local function statusLabel(s)
  return STATUS_LABELS[s] or clean(s or 'unknown', 50)
end

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

local function renderCoverage(lines, cov, report)
  if not cov or type(cov) ~= 'table' then return end

  lines[#lines+1] = '## Coverage Summary'
  lines[#lines+1] = ''

  -- 1. Collection
  local coll = cov.collection or {}
  local collStatus = statusLabel(coll.status)
  local collUnits = string.format('%d / %d', coll.units_processed or 0, coll.units_discovered or 0)
  local collPct = (type(coll.percentage) == 'number') and string.format(' (%.1f%%)', coll.percentage) or ''
  lines[#lines+1] = '### Collection'
  lines[#lines+1] = '- Status: ' .. collStatus .. collPct
  lines[#lines+1] = '- Processed: ' .. collUnits
  if coll.status == 'limit_reached' then
    lines[#lines+1] = '- Warning: Analysis limit reached; collection may be incomplete.'
  end
  lines[#lines+1] = ''

  -- 2. Discovery
  local disc = cov.discovery or {}
  local discStatus = statusLabel(disc.status)
  local discPct = (type(disc.percentage) == 'number') and string.format(' (%.1f%%)', disc.percentage) or ''
  local discCand = disc.candidates or 0
  local discEnt = disc.entities_discovered or 0
  lines[#lines+1] = '### Discovery'
  lines[#lines+1] = '- Status: ' .. discStatus .. discPct
  lines[#lines+1] = string.format('- Candidates: %d from %d entities (%d linked)',
    discCand, discEnt, disc.linked or 0)
  if disc.patterns_discovered and disc.patterns_discovered > 0 then
    lines[#lines+1] = string.format('- Patterns: %d literal, %d derived, %d conditional, %d symbol-only',
      disc.patterns_literal or 0, disc.patterns_derived or 0,
      disc.patterns_conditional or 0, disc.patterns_symbol_only or 0)
  end
  if disc.universe_known == false then
    lines[#lines+1] = '- Note: Discovery universe is not fully known; some candidate sources remain unresolved.'
  end
  lines[#lines+1] = ''

  -- 3. Validation
  local val = cov.validation or {}
  local valStatus = statusLabel(val.status)
  local valPct = (type(val.percentage) == 'number') and string.format(' (%.1f%%)', val.percentage) or ''
  lines[#lines+1] = '### Validation'
  lines[#lines+1] = '- Status: ' .. valStatus .. valPct
  lines[#lines+1] = string.format('- Attempted: %d of %d candidate(s)', val.runtime_attempted or 0, val.candidates or 0)
  lines[#lines+1] = string.format('- Validated: %d', val.runtime_validated or 0)

  local isAttached = report and report.target and report.target.attached
  if not isAttached then
    lines[#lines+1] = '- Note: Static source analysis completed; runtime validation was unavailable because no live target was attached.'
  elseif (val.candidates or 0) == 0 then
    lines[#lines+1] = '- Note: No signature candidates discovered; runtime validation is not applicable.'
  end
  lines[#lines+1] = ''
end

local function renderDynamicAnalysis(lines, dyn, report)
  if not dyn or type(dyn) ~= 'table' then return end

  local aobBySymbol = {}
  if report and report.aobs then
    for _, a in ipairs(report.aobs) do
      if a.symbol then aobBySymbol[a.symbol] = a end
    end
  end
  local isAttached = report and report.target and report.target.attached

  local patterns = dyn.patterns or {}
  local unresolved = dyn.unresolved or {}
  local edges = dyn.edges or {}
  local providers = dyn.providers or {}

  if #patterns == 0 and #unresolved == 0 and #edges == 0 and #providers == 0 then
    return
  end

  lines[#lines+1] = '## Dynamic Analysis & Provenance'
  lines[#lines+1] = ''

  local candidates = {}
  for _, p in ipairs(patterns) do
    if p.status == 'candidate' then candidates[#candidates+1] = p end
  end
  local displayPatterns = (#candidates > 0) and candidates or patterns

  if #displayPatterns > 0 then
    lines[#lines+1] = '### Discovered Candidates'
    local count = #displayPatterns
    if count > LIMITS.candidate then
      lines[#lines+1] = string.format('Showing top %d of %d candidate(s); full details in extensive report.', LIMITS.candidate, count)
    else
      lines[#lines+1] = string.format('%d candidate(s) discovered in source:', count)
    end
    lines[#lines+1] = ''

    for i = 1, math.min(count, LIMITS.candidate) do
      local p = displayPatterns[i]
      local name = clean(p.symbol or p.id or ('candidate-' .. i), 80)
      local loc = clean((p.source_script or 'source') .. ':' .. tostring(p.source_line or '?'), 60)
      lines[#lines+1] = string.format('#### Candidate: %s', name)
      lines[#lines+1] = ''
      lines[#lines+1] = '- Kind: ' .. clean(p.kind or 'unknown', 50)
      lines[#lines+1] = '- Source: ' .. loc
      if p.consumer then lines[#lines+1] = '- Consumer: ' .. clean(p.consumer, 100) end
      lines[#lines+1] = '- Status: ' .. clean(p.status or 'candidate', 50)

      local valState = 'not attempted'
      if not isAttached then
        valState = 'unavailable (target not attached)'
      elseif p.symbol and aobBySymbol[p.symbol] then
        local a = aobBySymbol[p.symbol]
        if a.uniqueness == 'unique' then
          valState = 'validated (unique)'
        elseif a.uniqueness == 'ambiguous' then
          valState = 'ambiguous'
        elseif a.uniqueness == 'no_match' then
          valState = 'no match'
        elseif a.status == 'error' then
          valState = 'error'
        elseif a.status == 'invalidated' then
          valState = 'unavailable'
        else
          valState = clean(a.uniqueness or a.status or 'not attempted', 50)
        end
      end
      lines[#lines+1] = '- Runtime validation: ' .. valState

      if p.kind == 'derived_pattern' then
        local helper = p.source_helper or 'helper'
        local hloc = p.helper_file and (p.helper_file .. ':' .. tostring(p.helper_line or '?')) or 'external'
        lines[#lines+1] = string.format('- Derived from helper: %s (%s)', clean(helper, 80), clean(hloc, 80))
        lines[#lines+1] = '- Derivation status: ' .. (p.status == 'unresolved' and 'unresolved' or 'resolved from helper')
      end

      if p.kind == 'conditional_pattern' or p.condition then
        local cond = p.condition or {}
        lines[#lines+1] = '- Condition resolution: ' .. clean(cond.resolution or 'unknown', 50)
        if cond.dependencies and #cond.dependencies > 0 then
          lines[#lines+1] = '- Condition dependency: ' .. clean(table.concat(cond.dependencies, ', '), 100)
        end
        if cond.fallback then
          lines[#lines+1] = '- Condition fallback: ' .. clean(cond.fallback, 80)
        end
      end

      if p.provenance and #p.provenance > 0 then
        lines[#lines+1] = '- Provenance:'
        for _, pr in ipairs(p.provenance) do
          local pdesc = pr.kind or 'unknown'
          if pr.detail then pdesc = pdesc .. ' (' .. clean(pr.detail, 60) .. ')' end
          lines[#lines+1] = '  - ' .. pdesc
        end
      end

      lines[#lines+1] = ''
    end

    if count > LIMITS.candidate then
      lines[#lines+1] = string.format('- ... and %d more candidate(s); see the extensive report.', count - LIMITS.candidate)
      lines[#lines+1] = ''
    end
  end

  if #unresolved > 0 then
    lines[#lines+1] = '### Unresolved Dependencies'
    lines[#lines+1] = ''
    for i = 1, math.min(#unresolved, LIMITS.unresolved) do
      local u = unresolved[i]
      local name = clean(u.name or u.id or 'unresolved', 80)
      local loc = clean((u.source_script or 'source') .. ':' .. tostring(u.source_line or '?'), 60)
      local reason = u.reason and (' — ' .. clean(u.reason, 100)) or ''
      lines[#lines+1] = string.format('- %s (%s%s)', name, loc, reason)
    end
    if #unresolved > LIMITS.unresolved then
      lines[#lines+1] = string.format('- ... and %d more unresolved dependenc(ies); see the extensive report.', #unresolved - LIMITS.unresolved)
    end
    lines[#lines+1] = ''
  end

  if #edges > 0 then
    lines[#lines+1] = '### Provenance Relationships'
    lines[#lines+1] = ''
    local relCounts = {}
    local relOrder = {'defines', 'passes_to', 'calls', 'constructs', 'provides', 'requires', 'consumes', 'derives_from', 'registers'}
    for _, e in ipairs(edges) do
      local rel = e.relation or 'other'
      relCounts[rel] = (relCounts[rel] or 0) + 1
    end
    for _, rel in ipairs(relOrder) do
      if relCounts[rel] then
        lines[#lines+1] = string.format('- %s: %d', rel, relCounts[rel])
      end
    end
    for rel, cnt in pairs(relCounts) do
      local found = false
      for _, r in ipairs(relOrder) do if r == rel then found = true; break end end
      if not found then
        lines[#lines+1] = string.format('- %s: %d', rel, cnt)
      end
    end
    lines[#lines+1] = ''
  end

  lines[#lines+1] = '### Providers & Consumers'
  if #providers > 0 then
    lines[#lines+1] = '- Providers: ' .. clean(table.concat(providers, ', '), 200)
  else
    lines[#lines+1] = '- Providers: unknown'
  end

  local consumers = {}
  local cseen = {}
  for _, p in ipairs(patterns) do
    if p.consumer and not cseen[p.consumer] then
      cseen[p.consumer] = true
      consumers[#consumers+1] = p.consumer
    end
  end
  if #consumers > 0 then
    lines[#lines+1] = '- Consumers: ' .. clean(table.concat(consumers, ', '), 200)
  else
    lines[#lines+1] = '- Consumers: unknown'
  end
  lines[#lines+1] = ''

  if dyn.status == 'limit_reached' or (dyn.limits and (dyn.limits.table_limit_hit or dyn.limits.candidate_limit_hit or dyn.limits.edge_limit_hit or dyn.limits.token_limit_hit)) then
    lines[#lines+1] = '### Analysis Limitations'
    lines[#lines+1] = ''
    lines[#lines+1] = 'Analysis limit reached. Results may be incomplete.'
    if dyn.limits then
      if dyn.limits.table_limit_hit then
        lines[#lines+1] = '- Table entries exceeded configured maximum: TABLE_LIMIT reached.'
      end
      if dyn.limits.candidate_limit_hit then
        lines[#lines+1] = '- Candidates exceeded configured maximum: CANDIDATE_LIMIT reached.'
      end
      if dyn.limits.edge_limit_hit then
        lines[#lines+1] = '- Provenance edges exceeded configured maximum: EDGE_LIMIT reached.'
      end
      if dyn.limits.token_limit_hit then
        lines[#lines+1] = '- Source tokens exceeded configured maximum: PARSE_LIMIT reached.'
      end
    end
    lines[#lines+1] = ''
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

  local cov=(report and report.coverage) or (report and report.static_lua_analysis and report.static_lua_analysis.coverage)
  if cov then
    renderCoverage(lines,cov,report)
  end

  local dyn=(report and report.dynamic_analysis) or (report and report.static_lua_analysis and report.static_lua_analysis.dynamic_analysis)
  if dyn then
    renderDynamicAnalysis(lines,dyn,report)
  end

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
