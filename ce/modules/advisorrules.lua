-- Deterministic, evidence-only rules. No CE, filesystem, network or execution.
local U=require('util')
local M={}
M.VERSION=1
M.RULES={
  {rule_id='COMPARISON_NOT_COMPARABLE',category='comparability_gap',severity='LOW',default_confidence='unknown',precedence=1,requires_comparability=false,required_evidence={'comparability'},suppresses={'candidate_causal'},can_emit_relocation_request=false},
  {rule_id='SOURCE_CHANGED',category='source_change',severity='MEDIUM',default_confidence='exact',precedence=2,requires_comparability=true,required_evidence={'comparability.source_changed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='TARGET_BUILD_CHANGED',category='build_change',severity='MEDIUM',default_confidence='exact',precedence=2,requires_comparability=true,required_evidence={'comparability.different_target_build'},suppresses={},can_emit_relocation_request=false},
  {rule_id='TARGET_CHANGED',category='target_change',severity='MEDIUM',default_confidence='exact',precedence=2,requires_comparability=true,required_evidence={'comparability.different_target'},suppresses={},can_emit_relocation_request=false},
  {rule_id='TARGET_BUILD_UNKNOWN',category='build_change',severity='LOW',default_confidence='unknown',precedence=2,requires_comparability=true,required_evidence={'comparability.target_build_unknown'},suppresses={'TARGET_BUILD_CHANGED'},can_emit_relocation_request=false},
  {rule_id='COVERAGE_CHANGED',category='coverage_gap',severity='LOW',default_confidence='strong',precedence=3,requires_comparability=true,required_evidence={'coverage.collection.changed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='DISCOVERY_COVERAGE_CHANGED',category='coverage_gap',severity='LOW',default_confidence='strong',precedence=3,requires_comparability=true,required_evidence={'coverage.discovery.changed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='VALIDATION_COVERAGE_CHANGED',category='runtime_validation_unavailable',severity='MEDIUM',default_confidence='strong',precedence=3,requires_comparability=true,required_evidence={'coverage.validation.changed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='EVIDENCE_LIMIT_REACHED',category='operation_limit',severity='MEDIUM',default_confidence='exact',precedence=3,requires_comparability=false,required_evidence={'coverage.status'},suppresses={},can_emit_relocation_request=false},
  {rule_id='PATTERN_CHANGED',category='pattern_change',severity='MEDIUM',default_confidence='exact',precedence=4,requires_comparability=true,required_evidence={'candidate.pattern'},suppresses={},can_emit_relocation_request=false},
  {rule_id='PROVIDER_CHANGED',category='provider_change',severity='MEDIUM',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'candidate.provider'},suppresses={},can_emit_relocation_request=false},
  {rule_id='CONSUMER_CHANGED',category='dependency_change',severity='MEDIUM',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'candidate.consumer'},suppresses={},can_emit_relocation_request=false},
  {rule_id='HELPER_CHANGED',category='dependency_change',severity='LOW',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'candidate.helper'},suppresses={},can_emit_relocation_request=false},
  {rule_id='PROVENANCE_CHANGED',category='dependency_change',severity='LOW',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'candidate.provenance'},suppresses={},can_emit_relocation_request=false},
  {rule_id='CANDIDATE_MISSING',category='candidate_missing',severity='MEDIUM',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'diff.candidate.removed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='CANDIDATE_ADDED',category='candidate_added',severity='LOW',default_confidence='strong',precedence=4,requires_comparability=true,required_evidence={'diff.candidate.added'},suppresses={},can_emit_relocation_request=false},
  {rule_id='WEAK_IDENTITY',category='candidate_ambiguity',severity='LOW',default_confidence='unknown',precedence=4,requires_comparability=false,required_evidence={'candidate.unknown'},suppresses={},can_emit_relocation_request=false},
  {rule_id='VALIDATION_LOST',category='validation_change',severity='HIGH',default_confidence='exact',precedence=5,requires_comparability=true,required_evidence={'candidate.validation.state'},suppresses={},can_emit_relocation_request=false},
  {rule_id='VALIDATION_AMBIGUOUS',category='validation_change',severity='HIGH',default_confidence='exact',precedence=5,requires_comparability=true,required_evidence={'candidate.validation.state'},suppresses={},can_emit_relocation_request=false},
  {rule_id='VALIDATION_UNAVAILABLE',category='runtime_validation_unavailable',severity='MEDIUM',default_confidence='strong',precedence=5,requires_comparability=false,required_evidence={'candidate.validation.state'},suppresses={'invalid_interpretation'},can_emit_relocation_request=false},
  {rule_id='VALIDATION_STATE_CHANGED',category='validation_change',severity='LOW',default_confidence='strong',precedence=5,requires_comparability=true,required_evidence={'candidate.validation.state'},suppresses={},can_emit_relocation_request=false},
  {rule_id='DEPENDENCY_CHANGED',category='dependency_change',severity='LOW',default_confidence='strong',precedence=6,requires_comparability=true,required_evidence={'dependencies'},suppresses={},can_emit_relocation_request=false},
  {rule_id='MODULE_INVENTORY_CHANGED',category='module_change',severity='LOW',default_confidence='strong',precedence=7,requires_comparability=true,required_evidence={'modules'},suppresses={},can_emit_relocation_request=false},
  {rule_id='UNRESOLVED_ADDED',category='unresolved_dependency',severity='LOW',default_confidence='strong',precedence=8,requires_comparability=false,required_evidence={'unresolved.added'},suppresses={},can_emit_relocation_request=false},
  {rule_id='UNRESOLVED_REMOVED',category='unresolved_dependency',severity='INFO',default_confidence='strong',precedence=8,requires_comparability=false,required_evidence={'unresolved.removed'},suppresses={},can_emit_relocation_request=false},
  {rule_id='NO_MEANINGFUL_CHANGE',category='no_meaningful_change',severity='INFO',default_confidence='exact',precedence=9,requires_comparability=true,required_evidence={'comparability'},suppresses={},can_emit_relocation_request=false},
}
M.RULE_METADATA={}
for _,r in ipairs(M.RULES) do
  assert(not M.RULE_METADATA[r.rule_id],'duplicate rule ID: '..tostring(r.rule_id))
  M.RULE_METADATA[r.rule_id]=r
end
M.RULE_METADATA.SOURCE_CHANGED.mandatory_assumptions={'SOURCE_CHANGE_NOT_BREAKAGE'}
M.RULE_METADATA.TARGET_BUILD_CHANGED.mandatory_assumptions={'BUILD_CHANGE_NOT_INCOMPATIBILITY'}
M.RULE_METADATA.VALIDATION_LOST.mandatory_assumptions={'UNIQUE_MATCH_NOT_FUNCTIONALITY'}
M.RULE_METADATA.UNRESOLVED_REMOVED.mandatory_assumptions={'UNRESOLVED_REMOVED_NOT_FIXED'}
M.ASSUMPTIONS={
  UNIQUE_MATCH_NOT_FUNCTIONALITY='Do not assume a unique match proves functionality.',
  SOURCE_CHANGE_NOT_BREAKAGE='Do not assume source_changed means the table is broken.',
  BUILD_CHANGE_NOT_INCOMPATIBILITY='Do not assume a build change means the table is incompatible.',
  UNRESOLVED_REMOVED_NOT_FIXED='Do not assume an unresolved entry disappeared because it was fixed.',
  READ_OK_NOT_SEMANTIC_VALIDATION='Do not assume a successful read establishes semantic correctness.'
}
M.NEXT_STEP_ENUM={
  REVIEW_EVIDENCE=true,CAPTURE_NEW_SNAPSHOT=true,COMPARE_TARGET_BUILD=true,
  INCREASE_COVERAGE=true,VALIDATE_CANDIDATE=true,REVIEW_PROVENANCE=true,
  REVIEW_DEPENDENCIES=true,RUN_ADDRESS_EVIDENCE=true,REQUEST_RELOCATION_CANDIDATES=true
}
M.REQUIRED_ASSUMPTIONS={
  SOURCE_CHANGED={'SOURCE_CHANGE_NOT_BREAKAGE'},
  TARGET_BUILD_CHANGED={'BUILD_CHANGE_NOT_INCOMPATIBILITY'},
  VALIDATION_LOST={'UNIQUE_MATCH_NOT_FUNCTIONALITY'},
  UNRESOLVED_REMOVED={'UNRESOLVED_REMOVED_NOT_FIXED'}
}


local RANK={INFO=1,LOW=2,MEDIUM=3,HIGH=4,CRITICAL=5}

local function ref(source,entity,id,field,value)
  return {source=source,entity=entity,id=id==nil and U.null or id,
    field=field,value=value==nil and U.null or value}
end
local function canonical_parts(parts)
  local out={}
  for i=1,#parts do
    local v=tostring(parts[i]==nil and U.null or parts[i])
    out[#out+1]=#v..':'..v
  end
  return table.concat(out,'|')
end
local function add(out,opts)
  local meta=M.RULE_METADATA[opts.rule_id]
  if not meta then error('unknown rule: '..tostring(opts.rule_id)) end
  out[#out+1]={
    rule_id=opts.rule_id,code=opts.code,category=meta.category,
    severity=meta.severity,status=opts.status or 'observed',
    confidence=opts.confidence or meta.default_confidence,
    precedence=meta.precedence,
    evidence_refs=U.array(opts.refs or {}),
    observations=U.array(opts.observations or {}),
    interpretation=opts.interpretation or '',
    likely_causes=U.array(opts.causes or {}),
    suggested_next_steps=U.array(opts.steps or {}),
    do_not_assume=U.array(opts.do_not_assume or {'Do not treat this finding as a repair instruction.'}),
    limitations=U.array(opts.limitations or {}),
    _key=opts.key or opts.code
  }
end
local function step(action,detail)
  return {action=action,detail=detail}
end
local function first_limitation(snapshot)
  local out={}
  for _,v in ipairs(snapshot.limitations or {}) do
    if type(v)=='string' and v:match('^SNAPSHOT_') then out[#out+1]=v end
  end
  return out
end
local function coverage_limited(diff)
  local vals={}
  for _,side in ipairs({'a','b'}) do
    local s=diff[side]
    -- The diff metadata does not carry limitations; coverage status is the
    -- observable limit signal available to this rule input.
    local c=diff.coverage and diff.coverage.collection
    if c and (c.a_status=='limit_reached' or c.b_status=='limit_reached') then vals[#vals+1]=side end
  end
  return vals
end

function M.evaluate(ctx)
  local out=U.array()
  local diff=ctx.diff
  if not diff then
    -- Single snapshot/analysis: context findings only.
    if ctx.validation_unavailable then
      add(out,{rule_id='VALIDATION_UNAVAILABLE',code='VALIDATION_COVERAGE_UNAVAILABLE',
        category='runtime_validation_unavailable',severity='MEDIUM',status='observed',
        confidence='strong',refs={ref(ctx.snapshot and 'snapshot_a' or 'analysis','coverage',nil,'validation.status','unavailable')},
        observations={'Validation coverage is unavailable; no candidate was runtime-validated.'},
        interpretation='Validation could not be established from this evidence.',
        causes={'No runtime scan was attempted.','The target or scan context was unavailable.'},
        steps={step('VALIDATE_CANDIDATE','Run an explicit runtime validation when available.'),
          step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot after validation.')},
        do_not_assume={'Do not assume a candidate is invalid because validation is unavailable.',
          'Do not assume a unique or zero match without runtime evidence.'}})
    end
    if ctx.limit_reached then
      add(out,{rule_id='EVIDENCE_LIMIT_REACHED',code='EVIDENCE_LIMIT_REACHED',
        category='operation_limit',severity='MEDIUM',confidence='exact',
        refs={ref(ctx.snapshot and 'snapshot_a' or 'analysis','coverage',nil,'collection.status','limit_reached')},
        observations={'The input reports a structural or snapshot limit.'},
        interpretation='Some evidence may be truncated; conclusions are bounded.',
        causes={'A bounded collection or storage limit was reached.'},
        steps={step('REVIEW_EVIDENCE','Review the recorded limitations.'),step('CAPTURE_NEW_SNAPSHOT','Capture a bounded snapshot with larger limits if appropriate.')},
        do_not_assume={'Do not assume the captured evidence is complete.'}})
    end
    return out
  end

  local comp=diff.comparability or {}
  local candidates=diff.candidates or {}
  local no_candidate_changes=(#(candidates.changed or {})==0 and #(candidates.added or {})==0
    and #(candidates.removed or {})==0 and #(candidates.unknown or {})==0)

  if comp.status=='not_comparable' then
    add(out,{rule_id='COMPARISON_NOT_COMPARABLE',code='COMPARISON_NOT_COMPARABLE',
      category='comparability_gap',severity='LOW',status='not_comparable',confidence='unknown',
      refs={ref('diff','comparability',nil,'status',comp.status)},
      observations={'The snapshots are not comparable.'},
      interpretation='Candidate-level causal claims are not supported.',
      causes={'Missing identity, source or target evidence.','Unsupported snapshot version.'},
      steps={step('REVIEW_EVIDENCE','Review comparability reasons.'),step('CAPTURE_NEW_SNAPSHOT','Capture comparable evidence if possible.')},
      do_not_assume={'Do not infer a broken, repaired or incompatible table from this comparison.'}})
    return out
  end

  if comp.source_changed then
    add(out,{rule_id='SOURCE_CHANGED',code='SOURCE_CHANGED',
      category='source_change',severity='MEDIUM',confidence='exact',
      refs={ref('diff','comparability',nil,'source_changed',true)},
      observations={'The source fingerprints differ between A and B.'},
      interpretation='The captured source changed between observations.',
      causes={'A script or table source was edited.','The captured source set differs.'},
      steps={step('REVIEW_EVIDENCE','Review source and candidate changes.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot from the intended source.')},
      do_not_assume={M.ASSUMPTIONS.SOURCE_CHANGE_NOT_BREAKAGE,
        'Do not assume candidates with different source semantics are equivalent.'}})
  end

  if comp.different_target_build then
    add(out,{rule_id='TARGET_BUILD_CHANGED',code='TARGET_BUILD_CHANGED',
      category='build_change',severity='MEDIUM',confidence='exact',
      refs={ref('diff','comparability',nil,'different_target_build',true)},
      observations={'Both target builds are known and their fingerprints differ.'},
      interpretation='The target build context changed between observations.',
      causes={'The target executable or module metadata changed.'},
      steps={step('COMPARE_TARGET_BUILD','Confirm target build context.'),step('REVIEW_EVIDENCE','Review validation evidence against the new build.')},
      do_not_assume={M.ASSUMPTIONS.BUILD_CHANGE_NOT_INCOMPATIBILITY,
        'Do not assume a candidate still has the same semantics across builds.'}})
  end
  if comp.different_target then
    add(out,{rule_id='TARGET_CHANGED',code='TARGET_CHANGED',
      category='target_change',severity='MEDIUM',confidence='exact',
      refs={ref('diff','comparability',nil,'different_target',true)},
      observations={'The target identity differs between snapshots.'},
      interpretation='Validation contexts are not directly comparable.',
      causes={'A different process or target was observed.'},
      steps={step('COMPARE_TARGET_BUILD','Compare target metadata.'),step('CAPTURE_NEW_SNAPSHOT','Capture both snapshots against the intended target.')},
      do_not_assume={'Do not compare runtime validation states as if they shared a target.'}})
  end
  if comp.target_build_unknown then
    add(out,{rule_id='TARGET_BUILD_UNKNOWN',code='TARGET_BUILD_UNKNOWN',
      category='build_change',severity='LOW',status='unknown',confidence='unknown',
      refs={ref('diff','comparability',nil,'target_build_unknown',true)},
      observations={'A complete target build fingerprint is unavailable.'},
      interpretation='Build identity and validation context are incomplete.',
      causes={'Module size/hash/timestamp evidence was unavailable.'},
      steps={step('COMPARE_TARGET_BUILD','Collect target module metadata.'),step('CAPTURE_NEW_SNAPSHOT','Capture with target metadata when available.')},
      do_not_assume={'Do not claim a target build changed.',
        'Do not treat a name match as a build identity.'}})
  end

  local coverage=diff.coverage or {}
  if coverage.collection and coverage.collection.changed then
    add(out,{rule_id='COVERAGE_CHANGED',code='COVERAGE_CHANGED',
      category='coverage_gap',severity='LOW',confidence='strong',
      refs={ref('diff','coverage',nil,'collection.changed',true)},
      observations={'Collection coverage fields changed between snapshots.'},
      interpretation='The observed collection scope changed; this does not establish table quality.',
      causes={'Different source capture.','A limit or capture failure.'},
      steps={step('REVIEW_EVIDENCE','Review collection status and limitations.'),step('INCREASE_COVERAGE','Improve source coverage if needed.')},
      do_not_assume={'Do not interpret reduced coverage as evidence that a candidate is invalid.'}})
  end
  if coverage.discovery and coverage.discovery.changed then
    add(out,{rule_id='DISCOVERY_COVERAGE_CHANGED',code='DISCOVERY_COVERAGE_CHANGED',
      category='coverage_gap',severity='LOW',confidence='strong',
      refs={ref('diff','coverage',nil,'discovery.changed',true)},
      observations={'Discovery counts/status changed between snapshots.'},
      interpretation='The number or classification of discovered evidence changed.',
      causes={'Source changes.','Coverage or parser limits.'},
      steps={step('REVIEW_EVIDENCE','Review discovery fields.'),step('INCREASE_COVERAGE','Capture additional source if needed.')},
      do_not_assume={'Do not assume a lower count means a candidate is missing without source evidence.'}})
  end
  if coverage.validation and not coverage.validation.changed
      and (coverage.validation.a_status=='unavailable' or coverage.validation.b_status=='unavailable') then
    add(out,{rule_id='VALIDATION_UNAVAILABLE',code='VALIDATION_COVERAGE_UNAVAILABLE',
      category='runtime_validation_unavailable',severity='MEDIUM',confidence='strong',
      refs={ref('diff','coverage',nil,'validation.status',coverage.validation.b_status)},
      observations={'Validation coverage is unavailable in the compared evidence.'},
      interpretation='Runtime validation could not be established.',
      causes={'No runtime scan was attempted.','The target or scan context was unavailable.'},
      steps={step('VALIDATE_CANDIDATE','Run an explicit validation when available.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot after validation.')},
      do_not_assume={'Do not assume a candidate is invalid because validation is unavailable.'}})
  end
  if coverage.validation and coverage.validation.changed then
    local v=diff.coverage.validation
    local aStatus=v.a_status or U.null
    local bStatus=v.b_status or U.null
    add(out,{rule_id='VALIDATION_COVERAGE_CHANGED',code='VALIDATION_COVERAGE_CHANGED',
      category='runtime_validation_unavailable',severity='MEDIUM',confidence='strong',
      refs={ref('diff','coverage',nil,'validation.status',bStatus)},
      observations={'Validation coverage changed from '..tostring(aStatus)..' to '..tostring(bStatus)..'.'},
      interpretation='Runtime validation availability or results changed.',
      causes={'Scan attempts changed.','Target/scan context changed.'},
      steps={step('VALIDATE_CANDIDATE','Validate candidates when a scan is available.'),step('REVIEW_EVIDENCE','Review validation limitations.')},
      do_not_assume={'Do not convert unavailable validation into a negative result.'}})
  end

  local limits=coverage_limited(diff)
  if #limits>0 then
    add(out,{rule_id='EVIDENCE_LIMIT_REACHED',code='EVIDENCE_LIMIT_REACHED',
      category='operation_limit',severity='MEDIUM',confidence='exact',
      refs={ref('diff','coverage',nil,'collection.status','limit_reached')},
      observations={'At least one snapshot reports collection limit_reached.'},
      interpretation='Evidence may be truncated; dependent conclusions are bounded.',
      causes={'A structural or storage limit was reached.'},
      steps={step('REVIEW_EVIDENCE','Review all limitations.'),step('CAPTURE_NEW_SNAPSHOT','Capture a bounded snapshot with sufficient limits.')},
      do_not_assume={'Do not assume truncated evidence is complete.'}})
  end

  -- Candidate-level findings. These are only reached for comparable inputs.
  for _,c in ipairs(candidates.changed or {}) do
    local key=c.key or U.null
    for _,f in ipairs(c.fields or {}) do
      local field=f.field
      local old,new=f.a,f.b
      if field=='pattern' then
        add(out,{rule_id='PATTERN_CHANGED',code='PATTERN_CHANGED',category='pattern_change',
          severity='MEDIUM',confidence='exact',key='pattern:'..tostring(key),
          refs={ref('snapshot_a','candidate',key,'pattern',old),ref('snapshot_b','candidate',key,'pattern',new),ref('diff','candidate',key,'pattern',new)},
          observations={'A pattern changed from '..tostring(old)..' to '..tostring(new)..'.'},
          interpretation='The observed pattern differs between snapshots.',
          causes={'The source pattern was edited.','A helper/provider changed the derived pattern.'},
          steps={step('REVIEW_EVIDENCE','Compare the pattern and its provenance.'),step('REVIEW_PROVENANCE','Inspect consumer/provider evidence.')},
          do_not_assume={'Do not assume the new pattern is equivalent or invalid.'}})
      elseif field=='provider' then
        add(out,{rule_id='PROVIDER_CHANGED',code='PROVIDER_CHANGED',category='provider_change',
          severity='MEDIUM',confidence='strong',key='provider:'..tostring(key),
          refs={ref('snapshot_a','candidate',key,'provider',old),ref('snapshot_b','candidate',key,'provider',new)},
          observations={'The candidate provider changed from '..tostring(old)..' to '..tostring(new)..'.'},
          interpretation='The dependency/provider path changed between snapshots.',
          causes={'A helper/provider definition changed.','A loader/include path changed.'},
          steps={step('REVIEW_PROVENANCE','Inspect the provider and helper path.'),step('REVIEW_EVIDENCE','Review the candidate provenance.')},
          do_not_assume={'Do not assume the script was repaired.'}})
      elseif field=='consumer' then
        add(out,{rule_id='CONSUMER_CHANGED',code='CONSUMER_CHANGED',category='dependency_change',
          severity='MEDIUM',confidence='strong',key='consumer:'..tostring(key),
          refs={ref('snapshot_a','candidate',key,'consumer',old),ref('snapshot_b','candidate',key,'consumer',new)},
          observations={'The candidate consumer changed from '..tostring(old)..' to '..tostring(new)..'.'},
          interpretation='The registration/consumer path changed.',
          causes={'Wrapper or call-site path changed.'},
          steps={step('REVIEW_PROVENANCE','Inspect the consumer path.'),step('REVIEW_EVIDENCE','Review wrapper/consumer evidence.')},
          do_not_assume={'Do not assume the candidate has equivalent semantics.'}})
      elseif field=='helper' then
        add(out,{rule_id='HELPER_CHANGED',code='HELPER_CHANGED',category='dependency_change',
          severity='LOW',confidence='strong',key='helper:'..tostring(key),
          refs={ref('snapshot_a','candidate',key,'helper',old),ref('snapshot_b','candidate',key,'helper',new)},
          observations={'The helper reference changed from '..tostring(old)..' to '..tostring(new)..'.'},
          interpretation='The helper/dependency path changed.',
          causes={'Helper definition or source changed.'},
          steps={step('REVIEW_PROVENANCE','Inspect the helper source.'),step('REVIEW_EVIDENCE','Review helper resolution.')},
          do_not_assume={'Do not assume the helper is valid or invalid.'}})
      elseif field=='provenance' then
        add(out,{rule_id='PROVENANCE_CHANGED',code='PROVENANCE_CHANGED',category='dependency_change',
          severity='LOW',confidence='strong',key='provenance:'..tostring(key),
          refs={ref('snapshot_a','candidate',key,'provenance',old),ref('snapshot_b','candidate',key,'provenance',new)},
          observations={'The candidate provenance summary changed.'},
          interpretation='The evidence path changed between snapshots.',
          causes={'A provider, wrapper or source path changed.'},
          steps={step('REVIEW_PROVENANCE','Inspect the provenance summary.'),step('REVIEW_EVIDENCE','Review candidate evidence.')},
          do_not_assume={'Do not assume the script was repaired.'}})
      elseif field=='validation_state' then
        if old=='unique' and new=='no_match' then
          add(out,{rule_id='VALIDATION_LOST',code='PATTERN_NO_LONGER_MATCHES_OBSERVED_TARGET',
            category='validation_change',severity='HIGH',confidence='exact',key='validation:'..tostring(key),
            refs={ref('snapshot_a','candidate',key,'validation.state',old),ref('snapshot_b','candidate',key,'validation.state',new),ref('diff','candidate',key,'validation_state',new)},
            observations={'A.validation.state = unique; B.validation.state = no_match.'},
            interpretation='The previously validated pattern no longer matches the currently observed target.',
            causes={'The pattern changed.','The target build changed.','Module layout changed.','Coverage/validation context changed.'},
            steps={step('REVIEW_EVIDENCE','Review pattern and validation evidence.'),step('VALIDATE_CANDIDATE','Run an explicit validation against the intended target.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot after validation.')},
            do_not_assume={'Do not assume the cheat is broken.','Do not assume a unique match proves functionality.','Do not replace the pattern without further evidence.'}})
        elseif old=='unique' and new=='ambiguous' then
          add(out,{rule_id='VALIDATION_AMBIGUOUS',code='PATTERN_NOW_MATCHES_MULTIPLE_LOCATIONS',
            category='validation_change',severity='HIGH',confidence='exact',key='validation:'..tostring(key),
            refs={ref('snapshot_a','candidate',key,'validation.state',old),ref('snapshot_b','candidate',key,'validation.state',new)},
            observations={'A.validation.state = unique; B.validation.state = ambiguous.'},
            interpretation='The pattern now matches multiple observed locations.',
            causes={'Target/build change.','Pattern specificity changed.','Scan context changed.'},
            steps={step('REVIEW_EVIDENCE','Review match evidence.'),step('VALIDATE_CANDIDATE','Revalidate with explicit scan evidence.'),step('RUN_ADDRESS_EVIDENCE','Inspect a representative address if available.')},
            do_not_assume={'Do not assume the candidate is invalid.','Do not select a location automatically.'}})
        elseif new=='unavailable' or new=='not_attempted' or new=='unknown' then
          add(out,{rule_id='VALIDATION_UNAVAILABLE',code='VALIDATION_COVERAGE_UNAVAILABLE',
            category='runtime_validation_unavailable',severity='MEDIUM',confidence='strong',key='validation:'..tostring(key),
            refs={ref('snapshot_b','candidate',key,'validation.state',new)},
            observations={'Candidate B.validation.state = '..tostring(new)..'.'},
            interpretation='Validation could not be established for this candidate.',
            causes={'No runtime scan was attempted.','The target was unavailable.'},
            steps={step('VALIDATE_CANDIDATE','Run an explicit validation when available.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot after validation.')},
            do_not_assume={'Do not assume the candidate is invalid because validation is unavailable.'}})
        else
          add(out,{rule_id='VALIDATION_STATE_CHANGED',code='VALIDATION_STATE_CHANGED',
            category='validation_change',severity='LOW',confidence='strong',key='validation:'..tostring(key),
            refs={ref('snapshot_a','candidate',key,'validation.state',old),ref('snapshot_b','candidate',key,'validation.state',new)},
            observations={'Validation state changed from '..tostring(old)..' to '..tostring(new)..'.'},
            interpretation='The observed validation state changed.',
            causes={'Scan result or validation availability changed.'},
            steps={step('REVIEW_EVIDENCE','Review validation evidence.'),step('VALIDATE_CANDIDATE','Revalidate if appropriate.')},
            do_not_assume={'Do not infer functionality from the state alone.'}})
        end
      end
    end
  end

  for _,c in ipairs(candidates.removed or {}) do
    add(out,{rule_id='CANDIDATE_MISSING',code='CANDIDATE_MISSING',category='candidate_missing',
      severity='MEDIUM',confidence='strong',key='removed:'..tostring(c.key),
      refs={ref('diff','candidate',c.key,'removed',true)},
      observations={'A candidate present in A is absent from B.'},
      interpretation='The candidate was not discovered in the second observation.',
      causes={'Source changed.','Coverage or discovery limit.','Candidate identity changed.'},
      steps={step('REVIEW_EVIDENCE','Review source and coverage.'),step('INCREASE_COVERAGE','Capture additional source if needed.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot.')},
      do_not_assume={'Do not assume the candidate was removed intentionally.'}})
  end
  for _,c in ipairs(candidates.added or {}) do
    add(out,{rule_id='CANDIDATE_ADDED',code='CANDIDATE_ADDED',category='candidate_added',
      severity='LOW',confidence='strong',key='added:'..tostring(c.key),
      refs={ref('diff','candidate',c.key,'added',true)},
      observations={'A candidate is present in B but absent from A.'},
      interpretation='A new candidate was discovered in the second observation.',
      causes={'Source changed.','Coverage improved.'},
      steps={step('REVIEW_EVIDENCE','Review the new candidate evidence.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot if changes continue.')},
      do_not_assume={'Do not assume the new candidate is valid or equivalent.'}})
  end
  if #(candidates.unknown or {})>0 then
    add(out,{rule_id='WEAK_IDENTITY',code='WEAK_CANDIDATE_IDENTITY',category='candidate_ambiguity',
      severity='LOW',status='not_comparable',confidence='unknown',key='unknown',
      refs={ref('diff','candidate',nil,'unknown',#candidates.unknown)},
      observations={'Some candidates could not be matched by a strong identity.'},
      interpretation='Those candidates are not comparable across this source change.',
      causes={'No symbol/strong identity.','Line-only identity.'},
      steps={step('REVIEW_EVIDENCE','Review the unknown candidates.'),step('CAPTURE_NEW_SNAPSHOT','Capture comparable source if possible.')},
      do_not_assume={'Do not match weak candidates by line or heuristic.'}})
  end

  if diff.modules and diff.modules.changed then
    add(out,{rule_id='MODULE_INVENTORY_CHANGED',code='MODULE_INVENTORY_CHANGED',
      category='module_change',severity='LOW',confidence='strong',
      refs={ref('diff','module',nil,'inventory.changed',true)},
      observations={'The module inventory fingerprint changed.'},
      interpretation='The observed module inventory differs.',
      causes={'Target build or module load set changed.'},
      steps={step('COMPARE_TARGET_BUILD','Compare target/module metadata.'),step('REVIEW_EVIDENCE','Review module evidence.')},
      do_not_assume={'Do not use ASLR bases as persistent module identity.'}})
  end

  for _,u in ipairs(diff.unresolved and diff.unresolved.added or {}) do
    add(out,{rule_id='UNRESOLVED_ADDED',code='UNRESOLVED_DEPENDENCY_ADDED',
      category='unresolved_dependency',severity='LOW',confidence='strong',key='unresolved-added:'..tostring(u.code)..':'..tostring(u.name),
      refs={ref('diff','unresolved',u.name,'added',true)},
      observations={'An unresolved dependency was added: '..tostring(u.code)..' '..tostring(u.name)..'.'},
      interpretation='A dependency remains unresolved in the second observation.',
      causes={'Missing helper/loader definition.','Incomplete source capture.'},
      steps={step('REVIEW_PROVENANCE','Inspect the helper/loader path.'),step('INCREASE_COVERAGE','Capture additional source if needed.')},
      do_not_assume={'Do not assume the dependency is invalid or missing from the game.'}})
  end
  for _,u in ipairs(diff.unresolved and diff.unresolved.removed or {}) do
    add(out,{rule_id='UNRESOLVED_REMOVED',code='UNRESOLVED_DEPENDENCY_REMOVED',
      category='unresolved_dependency',severity='INFO',confidence='strong',key='unresolved-removed:'..tostring(u.code)..':'..tostring(u.name),
      refs={ref('diff','unresolved',u.name,'removed',true)},
      observations={'An unresolved dependency present in A is absent from B.'},
      interpretation='The unresolved entry disappeared from the second observation.',
      causes={'Source changed.','Dependency resolved or coverage changed.'},
      steps={step('REVIEW_EVIDENCE','Review dependency evidence.'),step('CAPTURE_NEW_SNAPSHOT','Capture a new snapshot if needed.')},
      do_not_assume={M.ASSUMPTIONS.UNRESOLVED_REMOVED_NOT_FIXED}})
  end

  if diff.dependencies and (#(diff.dependencies.added or {})>0 or #(diff.dependencies.removed or {})>0 or #(diff.dependencies.changed or {})>0) then
    add(out,{rule_id='DEPENDENCY_CHANGED',code='DEPENDENCY_EVIDENCE_CHANGED',
      category='dependency_change',severity='LOW',confidence='strong',
      refs={ref('diff','dependency',nil,'changed',true)},
      observations={'Dependency evidence changed between snapshots.'},
      interpretation='The observed dependency set or counts changed.',
      causes={'Source changed.','Coverage changed.'},
      steps={step('REVIEW_PROVENANCE','Review dependency occurrences.'),step('REVIEW_EVIDENCE','Review source evidence.')},
      do_not_assume={'Do not infer runtime availability from lexical dependencies.'}})
  end

  if #out==0 and comp.status=='comparable' and no_candidate_changes then
    add(out,{rule_id='NO_MEANINGFUL_CHANGE',code='NO_MEANINGFUL_CHANGE',
      category='no_meaningful_change',severity='INFO',confidence='exact',
      refs={ref('diff','comparability',nil,'status',comp.status)},
      observations={'No candidate, coverage, dependency, unresolved or module change was observed.'},
      interpretation='No meaningful evidence change was detected in the compared fields.',
      causes={'The compared evidence is unchanged.'},
      steps={step('REVIEW_EVIDENCE','Review the snapshot evidence if context matters.')},
      do_not_assume={'Do not assume unchanged evidence proves a table or target is working.'}})
  end

  -- Deduplicate by code/key, keeping the highest severity and bounded refs.
  local map,order={},U.array()
  for _,f in ipairs(out) do
    local k=canonical_parts({f.code,f._key})
    local prev=map[k]
    if not prev then map[k]=f;order[#order+1]=k
    elseif (RANK[f.severity] or 0)>(RANK[prev.severity] or 0) then map[k]=f end
  end
  local list={}
  for _,k in ipairs(order) do list[#list+1]=map[k] end
  -- Formal suppression: unknown build context cannot support a build-change claim.
  local build_unknown=false
  for _,f in ipairs(list) do if f.rule_id=='TARGET_BUILD_UNKNOWN' then build_unknown=true end end
  if build_unknown then
    local kept={}
    for _,f in ipairs(list) do if f.rule_id~='TARGET_BUILD_CHANGED' then kept[#kept+1]=f end end
    list=kept
  end
  table.sort(list,function(a,b)
    if (a.precedence or 9)~=(b.precedence or 9) then return (a.precedence or 9)<(b.precedence or 9) end
    local ar,br=RANK[a.severity] or 0,RANK[b.severity] or 0
    if ar~=br then return ar>br end
    if a.code~=b.code then return a.code<b.code end
    return canonical_parts({a._key})<canonical_parts({b._key})
  end)
  local unique=#list
  if unique>64 then
    local capped={}
    for i=1,64 do capped[i]=list[i] end
    capped.truncated=true
    list=capped
  else
    list.truncated=false
  end
  return list
end

return M
