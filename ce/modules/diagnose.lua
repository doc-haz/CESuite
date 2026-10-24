-- Diagnostic model: interprets evidence that already exists in a runtime report.
-- Never scans, executes inspected code, edits tables or invents evidence.
-- A diagnostic is a conservative statement about the collected evidence only.
local U=require('util')
local M={}

-- Repair-path priority. Lower runs first. Order documented in docs/reporting.md.
-- AOB scans that could not complete rank above dependency/static review because
-- they block trust in the AOB evidence itself.
local RULE_PRIORITY={
  ['PROCESS-NOT-ATTACHED']=1,
  ['PROCESS-CHANGED']=1,
  ['MODULES-UNAVAILABLE']=2,
  ['MODULE-AMBIGUOUS']=2,
  ['AOB-NO-MATCH']=3,
  ['AOB-AMBIGUOUS']=4,
  ['AOB-SCOPE-UNRESOLVED']=5,
  ['AOB-SCAN-ERROR']=5,
  ['AOB-SCAN-UNAVAILABLE']=5,
  ['AOB-INVALIDATED']=5,
  ['AOB-UNSUPPORTED']=5,
  ['DEPENDENCY-UNRESOLVED-PROVIDER']=6,
  ['STATIC-CANDIDATE-ONLY']=7,
  ['STATIC-UNRESOLVED']=7,
  ['EVIDENCE-INSUFFICIENT']=9
}
local DEFAULT_PRIORITY=8

local SEVERITY_RANK={high=1,medium=2,low=3,info=4}

-- Review diagnostics that indicate degraded evidence, not just style advice.
local REVIEW_SEVERITY={
  ['SCAN-ERROR-VISIBILITY']='medium',
  ['MODULE-SNAPSHOT-INCOMPLETE']='medium',
  ['ACTIVE-RECORD']='medium',
  ['PROCESS-CHANGED']='high',
  ['PROCESS-UNAVAILABLE']='high',
  ['MODULES-UNAVAILABLE']='high',
  ['TABLE-LUA-UNAVAILABLE']='low',
  ['CT-UNAVAILABLE']='medium'
}

local function arr(t) return U.array(t or {}) end
local function str(v) return type(v)=='string' and v or nil end
local function num(v) return type(v)=='number' and v or nil end

local function newDiag(fields)
  return {
    id=fields.id,
    rule=fields.rule,
    category=fields.category,
    severity=fields.severity,
    status=fields.status,
    outcome=fields.outcome,
    label=fields.label or fields.rule,
    summary=fields.summary,
    evidence=arr(fields.evidence),
    confidence=fields.confidence,
    confidence_reason=arr(fields.confidence_reason),
    likely_causes=arr(fields.likely_causes),
    suggested_next_steps=arr(fields.suggested_next_steps),
    limitations=arr(fields.limitations),
    do_not_assume=arr(fields.do_not_assume),
    source=fields.source or 'runtime'
  }
end

local function aobLabel(a)
  local symbol=str(a.symbol)
  if symbol and symbol~='' then return 'AOB "'..symbol..'"' end
  local id=str(a.id)
  return id and ('AOB '..id) or 'AOB'
end

local function aobEvidence(a)
  local e={kind='runtime_aob', script_id=str(a.script_id) or U.null,
    line=num(a.line) or U.null, section=str(a.section) or U.null,
    command=str(a.command) or U.null, scope=str(a.scope) or U.null,
    pattern=str(a.pattern) or U.null, match_count=num(a.match_count) or U.null,
    uniqueness=str(a.uniqueness) or U.null, status=str(a.status) or U.null,
    description=''}
  if type(a.message)=='string' then e.message=a.message end
  if type(a.scan)=='table' then
    e.scan_start=str(a.scan.start) or U.null
    e.scan_stop=str(a.scan.stop) or U.null
    e.error_visibility=str(a.scan.error_visibility) or U.null
  end
  return e
end

local function scanScopeText(a)
  local scope=str(a.scope) or 'unknown'
  local module=str(a.arguments and a.arguments[2])
  if scope=='module' and module then return 'module '..module end
  if scope=='process' then return 'the whole readable address space' end
  return scope..' scope'
end

-- AOB diagnostics -----------------------------------------------------------
local function observedConfidence(a)
  local visibility=type(a.scan)=='table' and a.scan.error_visibility or nil
  if a.uniqueness=='unverified' or visibility=='unavailable' then
    return 'medium',{'Runtime count was read, but Cheat Engine did not expose scan error detail; uniqueness stays unverified.'}
  end
  return 'high',{'Direct runtime scan in this collection; match count reported by Cheat Engine.'}
end

local function aobDiagnostics(report, out)
  local aobs=report.aobs or {}
  local unavailable,invalidated=0,0
  for _,a in ipairs(aobs) do
    local status=str(a.status) or 'not_scanned'
    local label=aobLabel(a)
    local evidence=aobEvidence(a)
    local pattern=str(a.pattern)
    evidence.description=string.format('%s over %s%s',label,scanScopeText(a),pattern and (' with pattern "'..pattern..'"') or '')
    if status=='observed' then
      local count=num(a.match_count) or 0
      local confidence,reasons=observedConfidence(a)
      if count==0 then
        evidence.description=string.format('%s over %s returned zero matches.',label,scanScopeText(a))
        local d=newDiag({id='aob:'..tostring(a.id),rule='AOB-NO-MATCH',category='aob',
          severity='high',status='observed',outcome='problem',label=label,
          summary='AOB signature was not found in the scanned range.',
          evidence={evidence},confidence=confidence,confidence_reason=reasons,
          likely_causes={'The target executable or build differs from the one this signature was made for.',
            'The intended module is not loaded, was replaced, or has a different version.',
            'The bytes around the target instruction changed in an update.','The signature scope points at the wrong module.'},
          suggested_next_steps={'Verify the attached process and executable build are the ones this table expects.',
            'Confirm the intended module is loaded and is the expected version.',
            'Compare the signature against the current build and look for changed bytes near the original instruction.',
            'If the build changed, identify the new instruction location manually before editing anything.'},
          limitations={'Only Cheat Engine-readable memory inside the scanned range was checked.','A scan is a snapshot; the target keeps running.'},
          do_not_assume={'A missing signature does not prove the underlying feature was removed.','A missing signature does not identify the correct replacement bytes.'}})
        d.source='runtime'
        out[#out+1]=d
      elseif count==1 then
        evidence.description=string.format('%s over %s matched exactly once.',label,scanScopeText(a))
        out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-UNIQUE',category='aob',
          severity='info',status='observed',outcome='healthy',label=label,
          summary='AOB signature matched exactly once in the scanned range.',
          evidence={evidence},confidence=confidence,confidence_reason=reasons,
          limitations={'Uniqueness applies to this scan only; it does not prove other builds behave the same.'}})
      else
        evidence.description=string.format('%s over %s matched %d times.',label,scanScopeText(a),count)
        out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-AMBIGUOUS',category='aob',
          severity='medium',status='observed',outcome='problem',label=label,
          summary='AOB signature matched more than one location in the scanned range.',
          evidence={evidence},confidence=confidence,confidence_reason=reasons,
          likely_causes={'The pattern is too short to be unique in this build.','Several copies of the same code exist (templates, inlined variants, multiple modules).',
            'The scan scope is broader than intended.'},
          suggested_next_steps={'Inspect the neighbouring bytes of each reported match.','Extend the pattern with bytes that are specific to the intended instruction.',
            'Verify the intended module and instruction context before choosing a match.','Re-run Validate AOBs after narrowing the pattern.'},
          limitations={'Only the first 256 addresses are exported; later matches may differ.'},
          do_not_assume={'Multiple matches do not identify which one is the correct target.','A longer pattern is not automatically a safe pattern.'}})
      end
    elseif status=='not_scanned' then
      evidence.description=string.format('%s was inventoried from the table but never scanned.',label)
      out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-NOT-SCANNED',category='aob',
        severity='low',status='unknown',outcome='not_assessed',label=label,
        summary='Signature was detected in the table only; runtime validity has not been established.',
        evidence={evidence},confidence='unknown',confidence_reason={'No runtime scan was performed for this signature in this collection.'},
        suggested_next_steps={'Run Validate AOBs with the intended process attached.','Confirm the table is the one loaded in the target session.'},
        do_not_assume={'Detected in source only. Runtime validity has not been established.'},source='runtime'})
    elseif status=='unsupported' then
      evidence.description=string.format('%s is outside supported scan syntax.',label)
      out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-UNSUPPORTED',category='aob',
        severity='low',status='unsupported',outcome='not_assessed',label=label,
        summary='Signature or scope is outside the scan syntax CESuite supports, so no runtime evidence exists.',
        evidence={evidence},confidence='unknown',confidence_reason={'The pattern or argument count could not be scanned as written.'},
        suggested_next_steps={'Use a literal byte/nibble wildcard pattern with the expected argument count.','Review the pattern manually; CESuite will not widen the scan.'},
        limitations={'CESuite does not translate or repair patterns.'},source='runtime'})
    elseif status=='unresolved' then
      evidence.description=string.format('%s could not be resolved to a scan range.',label)
      out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-SCOPE-UNRESOLVED',category='aob',
        severity='medium',status='unknown',outcome='problem',label=label,
        summary='The scan scope could not be resolved, so the signature was not validated.',
        evidence={evidence},confidence='medium',confidence_reason={'The scope expression could not be resolved from enumerated modules or constants.'},
        likely_causes={'The module name in the scan does not match any enumerated module.','The module size is unavailable, for example with duplicate module names.',
          'The scope uses an expression CESuite does not evaluate.'},
        suggested_next_steps={'Verify the module name used by the scan is loaded in this process.','Check whether duplicate module names make the scope ambiguous.',
          'Test the scope manually in Cheat Engine before changing the table.'},
        limitations={'CESuite deliberately does not evaluate arbitrary expressions or symbol tables.'},
        do_not_assume={'An unresolved scope is not evidence that the signature is wrong.'},source='runtime'})
    elseif status=='error' then
      evidence.description=string.format('The scan for %s failed inside Cheat Engine.',label)
      out[#out+1]=newDiag({id='aob:'..tostring(a.id),rule='AOB-SCAN-ERROR',category='aob',
        severity='medium',status='unknown',outcome='problem',label=label,
        summary='Cheat Engine reported an error while scanning this signature.',
        evidence={evidence},confidence='medium',confidence_reason={'The scan raised an error; no match count is available.'},
        suggested_next_steps={'Review Cheat Engine scan settings and memory types.','Retry Validate AOBs with the process attached and idle.',
          'If the error persists, simplify the pattern to isolate the failing input.'},
        limitations={'The error text comes from Cheat Engine, not from the table.'},source='runtime'})
    elseif status=='unavailable' then
      unavailable=unavailable+1
    elseif status=='invalidated' then
      invalidated=invalidated+1
    end
  end
  if unavailable>0 then
    out[#out+1]=newDiag({id='aob:unavailable',rule='AOB-SCAN-UNAVAILABLE',category='aob',
      severity=report.target and report.target.attached==true and 'medium' or 'high',
      status='unknown',outcome='problem',label=tostring(unavailable)..' AOB scan(s)',
      summary='Some AOB scans could not run because no process was attached or the target changed.',
      evidence={{kind='aggregate',description=tostring(unavailable)..' AOB scan(s) were marked unavailable.',count=unavailable}},
      confidence='high',confidence_reason={'The collection recorded that no valid attached process was available for these scans.'},
      suggested_next_steps={'Attach Cheat Engine to the intended process.','Re-run Validate AOBs without switching process.','Keep the target attached while the analysis runs.'},
      do_not_assume={'Missing scans say nothing about the signature itself.'},source='runtime'})
  end
  if invalidated>0 then
    out[#out+1]=newDiag({id='aob:invalidated',rule='AOB-INVALIDATED',category='aob',
      severity='high',status='unknown',outcome='problem',label=tostring(invalidated)..' AOB scan(s)',
      summary='The attached process changed during scanning, so those results were discarded.',
      evidence={{kind='aggregate',description=tostring(invalidated)..' AOB result(s) were invalidated.',count=invalidated}},
      confidence='high',confidence_reason={'The process or module identity changed during collection.'},
      suggested_next_steps={'Re-run the analysis without changing the attached process.','Close other tools that attach to the same target.'},
      do_not_assume={'Invalidated results are not evidence about the table.'},source='runtime'})
  end
end

-- Target / module diagnostics ----------------------------------------------
local function targetDiagnostics(report, out)
  local target=report.target or {}
  if target.attached~=true then
    out[#out+1]=newDiag({id='target:not-attached',rule='PROCESS-NOT-ATTACHED',category='target',
      severity='high',status='observed',outcome='problem',label='Target process',
      summary='No process was attached, so runtime evidence is unavailable.',
      evidence={{kind='target',description='target.attached = false; no runtime memory was read.',pid=U.null,name=U.null}},
      confidence='high',confidence_reason={'The collection recorded no attached process.'},
      likely_causes={'Cheat Engine was not attached to a process.','The process was closed before the analysis started.'},
      suggested_next_steps={'Attach Cheat Engine to the intended process.','Load the table you want to review, then run Analyze Loaded Table or Validate AOBs.'},
      limitations={'Without an attached process, CESuite cannot validate any runtime signature.'},
      do_not_assume={'A table analysed without a process is not evidence that the table is broken.'},source='runtime'})
  end
  local changed=false
  for _,w in ipairs(report.diagnostics or {}) do
    if str(w.rule)=='PROCESS-CHANGED' then changed=true end
  end
  for _,a in ipairs(report.aobs or {}) do
    if str(a.status)=='invalidated' then changed=true end
  end
  if changed then
    out[#out+1]=newDiag({id='target:process-changed',rule='PROCESS-CHANGED',category='target',
      severity='high',status='observed',outcome='problem',label='Target process',
      summary='The attached process changed during collection, so results are not reliable.',
      evidence={{kind='target',description='PROCESS-CHANGED was recorded, or an AOB result was invalidated.'}},
      confidence='high',confidence_reason={'CESuite detected a process or module identity change.'},
      suggested_next_steps={'Re-run the analysis without switching process.','Avoid attaching or restructuring modules while the analysis runs.'},
      do_not_assume={'Results from a changed process are not evidence about the table.'},source='runtime'})
  end
end

local function moduleDiagnostics(report, out)
  local unavailable=false
  local ambiguous={}
  for _,w in ipairs(report.diagnostics or {}) do
    local rule=str(w.rule)
    if rule=='MODULES-UNAVAILABLE' then unavailable=true end
    if rule=='MODULE-SNAPSHOT-INCOMPLETE' then
      local message=str(w.message) or 'duplicate module name'
      ambiguous[#ambiguous+1]=message
    end
  end
  if unavailable then
    out[#out+1]=newDiag({id='module:unavailable',rule='MODULES-UNAVAILABLE',category='module',
      severity='high',status='unknown',outcome='problem',label='Module list',
      summary='The loaded module list could not be enumerated.',
      evidence={{kind='modules',description='enumModules failed or returned an unusable table.'}},
      confidence='high',confidence_reason={'No module inventory was produced.'},
      suggested_next_steps={'Confirm the process is attached and still running.','Check that Cheat Engine can list modules for this target.','Re-run the analysis.'},
      limitations={'Scoped AOB scans cannot be validated without a module list.'},
      do_not_assume={'A missing module list is not evidence about the table.'},source='runtime'})
  end
  if #ambiguous>0 then
    local evidence={}
    for i=1,math.min(#ambiguous,5) do
      evidence[#evidence+1]={kind='module_ambiguity',description=ambiguous[i]}
    end
    out[#out+1]=newDiag({id='module:ambiguous',rule='MODULE-AMBIGUOUS',category='module',
      severity='medium',status='observed',outcome='problem',label='Module snapshot',
      summary='Ambiguous module names were found; sizes and scoped scans were withheld.',
      evidence=evidence,confidence='high',confidence_reason={'Duplicate normalized module names were enumerated.'},
      likely_causes={'Two loaded modules share the same file name.','A module appears twice in the enumeration.'},
      suggested_next_steps={'Identify which module the table intends by full path.','Avoid name-only scoped scans while duplicates exist.','Re-run after resolving the duplicate.'},
      limitations={'CESuite does not choose a first match on your behalf.'},
      do_not_assume={'A null module size does not mean the module is absent.'},source='runtime'})
  end
end

-- Dependency diagnostics ---------------------------------------------------
-- Names the static analyser classifies as AOB sinks. The dependency inventory
-- records every bare identifier; these are Cheat Engine scan calls, so treating
-- them as unresolved table symbols would contradict the AOB classification.
local SINK_NAMES={aobscan=true,aobscanmodule=true,aobscanregion=true,
  aobscanunique=true,aobscanmoduleunique=true,customscan=true}

local function dependencyDiagnostics(report, out)
  local providers={}
  for _,d in ipairs(report.dependencies or {}) do
    if str(d.relation)=='provides' and str(d.name) then providers[str(d.name):lower()]=true end
  end
  local unresolved={}
  for _,d in ipairs(report.dependencies or {}) do
    local name=str(d.name)
    if str(d.relation)=='requires' and name and not providers[name:lower()]
      and not SINK_NAMES[name:lower()] then
      local entry=unresolved[name]
      if not entry then
        entry={count=0,first=d}
        unresolved[name]=entry
      end
      entry.count=entry.count+1
    end
  end
  local names={}
  for name in pairs(unresolved) do names[#names+1]=name end
  table.sort(names)
  -- Bound the number of dependency diagnostics: large tables can produce many
  -- lexical requires with no visible provider. Remaining names stay in the
  -- extensive report through the raw dependency inventory.
  for i=1,math.min(#names,200) do
    local name=names[i]
    local entry=unresolved[name]
    local d=entry.first
    out[#out+1]=newDiag({id='dependency:'..name,rule='DEPENDENCY-UNRESOLVED-PROVIDER',category='dependency',
      severity='low',status='candidate',outcome='advisory',label='Symbol "'..name..'"',
      summary='A required symbol has no provider occurrence in the analysed scripts.',
      evidence={{kind='lexical_requires',description=string.format('Required %d time(s); no provides occurrence was inventoried.',entry.count),
        name=name,count=entry.count,script_id=str(d.script_id) or U.null,line=num(d.line) or U.null,
        section=str(d.section) or U.null,command=str(d.command) or U.null,kind_detail=str(d.kind) or U.null}},
      confidence='low',confidence_reason={'This is a lexical requires occurrence; no runtime resolution was attempted.'},
      likely_causes={'The provider script is not loaded or did not run in this table version.','The symbol was renamed or removed.',
        'The provider comes from table Lua, a CE built-in, or generated code that passive capture cannot see.'},
      suggested_next_steps={'Confirm the provider script is present and enabled.','Check activation order: providers must run before consumers.',
        'Check whether the symbol was renamed.','Review registersymbol/define relationships in the table.'},
      limitations={'Only script text present in this collection was inspected.'},
      do_not_assume={'A missing provider in source does not prove the symbol is undefined at runtime.'},source='lexical'})
  end
end

-- Static Lua diagnostics ---------------------------------------------------
local function normalizeKey(pattern)
  if type(pattern)~='string' then return nil end
  local compact=pattern:gsub('%s+','')
  if compact=='' then return nil end
  return compact:upper()
end

local function staticDiagnostics(report, out)
  local static=report.static_lua_analysis
  if type(static)~='table' then return end
  local groups,unknown={},0
  local runtimeByPattern={}
  for _,a in ipairs(report.aobs or {}) do
    if str(a.status)=='observed' then
      local key=normalizeKey(str(a.pattern))
      if key then runtimeByPattern[key]=a end
    end
  end
  for _,o in ipairs(static.observations or {}) do
    if str(o.status)=='source-candidate' and str(o.pattern) then
      local key=normalizeKey(o.pattern) or o.pattern
      local group=groups[key]
      if not group then
        group={pattern=o.pattern,count=0,occurrences={}}
        groups[key]=group
      end
      group.count=group.count+1
      if #group.occurrences<5 then group.occurrences[#group.occurrences+1]=o end
    else
      unknown=unknown+1
    end
  end
  local keys={}
  for k in pairs(groups) do keys[#keys+1]=k end
  table.sort(keys)
  for i=1,math.min(#keys,200) do
    local group=groups[keys[i]]
    local evidence={}
    for _,o in ipairs(group.occurrences) do
      evidence[#evidence+1]={kind='static_observation',description=string.format('Line %s in script %s via %s.',
        tostring(o.line),tostring(o.script_id),tostring(o.sink)),
        script_id=str(o.script_id) or U.null,line=num(o.line) or U.null,sink=str(o.sink) or U.null,
        symbol=str(o.symbol) or U.null,pattern=str(o.pattern) or U.null}
    end
    local corroborated=runtimeByPattern[keys[i]]
    local confidence='low'
    local reasons={'Static lexical inventory only; no memory scan was run for this candidate.'}
    if corroborated then
      evidence[#evidence+1]={kind='runtime_corroboration',
        description='The same normalized pattern was also observed in a runtime scan in this collection.',
        match_count=num(corroborated.match_count) or U.null,
        status=str(corroborated.status) or U.null,
        script_id=str(corroborated.script_id) or U.null,line=num(corroborated.line) or U.null}
      reasons[#reasons+1]='A runtime scan with this normalized pattern exists, but it is separate evidence.'
      confidence='medium'
    end
    out[#out+1]=newDiag({id='static:'..tostring(group.pattern),rule='STATIC-CANDIDATE-ONLY',category='static',
      severity='info',status='candidate',outcome='advisory',label='Static candidate "'..tostring(group.pattern)..'"',
      summary='A signature candidate was detected in Lua source only; runtime validity has not been established.',
      evidence=evidence,confidence=confidence,confidence_reason=reasons,
      suggested_next_steps={'Run Validate AOBs or a manual scan for this pattern with the target attached.',
        'Confirm the Lua path that registers this pattern actually runs in the target session.'},
      limitations={'Static analysis never executes Lua and cannot see computed patterns.'},
      do_not_assume={'A source literal does not prove the scan runs or succeeds.','Static candidates are never treated as runtime observations.'},source='static'})
  end
  if unknown>0 then
    out[#out+1]=newDiag({id='static:unresolved',rule='STATIC-UNRESOLVED',category='static',
      severity='info',status='unknown',outcome='not_assessed',label='Static Lua candidates',
      summary='Some Lua source candidates could not be resolved to a literal pattern.',
      evidence={{kind='aggregate',description=tostring(unknown)..' static observation(s) had no resolvable pattern.',count=unknown}},
      confidence='unknown',confidence_reason={'The source expressions were dynamic, incomplete or outside supported syntax.'},
      suggested_next_steps={'Review the referenced Lua manually.','Run the table in the target and validate the pattern by scanning.'},
      limitations={'CESuite does not evaluate Lua expressions.'},source='static'})
  end
  local limit=0
  for _,d in ipairs(static.diagnostics or {}) do
    if str(d.rule)=='LUA-STATIC-LIMIT' then limit=limit+1 end
  end
  if limit>0 then
    out[#out+1]=newDiag({id='static:limit',rule='STATIC-ANALYSIS-LIMIT',category='static',
      severity='low',status='unknown',outcome='not_assessed',label='Static Lua analysis',
      summary='Some Lua sources exceeded static analysis limits or could not be tokenized.',
      evidence={{kind='aggregate',description=tostring(limit)..' static Lua source(s) hit a limit or failed to tokenize.',count=limit}},
      confidence='high',confidence_reason={'The analyser reported a deterministic limit or tokenizer error.'},
      suggested_next_steps={'Review the affected Lua sources manually.','Reduce dynamic or generated content before static analysis.'},
      limitations={'Unanalysed source is not evidence of absence.'},source='static'})
  end
end

-- Review diagnostics -------------------------------------------------------
local consumed={
  ['PROCESS-CHANGED']=true,['PROCESS-UNAVAILABLE']=true,['MODULES-UNAVAILABLE']=true,
  ['MODULE-SNAPSHOT-INCOMPLETE']=true
}

local REVIEW_SUMMARY={
  ['HOOK-REVIEW']='Hook placement needs manual review: anchor, jump span, overwrite and restore are unverified.',
  ['LUA-RVA-HOOK']='A Lua module+RVA hook candidate was detected lexically; runtime behaviour is unverified.',
  ['RESOURCE-OWNERSHIP']='Resource cleanup spans more than one owner; ownership is unverified.',
  ['RESTORE-BEFORE-FREE']='A resource is freed; full byte restoration before free is unverified.',
  ['EMPTY-DISABLE']='A DISABLE section appears empty; persistence may be intentional.',
  ['DYNAMIC-SOURCE']='The script contains dynamic source; literal observations may not match what runs.',
  ['AMBIGUOUS-ANCHOR']='An AOB symbol is reused in one script; hook candidates were omitted.',
  ['SCAN-ERROR-VISIBILITY']='Cheat Engine did not expose scan error detail; uniqueness stays unverified.',
  ['ACTIVE-RECORD']='An active record was observed; target bytes may already be modified.',
  ['TABLE-LUA-UNAVAILABLE']='Standalone table Lua cannot be captured passively; some dependencies may be missing.',
  ['CT-UNAVAILABLE']='The address list could not be read.',
  ['AA-TYPE-UNAVAILABLE']='The Auto Assembler type constant is unavailable; AA scripts cannot be classified.',
  ['CT-LIMIT']='The record inventory was truncated at the record limit.',
  ['RECORD-UNAVAILABLE']='A record could not be read.',
  ['SCRIPT-UNAVAILABLE']='A script source was unavailable.',
  ['SELECTION-EMPTY']='No record was selected for Inspect Selected Script.'
}

local function reviewDiagnostics(report, out)
  local counts,order={},{}
  for _,w in ipairs(report.diagnostics or {}) do
    local rule=str(w.rule)
    if rule and not consumed[rule] then
      local state=counts[rule]
      if not state then
        state={count=0,examples={}}
        counts[rule]=state;order[#order+1]=rule
      end
      state.count=state.count+1
      if #state.examples<5 then state.examples[#state.examples+1]=w end
    end
  end
  table.sort(order)
  for _,rule in ipairs(order) do
    local state=counts[rule]
    local evidence={}
    for _,w in ipairs(state.examples) do
      evidence[#evidence+1]={kind='report_diagnostic',description=str(w.message) or rule,
        rule=rule,script_id=str(w.script_id) or U.null,line=num(w.line) or U.null}
    end
    out[#out+1]=newDiag({id='review:'..rule,rule=rule,category='review',
      severity=REVIEW_SEVERITY[rule] or 'low',status='candidate',outcome='advisory',
      label=rule..' ('..tostring(state.count)..')',
      summary=REVIEW_SUMMARY[rule] or ('Review diagnostic '..rule..' was reported.'),
      evidence=evidence,confidence='low',confidence_reason={'This is a lexical review diagnostic, not a runtime proof.'},
      suggested_next_steps={'Open the referenced script and line.','Verify the behaviour manually in Cheat Engine before changing anything.'},
      limitations={'Review diagnostics are advisory and may be false positives in comments or strings.'},source='lexical'})
  end
end

-- Assessment ---------------------------------------------------------------
local function scopeSummary(report)
  local target=report.target or {}
  local modules=report.modules or {}
  local scripts=report.scripts or {}
  local aobs=report.aobs or {}
  local deps=report.dependencies or {}
  local static=report.static_lua_analysis
  local candidates=0
  if type(static)=='table' then
    for _,o in ipairs(static.observations or {}) do
      if str(o.status)=='source-candidate' then candidates=candidates+1 end
    end
  end
  local name=U.null
  if type(target.name)=='string' and target.name~='' then name=target.name end
  local pid=U.null
  if type(target.pid)=='number' then pid=target.pid end
  return {
    attached=target.attached==true,
    pid=pid,
    process_name=name,
    module_count=#modules,
    script_count=#scripts,
    aob_count=#aobs,
    dependency_occurrence_count=#deps,
    static_candidate_count=candidates
  }
end

local function sortDiagnostics(diagnostics)
  local function key(d)
    return string.format('%d|%d|%s|%s',RULE_PRIORITY[d.rule] or DEFAULT_PRIORITY,
      SEVERITY_RANK[d.severity] or 9,d.id,d.rule)
  end
  table.sort(diagnostics,function(a,b) return key(a)<key(b) end)
  return diagnostics
end

local function plural(n,singular,pluralForm)
  if n==1 then return tostring(n)..' '..singular end
  return tostring(n)..' '..(pluralForm or (singular..'s'))
end

local function actionFor(d)
  local rule=d.rule
  if rule=='PROCESS-NOT-ATTACHED' then return 'Attach Cheat Engine to the intended process, then re-run the analysis.' end
  if rule=='PROCESS-CHANGED' then return 'Re-run the analysis without changing the attached process.' end
  if rule=='MODULES-UNAVAILABLE' then return 'Confirm module enumeration works for the attached process.' end
  if rule=='MODULE-AMBIGUOUS' then return 'Resolve duplicate module names before trusting scoped scans.' end
  if rule=='AOB-NO-MATCH' then return 'Review '..d.label..' — the runtime scan returned zero matches.' end
  if rule=='AOB-AMBIGUOUS' then return 'Review '..d.label..' — the runtime scan returned multiple matches.' end
  if rule=='AOB-SCOPE-UNRESOLVED' then return 'Resolve the scan scope for '..d.label..'.' end
  if rule=='AOB-SCAN-ERROR' then return 'Retry the scan for '..d.label..' after checking Cheat Engine scan settings.' end
  if rule=='AOB-SCAN-UNAVAILABLE' then return 'Attach the intended process and re-run the AOB scans.' end
  if rule=='AOB-INVALIDATED' then return 'Re-run the analysis; the process changed while scanning.' end
  if rule=='AOB-UNSUPPORTED' then return 'Review '..d.label..' manually; it is outside supported scan syntax.' end
  if rule=='DEPENDENCY-UNRESOLVED-PROVIDER' then
    local name=(d.evidence[1] and type(d.evidence[1].name)=='string') and d.evidence[1].name or d.label
    return 'Check the provider for symbol "'..name..'".'
  end
  if rule=='STATIC-CANDIDATE-ONLY' then
    local pattern=(d.evidence[1] and type(d.evidence[1].pattern)=='string') and d.evidence[1].pattern or d.label
    return 'Validate static candidate "'..pattern..'" against the running target.'
  end
  if rule=='STATIC-UNRESOLVED' then return 'Review the unresolved Lua sources manually.' end
  if rule=='STATIC-ANALYSIS-LIMIT' then return 'Review the Lua sources that exceeded static analysis limits.' end
  if rule=='EVIDENCE-INSUFFICIENT' then return 'Collect evidence first: attach a process, load the table and run the analysis.' end
  if d.category=='review' then return 'Review the '..tostring(d.rule)..' findings and the referenced lines.' end
  return 'Review '..tostring(d.label)..'.'
end

local function rationaleFor(d)
  return string.format('%s (%s; confidence %s).',d.summary,d.status,d.confidence)
end

function M.build(report)
  assert(type(report)=='table','diagnose.build requires a report table')
  local diagnostics={}
  targetDiagnostics(report,diagnostics)
  moduleDiagnostics(report,diagnostics)
  aobDiagnostics(report,diagnostics)
  dependencyDiagnostics(report,diagnostics)
  staticDiagnostics(report,diagnostics)
  reviewDiagnostics(report,diagnostics)

  local hasAobs=#(report.aobs or {})>0
  local hasScripts=#(report.scripts or {})>0
  local hasDeps=#(report.dependencies or {})>0
  local static=report.static_lua_analysis
  local hasStatic=type(static)=='table' and #(static.observations or {})>0
  if not hasAobs and not hasScripts and not hasDeps and not hasStatic then
    diagnostics[#diagnostics+1]=newDiag({id='evidence:none',rule='EVIDENCE-INSUFFICIENT',category='evidence',
      severity='medium',status='unknown',outcome='not_assessed',label='Evidence',
      summary='Not enough evidence to recommend a repair step.',
      evidence={{kind='aggregate',description='No scripts, AOB records, dependencies or static candidates were collected.'}},
      confidence='unknown',confidence_reason={'The collection was empty.'},
      suggested_next_steps={'Attach Cheat Engine to the intended process.','Load the table you want to review.',
        'Run Analyze Loaded Table and Validate AOBs, then run Diagnostics again.'},
      do_not_assume={'An empty collection is not evidence that the table is healthy.'},source='runtime'})
  end

  sortDiagnostics(diagnostics)

  local counts={total=#diagnostics,problems=0,healthy=0,advisory=0,not_assessed=0}
  local byId={}
  for _,d in ipairs(diagnostics) do
    byId[d.id]=d
    if d.outcome=='problem' then counts.problems=counts.problems+1
    elseif d.outcome=='healthy' then counts.healthy=counts.healthy+1
    elseif d.outcome=='advisory' then counts.advisory=counts.advisory+1
    else counts.not_assessed=counts.not_assessed+1 end
  end

  local repair_path,order=U.array(),0
  for _,d in ipairs(diagnostics) do
    if d.outcome=='problem' or d.outcome=='advisory' then
      order=order+1
      repair_path[#repair_path+1]={order=order,action=actionFor(d),diagnostic_id=d.id,
        rationale=rationaleFor(d)}
    end
  end

  local headline
  if counts.problems>0 then
    headline=string.format('%s found; %s passed, %s, %s.',
      plural(counts.problems,'problem'),plural(counts.healthy,'check'),
      plural(counts.advisory,'advisory finding'),plural(counts.not_assessed,'item not assessed','items not assessed'))
  elseif counts.advisory>0 then
    headline='No runtime problems found; '..plural(counts.advisory,'advisory finding')..' for manual review.'
  elseif counts.healthy>0 then
    headline='No problems found in the evidence collected; '..plural(counts.healthy,'check')..' passed.'
  else
    headline='Not enough evidence to recommend a repair step.'
  end

  local statements=U.array({
    'Diagnostics are derived from the evidence in this report only; no table was modified.',
    'Static Lua candidates are source observations and are never treated as runtime matches.'
  })
  if #repair_path>0 then statements[#statements+1]='Suggested next steps follow a fixed, documented priority order.' end

  return {
    schema_version='0.1',
    generated_at=report.generated_at or U.null,
    completed_at=report.completed_at or U.null,
    mode=report.mode or 'unknown',
    scope=scopeSummary(report),
    counts=counts,
    headline=headline,
    statements=statements,
    diagnostics=U.array(diagnostics),
    repair_path=repair_path,
    limitations=U.array({
      'Diagnostics interpret collected evidence; they do not prove runtime behaviour beyond the recorded scans.',
      'No table, script, module or target memory was modified.',
      'Static candidates are source-only and are never promoted to runtime observations.',
      'Re-run the analysis after changing the table, the target or the attached process.'
    })
  }
end

M.RULE_PRIORITY=RULE_PRIORITY
M.REVIEW_SEVERITY=REVIEW_SEVERITY
return M
