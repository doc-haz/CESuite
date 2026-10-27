-- Evidence Advisor v1: pure, deterministic evidence interpretation.
-- No CE API, filesystem, network, snapshots execution or table mutation.
local U=require('util')
local E=require('exporter')
local Rules=require('advisorrules')
local M={}

M.VERSION=1
M.RULESET_VERSION=Rules.VERSION
M.SCHEMA_ID='cesuite.evidence_advisor'
M.ASSUMPTIONS=Rules.ASSUMPTIONS
M.MAX_FINDINGS=64
M.MAX_EVIDENCE_REFS=16
M.MAX_OBSERVATIONS=16
M.MAX_CAUSES=8
M.MAX_STEPS=8
M.MAX_DO_NOT_ASSUME=16
M.MAX_CANDIDATES=2000
M.ALLOWED_ACTIONS={
  REVIEW_EVIDENCE=true,INCREASE_COVERAGE=true,VALIDATE_CANDIDATE=true,
  REVIEW_PROVENANCE=true,REVIEW_DEPENDENCIES=true,COMPARE_TARGET_BUILD=true,CAPTURE_NEW_SNAPSHOT=true,
  RUN_ADDRESS_EVIDENCE=true,REQUEST_RELOCATION_CANDIDATES=true
}
M.CATEGORIES={
  source_change=true,pattern_change=true,validation_change=true,coverage_gap=true,
  dependency_change=true,provider_change=true,target_change=true,build_change=true,
  unresolved_dependency=true,candidate_ambiguity=true,candidate_missing=true,
  candidate_added=true,runtime_validation_unavailable=true,module_change=true,
  address_evidence_change=true,operation_limit=true,privacy_redaction=true,
  no_meaningful_change=true,comparability_gap=true
}

M.SOURCES={diff=true,snapshot_a=true,snapshot_b=true,analysis=true,address=true}
M.ENTITIES={comparability=true,candidate=true,coverage=true,target=true,module=true,
  dependency=true,unresolved=true,operation=true,address=true}

local function ror(x,n) x=x&0xffffffff;return ((x>>n)|(x<<(32-n)))&0xffffffff end
local function sha256(msg)
  msg=tostring(msg or '')
  local h0,h1,h2,h3,h4,h5,h6,h7=0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
    0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
  local k={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
  local len=#msg*8
  local padded=msg..string.char(0x80)
  local rem=(#padded+8)%64
  if rem>0 then padded=padded..string.rep(string.char(0),64-rem) end
  padded=padded..string.pack('>I8',len)
  for start=1,#padded,64 do
    local w={}
    for i=0,15 do w[i]=string.unpack('>I4',padded,start+i*4) end
    for i=16,63 do
      local s0=(ror(w[i-15],7)~ror(w[i-15],18)~(w[i-15]>>3))&0xffffffff
      local s1=(ror(w[i-2],17)~ror(w[i-2],19)~(w[i-2]>>10))&0xffffffff
      w[i]=(w[i-16]+s0+w[i-7]+s1)&0xffffffff
    end
    local a,b,c,d,e,f,g,h=h0,h1,h2,h3,h4,h5,h6,h7
    for i=0,63 do
      local S1=(ror(e,6)~ror(e,11)~ror(e,25))&0xffffffff
      local ch=((e&f)~((~e)&g))&0xffffffff
      local t1=(h+S1+ch+k[i+1]+w[i])&0xffffffff
      local S0=(ror(a,2)~ror(a,13)~ror(a,22))&0xffffffff
      local maj=((a&b)~(a&c)~(b&c))&0xffffffff
      local t2=(S0+maj)&0xffffffff
      h=g;g=f;f=e;e=(d+t1)&0xffffffff;d=c;c=b;b=a;a=(t1+t2)&0xffffffff
    end
    h0=(h0+a)&0xffffffff;h1=(h1+b)&0xffffffff;h2=(h2+c)&0xffffffff;h3=(h3+d)&0xffffffff
    h4=(h4+e)&0xffffffff;h5=(h5+f)&0xffffffff;h6=(h6+g)&0xffffffff;h7=(h7+h)&0xffffffff
  end
  return string.format('%08x%08x%08x%08x%08x%08x%08x%08x',h0,h1,h2,h3,h4,h5,h6,h7)
end
M.sha256=sha256
local function canonical_parts(parts)
  local out={}
  for i=1,#parts do
    local v=tostring(parts[i]==nil and U.null or parts[i])
    out[#out+1]=#v..':'..v
  end
  return table.concat(out,'|')
end
local function ref_identity(r)
  return canonical_parts({r.source,r.entity,r.id,r.field,r.value})
end
local function frozen_rule_metadata(rule_id)
  local m=Rules.RULE_METADATA[rule_id]
  return {rule_id=rule_id,category=m.category,severity=m.severity,
    default_confidence=m.default_confidence,precedence=m.precedence,
    required_evidence=U.array(m.required_evidence or {})}
end

local function err(code,message)
  return {code=code,message=message or code}
end
local function str(v)
  if type(v)=='string' and v~='' then return v end
  return nil
end
local function count(v) return type(v)=='table' and #v or 0 end
local function clone_arr(v,limit)
  local out=U.array()
  local n=#(v or {})
  for i=1,math.min(n,limit or 9999) do out[#out+1]=v[i] end
  return out,n>(limit or 9999)
end

local function bound_finding(f)
  local refs,r1=clone_arr(f.evidence_refs,M.MAX_EVIDENCE_REFS)
  local obs,r2=clone_arr(f.observations,M.MAX_OBSERVATIONS)
  local causes,r3=clone_arr(f.likely_causes,M.MAX_CAUSES)
  local steps,r4=clone_arr(f.suggested_next_steps,M.MAX_STEPS)
  local dna,r5=clone_arr(f.do_not_assume,M.MAX_DO_NOT_ASSUME)
  local limits,r6=clone_arr(f.limitations,16)
  return {evidence_refs=refs,observations=obs,likely_causes=causes,
    suggested_next_steps=steps,do_not_assume=dna,limitations=limits,
    truncated=(r1 or r2 or r3 or r4 or r5 or r6)}
end
M._bound_finding=bound_finding

local function validate_input_diff(input)
  if input.diff_version~=1 then return nil,err('unsupported_input','diff_version must be 1') end
  if type(input.a)~='table' or type(input.b)~='table' then return nil,err('invalid_input','snapshot metadata missing') end
  if type(input.comparability)~='table' then return nil,err('invalid_input','comparability missing') end
  local valid_status={comparable=true,partial_comparison=true,different_source=true,
    different_target=true,different_target_build=true,target_build_unknown=true,
    unknown=true,not_comparable=true}
  if not valid_status[input.comparability.status] then
    return nil,err('invalid_input','invalid comparability status')
  end
  if type(input.candidates)~='table' or type(input.coverage)~='table' then
    return nil,err('invalid_input','candidate/coverage evidence missing')
  end
  for _,field in ipairs({'collection','discovery','validation'}) do
    if type(input.coverage[field])~='table' then
      return nil,err('invalid_input','coverage.'..field..' missing')
    end
  end
  for _,k in ipairs({'changed','added','removed','unknown'}) do
    if input.candidates[k]~=nil and type(input.candidates[k])~='table' then
      return nil,err('invalid_input','candidate list is not an array')
    end
    if count(input.candidates[k])>M.MAX_CANDIDATES then return nil,err('input_limit','candidate list too large') end
    for _,c in ipairs(input.candidates[k] or {}) do
      if type(c)~='table' then return nil,err('invalid_input','candidate entry is not a table') end
      if k=='changed' then
        if type(c.key)~='string' or type(c.fields)~='table' then
          return nil,err('invalid_input','changed candidate shape invalid')
        end
        for _,f in ipairs(c.fields) do
          if type(f)~='table' or type(f.field)~='string' then
            return nil,err('invalid_input','changed field shape invalid')
          end
        end
      end
    end
  end
  return true
end

local function build_context(input)
  if type(input)~='table' then return nil,err('invalid_input','input must be a table') end
  if input.diff_version~=nil then
    local ok,e=validate_input_diff(input);if not ok then return nil,e end
    local id=str(input.a.snapshot_id) and str(input.b.snapshot_id)
      and (input.a.snapshot_id..':'..input.b.snapshot_id) or nil
    if not id then return nil,err('invalid_input','snapshot identities missing') end
    return {kind='snapshot_diff',input_id=id,diff=input,
      comparability=input.comparability.status},nil
  end
  if input.snapshot_version~=nil then
    if input.snapshot_version~=1 then return nil,err('unsupported_input','snapshot_version must be 1') end
    local id=str(input.snapshot_id);if not id then return nil,err('invalid_input','snapshot_id missing') end
    if type(input.coverage)~='table' then return nil,err('invalid_input','snapshot coverage missing') end
    local validation=input.coverage and input.coverage.validation
    local collection=input.coverage and input.coverage.collection
    return {kind='snapshot',input_id=id,snapshot=input,
      validation_unavailable=validation and validation.status=='unavailable' or false,
      limit_reached=(collection and collection.status=='limit_reached') or false},nil
  end
  if type(input.mode)=='string' and type(input.coverage)=='table' then
    local suite=str(input.suite_version) or 'unknown'
    return {kind='analysis',input_id='analysis:'..suite..':'..input.mode,
      analysis_coverage=input.coverage,
      validation_unavailable=input.coverage.validation and input.coverage.validation.status=='unavailable' or false,
      limit_reached=input.coverage.collection and input.coverage.collection.status=='limit_reached' or false},nil
  end
  return nil,err('unsupported_input','expected snapshot_diff, snapshot or analysis evidence')
end

local function collect_limitations(ctx)
  local out=U.array()
  local seen={}
  local truncated=false
  local function add(v)
    if type(v)~='string' or v=='' then return end
    if seen[v] then return end
    if #out>=28 then truncated=true;return end
    seen[v]=true;out[#out+1]=v
  end
  if ctx.diff then
    local d=ctx.diff
    for _,s in ipairs({d.a,d.b}) do
      for _,v in ipairs(s.limitations or {}) do add(v) end
    end
    for _,field in ipairs({'collection','discovery','validation'}) do
      local c=d.coverage and d.coverage[field]
      for _,v in ipairs(c and c.limitations or {}) do add(v) end
    end
  elseif ctx.snapshot then
    for _,v in ipairs(ctx.snapshot.limitations or {}) do add(v) end
    for _,field in ipairs({'collection','discovery','validation'}) do
      local c=ctx.snapshot.coverage and ctx.snapshot.coverage[field]
      for _,v in ipairs(c and c.limitations or {}) do add(v) end
    end
  end
  table.sort(out)
  return out,truncated
end

local function build_report(ctx,options,raw_override)
  local raw=raw_override or Rules.evaluate(ctx)
  local findings_truncated=raw.truncated==true
  local fields_truncated=false
  local findings=U.array()
  for _,f in ipairs(raw) do
    local key=f._key or f.code
    local bound=bound_finding(f)
    local refs=bound.evidence_refs
    local ref_keys={}
    for _,r in ipairs(refs) do ref_keys[#ref_keys+1]=ref_identity(r) end
    table.sort(ref_keys)
    local id_parts={'finding',M.RULESET_VERSION,ctx.input_id,f.rule_id,key}
    for _,rk in ipairs(ref_keys) do id_parts[#id_parts+1]=rk end
    local id='advf-'..sha256(canonical_parts(id_parts)):sub(1,32)
    local obs=bound.observations
    local causes=bound.likely_causes
    local steps=bound.suggested_next_steps
    local dna=bound.do_not_assume
    local limits=bound.limitations
    local ftrunc=bound.truncated
    if ftrunc then fields_truncated=true end
    findings[#findings+1]={
      finding_id=id,rule_id=f.rule_id,code=f.code,category=f.category,
      severity=f.severity,status=f.status,confidence=f.confidence,
      precedence=f.precedence or 9,truncated=ftrunc,rule_metadata=frozen_rule_metadata(f.rule_id),
      evidence_refs=refs,observations=obs,interpretation=f.interpretation,
      likely_causes=causes,suggested_next_steps=steps,
      do_not_assume=dna,limitations=limits
    }
    if #findings>=M.MAX_FINDINGS then break end
  end
  local limitations,limits_truncated=collect_limitations(ctx)
  local function add_lim(code)
    for _,v in ipairs(limitations) do if v==code then return end end
    if #limitations>=32 then
      limitations[32]=code
      limits_truncated=true
      return
    end
    limitations[#limitations+1]=code
  end
  if findings_truncated then add_lim('ADVISOR_FINDINGS_CAPPED_AT_64') end
  if fields_truncated then add_lim('ADVISOR_FINDING_FIELDS_CAPPED') end
  if limits_truncated then add_lim('ADVISOR_LIMITATIONS_CAPPED') end
  local truncated=findings_truncated or fields_truncated or limits_truncated
  if truncated then
    add_lim('ADVISOR_CONFIDENCE_DEGRADED_BY_TRUNCATION')
    for _,f in ipairs(findings) do
      if f.confidence=='exact' then f.confidence='strong'
      elseif f.confidence=='strong' then f.confidence='weak' end
    end
  end
  table.sort(limitations)
  local by_sev={INFO=0,LOW=0,MEDIUM=0,HIGH=0,CRITICAL=0}
  local by_cat={}
  for _,f in ipairs(findings) do
    by_sev[f.severity]=(by_sev[f.severity] or 0)+1
    by_cat[f.category]=(by_cat[f.category] or 0)+1
  end
  local cats=U.array()
  local names={}
  for k in pairs(by_cat) do names[#names+1]=k end
  table.sort(names)
  for _,k in ipairs(names) do cats[#cats+1]={category=k,count=by_cat[k]} end
  local highest='INFO'
  for _,s in ipairs({'CRITICAL','HIGH','MEDIUM','LOW','INFO'}) do
    if by_sev[s]>0 then highest=s;break end
  end
  local headline=#findings..' finding(s); highest severity '..highest..'. Evidence only; no automatic change.'
  local id='adv-'..sha256(canonical_parts({'report',M.VERSION,M.RULESET_VERSION,ctx.kind,ctx.input_id})):sub(1,32)
  local comparability=ctx.kind=='snapshot_diff' and (ctx.diff.comparability.status or U.null) or U.null
  return {
    advisor_version=M.VERSION,schema_id=M.SCHEMA_ID,advisor_report_id=id,
    ruleset_version=M.RULESET_VERSION,suite_version=options.suite_version or '0.3.2',
    generated_at=options.generated_at or os.date('!%Y-%m-%dT%H:%M:%SZ'),
    truncated=truncated,
    truncation={findings_capped=findings_truncated,fields_capped=fields_truncated,
      limitations_capped=limits_truncated},
    input={type=ctx.kind,input_id=ctx.input_id,
      snapshot_a=ctx.kind=='snapshot_diff' and (ctx.diff.a.snapshot_id or U.null) or U.null,
      snapshot_b=ctx.kind=='snapshot_diff' and (ctx.diff.b.snapshot_id or U.null) or U.null,
      comparability=comparability},
    findings=findings,limitations=limitations,
    summary={finding_count=#findings,by_severity=by_sev,by_category=cats,headline=headline}
  }
end

local function verr(errors,code,path,message,ref)
  if #errors>=64 then return end
  local e={code=code,path=path,message=message}
  if ref~=nil then e.ref=ref end
  errors[#errors+1]=e
end
local function nullish(v) return v==nil or v==U.null end
local function same_value(a,b)
  if nullish(a) and nullish(b) then return true end
  if nullish(a) or nullish(b) then return false end
  if type(a)~=type(b) then return false end
  if type(a)=='table' then return false end
  return a==b
end
local function canonical_ref(r)
  local function p(v)
    local s=tostring(v==nil and U.null or v)
    return #s..':'..s
  end
  return table.concat({p(r.source),p(r.entity),p(r.id),p(r.field),p(r.value)},'|')
end
local function sensitive_text(v)
  if type(v)~='string' then return false end
  return v:find('\\\\',1,true)~=nil or v:match('[A-Za-z]:\\Users')~=nil
    or v:find('/home/',1,true)~=nil or v:lower():find('appdata',1,true)~=nil
    or v:lower():find('doc_haz',1,true)~=nil
end
local function valid_candidate_id(id)
  if type(id)~='string' then return false end
  if id=='' or #id>1024 then return false end
  if id:find('[%c|]')~=nil then return false end
  return true
end
local function getpath(v,path)
  local cur=v
  for part in tostring(path):gmatch('[^.]+') do
    if type(cur)~='table' then return nil,false end
    cur=cur[part]
    if cur==nil then return nil,false end
  end
  return cur,true
end
local function candidate_by_key(list,id)
  for _,c in ipairs(list or {}) do if type(c)=='table' and tostring(c.key)==tostring(id) then return c end end
end
local function changed_candidate(diff,id)
  for _,c in ipairs(diff.candidates and diff.candidates.changed or {}) do
    if type(c)=='table' and tostring(c.key)==tostring(id) then return c end
  end
end
local function changed_field(c,field)
  for _,f in ipairs(c and c.fields or {}) do if f.field==field then return f end end
end
local function field_for(entity,field,side)
  if entity=='candidate' and field=='validation.state' then return 'validation_state' end
  return field
end
local function resolve_candidate(ctx,source,id,field)
  if nullish(id) then
    if source=='diff' and field=='unknown' then
      local n=#(ctx.diff.candidates and ctx.diff.candidates.unknown or {})
      return n,true
    end
    return nil,false,'MALFORMED_ID'
  end
  if not valid_candidate_id(id) then return nil,false,'MALFORMED_ID' end
  local list,side
  if source=='diff' then
    local c=changed_candidate(ctx.diff,id)
    if c then
      if field=='added' or field=='removed' then return true,true end
      local f=changed_field(c,field_for('candidate',field,'diff'))
      if f then return f.b,true end
      return nil,false,'UNKNOWN_FIELD'
    end
    for _,x in ipairs(ctx.diff.candidates and ctx.diff.candidates.added or {}) do
      if tostring(x.key)==id then if field=='added' then return true,true end;return nil,false,'UNKNOWN_FIELD' end
    end
    for _,x in ipairs(ctx.diff.candidates and ctx.diff.candidates.removed or {}) do
      if tostring(x.key)==id then if field=='removed' then return true,true end;return nil,false,'UNKNOWN_FIELD' end
    end
    return nil,false,'MISSING_CANDIDATE'
  elseif source=='snapshot_a' or source=='snapshot_b' then
    side=source=='snapshot_a' and 'a' or 'b'
    local c=changed_candidate(ctx.diff,id)
    if c then
      local f=changed_field(c,field_for('candidate',field,side))
      if f then return side=='a' and f.a or f.b,true end
      return nil,false,'UNKNOWN_FIELD'
    end
    if ctx.snapshot then
      local cand=candidate_by_key(ctx.snapshot.candidates,id)
      if cand then
        local v,ok=getpath(cand,field)
        if ok then return v,true end
        return nil,false,'UNKNOWN_FIELD'
      end
    end
    return nil,false,'MISSING_CANDIDATE'
  end
  return nil,false,'UNKNOWN_SOURCE'
end
local function resolve_coverage(ctx,source,field)
  local cov=ctx.diff and ctx.diff.coverage or ctx.snapshot and ctx.snapshot.coverage or ctx.analysis_coverage
  if type(cov)~='table' then return nil,false,'MISSING_ENTITY' end
  if field=='validation.status' then
    if ctx.diff then return ctx.diff.coverage.validation.b_status,true end
    return cov.validation and cov.validation.status,true
  end
  if field=='collection.status' then
    if ctx.diff then
      return (ctx.diff.coverage.collection.b_status or ctx.diff.coverage.collection.a_status),true
    end
    return cov.collection and cov.collection.status,true
  end
  local v,ok=getpath(cov,field)
  if ok then return v,true end
  return nil,false,'UNKNOWN_FIELD'
end
local function resolve_entity(ctx,source,entity,id,field)
  if entity=='comparability' then
    if source~='diff' or not ctx.diff then return nil,false,'WRONG_SOURCE' end
    local v,ok=getpath(ctx.diff.comparability,field)
    if ok then return v,true end
    return nil,false,'UNKNOWN_FIELD'
  elseif entity=='coverage' then
    if source=='diff' or source=='snapshot_a' or source=='analysis' then
      return resolve_coverage(ctx,source,field)
    end
    return nil,false,'WRONG_SOURCE'
  elseif entity=='candidate' then
    return resolve_candidate(ctx,source,id,field)
  elseif entity=='module' then
    if source~='diff' or not ctx.diff then return nil,false,'WRONG_SOURCE' end
    if field=='inventory.changed' then return ctx.diff.modules and ctx.diff.modules.changed,true end
    return nil,false,'UNKNOWN_FIELD'
  elseif entity=='dependency' then
    if source~='diff' or not ctx.diff then return nil,false,'WRONG_SOURCE' end
    if field=='changed' then return true,true end
    local v,ok=getpath(ctx.diff.dependencies,field)
    if ok then return v,true end
    return nil,false,'UNKNOWN_FIELD'
  elseif entity=='unresolved' then
    if source~='diff' or not ctx.diff then return nil,false,'WRONG_SOURCE' end
    for _,list in ipairs({ctx.diff.unresolved and ctx.diff.unresolved.added or {},
      ctx.diff.unresolved and ctx.diff.unresolved.removed or {}}) do
      for _,u in ipairs(list) do
        if tostring(u.name)==tostring(id) then
          if field=='added' or field=='removed' then return true,true end
          return nil,false,'UNKNOWN_FIELD'
        end
      end
    end
    return nil,false,'MISSING_CANDIDATE'
  elseif entity=='operation' or entity=='address' then
    return nil,false,'UNSUPPORTED_ENTITY'
  end
  return nil,false,'UNKNOWN_ENTITY'
end
local function referential_errors(report,input)
  local errors=U.array()
  local ctx,ce=build_context(input)
  if not ctx then
    verr(errors,'REFERENTIAL_INPUT_INVALID','input',ce and ce.message or 'invalid input')
    return errors
  end
  if report.input and report.input.input_id~=ctx.input_id then
    verr(errors,'INPUT_ID_MISMATCH','input.input_id','report input does not match supplied input')
  end
  if report.input and report.input.type~=ctx.kind then
    verr(errors,'INPUT_TYPE_MISMATCH','input.type','report type does not match supplied input')
  end
  for i,f in ipairs(report.findings or {}) do
    local seen={}
    for j,r in ipairs(f.evidence_refs or {}) do
      local path='findings['..i..'].evidence_refs['..j..']'
      if type(r)~='table' then
        verr(errors,'MALFORMED_REF',path,'evidence ref is not an object',r)
      else
        local cr=canonical_ref(r)
        if seen[cr] then verr(errors,'DUPLICATE_EVIDENCE_REF',path,'duplicate evidence ref',r) end
        seen[cr]=true
        local allowed_source={}
        if ctx.kind=='snapshot_diff' then allowed_source={diff=true,snapshot_a=true,snapshot_b=true}
        elseif ctx.kind=='snapshot' then allowed_source={snapshot_a=true}
        else allowed_source={analysis=true} end
        local value,ok,code
        if sensitive_text(r.id) or sensitive_text(r.value) then
          ok=false;code='PRIVACY_VIOLATION'
        elseif not allowed_source[r.source] then
          ok=false;code='UNKNOWN_SOURCE'
        else
          value,ok,code=resolve_entity(ctx,r.source,r.entity,r.id,r.field)
        end
        if not ok then
          verr(errors,code or 'INVALID_EVIDENCE_REF',path,
            'cannot resolve '..tostring(r.source)..'/'..tostring(r.entity)..'/'..tostring(r.id)..'/'..tostring(r.field),r)
        elseif not same_value(value,r.value) then
          verr(errors,'EVIDENCE_VALUE_MISMATCH',path,'observed value does not match evidence',r)
        end
      end
    end
  end
  return errors
end

function M.validate_ruleset()
  local errors=U.array()
  local seen={}
  local seen_count=0
  for _,meta in ipairs(Rules.RULES or {}) do
    local id=meta.rule_id
    if seen[id] then verr(errors,'DUPLICATE_RULE','rules',id) end
    if not seen[id] then seen_count=seen_count+1 end
    seen[id]=true
    if not M.CATEGORIES[meta.category] then verr(errors,'INVALID_RULE_CATEGORY','rules.'..id,id) end
    if not ({INFO=true,LOW=true,MEDIUM=true,HIGH=true,CRITICAL=true})[meta.severity] then
      verr(errors,'INVALID_RULE_SEVERITY','rules.'..id,id)
    end
    if not ({exact=true,strong=true,weak=true,unknown=true})[meta.default_confidence] then
      verr(errors,'INVALID_RULE_CONFIDENCE','rules.'..id,id)
    end
    if type(meta.precedence)~='number' or meta.precedence<1 or meta.precedence>9 then
      verr(errors,'INVALID_RULE_PRECEDENCE','rules.'..id,id)
    end
    if type(meta.required_evidence)~='table' or #meta.required_evidence==0 then
      verr(errors,'MISSING_REQUIRED_EVIDENCE','rules.'..id,id)
    end
    if type(meta.suppresses)~='table' then verr(errors,'INVALID_SUPPRESSION','rules.'..id,id) end
    for _,s in ipairs(meta.suppresses or {}) do
      if s~='candidate_causal' and s~='invalid_interpretation' and not Rules.RULE_METADATA[s] then
        verr(errors,'UNKNOWN_SUPPRESSION','rules.'..id,s)
      end
    end
    if type(meta.can_emit_relocation_request)~='boolean' then
      verr(errors,'INVALID_RELOCATION_FLAG','rules.'..id,id)
    end
    local required=Rules.REQUIRED_ASSUMPTIONS[id] or {}
    local have={}
    for _,name in ipairs(meta.mandatory_assumptions or {}) do have[name]=true end
    for _,name in ipairs(required) do
      if not Rules.ASSUMPTIONS[name] or not have[name] then
        verr(errors,'MISSING_DO_NOT_ASSUME','rules.'..id,name)
      end
    end
  end
  if seen_count~=26 then verr(errors,'RULESET_COUNT','rules','expected 26 rules') end
  for k,v in pairs(Rules.ASSUMPTIONS or {}) do
    if type(v)~='string' or v=='' then verr(errors,'INVALID_ASSUMPTION','rules.assumptions.'..k,k) end
  end
  for k in pairs(M.ALLOWED_ACTIONS) do
    if not (Rules.NEXT_STEP_ENUM or {})[k] then verr(errors,'UNKNOWN_NEXT_STEP','rules.next_steps.'..k,k) end
  end
  for k in pairs(Rules.NEXT_STEP_ENUM or {}) do
    if not M.ALLOWED_ACTIONS[k] then verr(errors,'MISSING_NEXT_STEP','rules.next_steps.'..k,k) end
  end
  return #errors==0,errors
end

function M.validate(report,input)
  local errors=U.array()
  local function bad(msg,code,path) verr(errors,code or 'STRUCTURAL',path or 'report',msg) end
  if type(report)~='table' then
    verr(errors,'STRUCTURAL','report','report is not a table')
    return false,errors
  end
  if report.advisor_version~=1 then bad('unsupported advisor_version','UNSUPPORTED_VERSION','advisor_version') end
  if report.schema_id~=M.SCHEMA_ID then bad('invalid schema_id','INVALID_SCHEMA','schema_id') end
  if type(report.advisor_report_id)~='string' or not report.advisor_report_id:match('^adv%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then bad('invalid advisor_report_id','INVALID_ID','advisor_report_id') end
  if report.ruleset_version~=M.RULESET_VERSION then bad('unsupported ruleset_version','UNSUPPORTED_VERSION','ruleset_version') end
  if type(report.generated_at)~='string' then bad('generated_at missing','MISSING_FIELD','generated_at') end
  if type(report.suite_version)~='string' then bad('suite_version missing','MISSING_FIELD','suite_version') end
  if type(report.truncated)~='boolean' then bad('truncated missing','MISSING_FIELD','truncated') end
  if type(report.truncation)~='table' then bad('truncation missing','MISSING_FIELD','truncation') end
  if type(report.truncation)=='table' then
    local tr_allowed={findings_capped=true,fields_capped=true,limitations_capped=true}
    for k in pairs(report.truncation) do if not tr_allowed[k] then bad('unexpected truncation property','UNEXPECTED_PROPERTY','truncation.'..tostring(k)) end end
    for _,k in ipairs({'findings_capped','fields_capped','limitations_capped'}) do
      if type(report.truncation[k])~='boolean' then bad('truncation flag invalid','INVALID_FIELD','truncation.'..k) end
    end
  end
  local top_allowed={advisor_version=true,schema_id=true,advisor_report_id=true,
    ruleset_version=true,suite_version=true,generated_at=true,truncated=true,
    truncation=true,input=true,findings=true,limitations=true,summary=true}
  for k in pairs(report) do if not top_allowed[k] then bad('unexpected top-level property','UNEXPECTED_PROPERTY',tostring(k)) end end
  if type(report.limitations)~='table' or #report.limitations>32 then bad('limitations invalid','BOUNDS','limitations') end
  if type(report.input)~='table' or type(report.input.type)~='string' or type(report.input.input_id)~='string' then
    bad('input metadata invalid','INVALID_INPUT','input')
  elseif not ({snapshot_diff=true,snapshot=true,analysis=true})[report.input.type] then
    bad('input type invalid','INVALID_INPUT','input.type')
  else
    local in_allowed={type=true,input_id=true,snapshot_a=true,snapshot_b=true,comparability=true}
    for k in pairs(report.input) do if not in_allowed[k] then bad('unexpected input property','UNEXPECTED_PROPERTY','input.'..tostring(k)) end end
    for _,k in ipairs({'snapshot_a','snapshot_b','comparability'}) do
      if report.input[k]==nil then bad('input field missing','MISSING_FIELD','input.'..k) end
    end
    for _,k in ipairs({'snapshot_a','snapshot_b'}) do
      if report.input[k]~=nil and report.input[k]~=U.null and type(report.input[k])~='string' then bad('input snapshot id invalid','INVALID_FIELD','input.'..k) end
    end
    if report.input.comparability~=nil and report.input.comparability~=U.null and type(report.input.comparability)~='string' then bad('input comparability invalid','INVALID_FIELD','input.comparability') end
  end
  if type(report.findings)~='table' then bad('findings missing','MISSING_FIELD','findings');return #errors==0,errors end
  if #report.findings>M.MAX_FINDINGS then bad('too many findings','BOUNDS','findings') end
  local seen={}
  for i,f in ipairs(report.findings) do
    local p='findings['..i..']'
    if type(f)~='table' then bad('not a table','STRUCTURAL',p)
    else
      local f_allowed={finding_id=true,rule_id=true,code=true,category=true,severity=true,
        status=true,confidence=true,precedence=true,truncated=true,rule_metadata=true,evidence_refs=true,
        observations=true,interpretation=true,likely_causes=true,suggested_next_steps=true,
        do_not_assume=true,limitations=true}
      for k in pairs(f) do if not f_allowed[k] then bad('unexpected finding property','UNEXPECTED_PROPERTY',p..'.'..tostring(k)) end end
      if type(f.finding_id)~='string' or not f.finding_id:match('^advf%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then bad('invalid finding_id','INVALID_ID',p..'.finding_id') end
      if seen[f.finding_id] then bad('duplicate finding_id','DUPLICATE_ID',p..'.finding_id') end;seen[f.finding_id]=true
      if type(f.rule_id)~='string' or f.rule_id=='' then bad('rule_id missing','MISSING_FIELD',p..'.rule_id') end
      if type(f.code)~='string' or f.code=='' then bad('code missing','MISSING_FIELD',p..'.code') end
      if not M.CATEGORIES[f.category] then bad('unknown category','INVALID_CATEGORY',p..'.category') end
      if not ({INFO=true,LOW=true,MEDIUM=true,HIGH=true,CRITICAL=true})[f.severity] then bad('invalid severity','INVALID_SEVERITY',p..'.severity') end
      if not ({observed=true,unknown=true,not_comparable=true,insufficient_evidence=true})[f.status] then bad('invalid status','INVALID_STATUS',p..'.status') end
      if not ({exact=true,strong=true,weak=true,unknown=true})[f.confidence] then bad('invalid confidence','INVALID_CONFIDENCE',p..'.confidence') end
      if f.truncated~=nil and type(f.truncated)~='boolean' then bad('invalid truncated','INVALID_FIELD',p..'.truncated') end
      if f.precedence~=nil and (type(f.precedence)~='number' or f.precedence~=math.floor(f.precedence) or f.precedence<1 or f.precedence>9) then bad('invalid precedence','INVALID_FIELD',p..'.precedence') end
      if type(f.rule_metadata)~='table' then bad('rule metadata missing','MISSING_FIELD',p..'.rule_metadata')
      else
        local rm_allowed={rule_id=true,category=true,severity=true,default_confidence=true,precedence=true,required_evidence=true}
        for k in pairs(f.rule_metadata) do if not rm_allowed[k] then bad('unexpected rule metadata property','UNEXPECTED_PROPERTY',p..'.rule_metadata.'..tostring(k)) end end
        for _,k in ipairs({'rule_id','category','severity','default_confidence','precedence','required_evidence'}) do
          if f.rule_metadata[k]==nil then bad('rule metadata incomplete','MISSING_FIELD',p..'.rule_metadata.'..k) end
        end
        if type(f.rule_metadata.rule_id)~='string' or type(f.rule_metadata.category)~='string' then bad('rule metadata type invalid','INVALID_FIELD',p..'.rule_metadata') end
        if not ({INFO=true,LOW=true,MEDIUM=true,HIGH=true,CRITICAL=true})[f.rule_metadata.severity] then bad('rule severity invalid','INVALID_FIELD',p..'.rule_metadata.severity') end
        if not ({exact=true,strong=true,weak=true,unknown=true})[f.rule_metadata.default_confidence] then bad('rule confidence invalid','INVALID_FIELD',p..'.rule_metadata.default_confidence') end
        if type(f.rule_metadata.precedence)~='number' or f.rule_metadata.precedence<1 or f.rule_metadata.precedence>9 then bad('rule precedence invalid','INVALID_FIELD',p..'.rule_metadata.precedence') end
        if type(f.rule_metadata.required_evidence)~='table' then bad('rule evidence invalid','INVALID_FIELD',p..'.rule_metadata.required_evidence')
        else for _,v in ipairs(f.rule_metadata.required_evidence) do if type(v)~='string' then bad('rule evidence entry invalid','INVALID_FIELD',p..'.rule_metadata.required_evidence') end end end
      end
      if type(f.evidence_refs)~='table' or #f.evidence_refs==0 then bad('evidence_refs required','MISSING_FIELD',p..'.evidence_refs') end
      if #(f.evidence_refs or {})>M.MAX_EVIDENCE_REFS then bad('too many evidence_refs','BOUNDS',p..'.evidence_refs') end
      local refseen={}
      for _,r in ipairs(f.evidence_refs or {}) do
        if type(r)=='table' then
          local r_allowed={source=true,entity=true,id=true,field=true,value=true}
          for k in pairs(r) do if not r_allowed[k] then bad('unexpected evidence-ref property','UNEXPECTED_PROPERTY',p..'.evidence_refs') end end
        end
        if type(r)~='table' or type(r.source)~='string' or type(r.entity)~='string' or type(r.field)~='string' then
          bad('invalid evidence ref','MALFORMED_REF',p..'.evidence_refs')
        elseif not M.SOURCES[r.source] or not M.ENTITIES[r.entity] then
          bad('invalid evidence source/entity','MALFORMED_REF',p..'.evidence_refs')
        elseif r.id~=nil and r.id~=U.null and type(r.id)~='string' then
          bad('invalid evidence id type','MALFORMED_REF',p..'.evidence_refs')
        elseif r.value~=nil and r.value~=U.null and not ({string=true,number=true,boolean=true})[type(r.value)] then
          bad('invalid evidence value type','MALFORMED_REF',p..'.evidence_refs')
        else
          local cr=canonical_ref(r)
          if sensitive_text(r.id) or sensitive_text(r.value) then
            bad('privacy-sensitive evidence ref','PRIVACY_VIOLATION',p..'.evidence_refs')
          end
          if refseen[cr] then bad('duplicate evidence ref','DUPLICATE_EVIDENCE_REF',p..'.evidence_refs') end
          refseen[cr]=true
        end
      end
      if type(f.observations)~='table' or #f.observations==0 then bad('observations required','MISSING_FIELD',p..'.observations') end
      if #(f.observations or {})>M.MAX_OBSERVATIONS then bad('too many observations','BOUNDS',p..'.observations') end
      for _,v in ipairs(f.observations or {}) do if type(v)~='string' then bad('observation entry invalid','INVALID_FIELD',p..'.observations') end end
      if type(f.interpretation)~='string' then bad('interpretation missing','MISSING_FIELD',p..'.interpretation') end
      for _,v in ipairs(f.observations or {}) do
        if sensitive_text(v) then bad('privacy-sensitive observation','PRIVACY_VIOLATION',p..'.observations') end
      end
      for _,v in ipairs(f.likely_causes or {}) do
        if sensitive_text(v) then bad('privacy-sensitive cause','PRIVACY_VIOLATION',p..'.likely_causes') end
      end
      for _,v in ipairs(f.do_not_assume or {}) do
        if sensitive_text(v) then bad('privacy-sensitive assumption','PRIVACY_VIOLATION',p..'.do_not_assume') end
      end
      if #(f.likely_causes or {})>M.MAX_CAUSES then bad('too many causes','BOUNDS',p..'.likely_causes') end
      for _,v in ipairs(f.likely_causes or {}) do if type(v)~='string' then bad('cause entry invalid','INVALID_FIELD',p..'.likely_causes') end end
      if type(f.suggested_next_steps)~='table' or #f.suggested_next_steps>M.MAX_STEPS then bad('next steps invalid','BOUNDS',p..'.suggested_next_steps') end
      for _,s in ipairs(f.suggested_next_steps or {}) do
        if type(s)~='table' then bad('next step invalid','INVALID_FIELD',p..'.suggested_next_steps')
        else
          for k in pairs(s) do if k~='action' and k~='detail' and k~='requires_user_approval' then
            bad('unexpected next-step property','UNEXPECTED_PROPERTY',p..'.suggested_next_steps')
          end end
        end
        if type(s)~='table' or not M.ALLOWED_ACTIONS[s.action] then bad('forbidden next step','FORBIDDEN_ACTION',p..'.suggested_next_steps') end
        if type(s.detail)~='string' or s.detail=='' then bad('next step detail missing','MISSING_FIELD',p..'.suggested_next_steps') end
      end
      if type(f.do_not_assume)~='table' or #f.do_not_assume==0 then bad('do_not_assume required','MISSING_FIELD',p..'.do_not_assume') end
      if #(f.do_not_assume or {})>M.MAX_DO_NOT_ASSUME then bad('too many do_not_assume','BOUNDS',p..'.do_not_assume') end
      for _,v in ipairs(f.do_not_assume or {}) do if type(v)~='string' then bad('assumption entry invalid','INVALID_FIELD',p..'.do_not_assume') end end
      if #(f.limitations or {})>16 then bad('too many finding limitations','BOUNDS',p..'.limitations') end
    end
  end
  if type(report.summary)~='table' or type(report.summary.finding_count)~='number' or report.summary.finding_count~=math.floor(report.summary.finding_count) or report.summary.finding_count~=#report.findings then
    bad('summary count mismatch','SUMMARY_MISMATCH','summary.finding_count')
  else
    local s_allowed={finding_count=true,by_severity=true,by_category=true,headline=true}
    for k in pairs(report.summary) do if not s_allowed[k] then bad('unexpected summary property','UNEXPECTED_PROPERTY','summary.'..tostring(k)) end end
    if type(report.summary.by_severity)~='table' then bad('summary severity missing','MISSING_FIELD','summary.by_severity')
    else for _,k in ipairs({'INFO','LOW','MEDIUM','HIGH','CRITICAL'}) do
      if type(report.summary.by_severity[k])~='number' or report.summary.by_severity[k]~=math.floor(report.summary.by_severity[k]) then bad('summary severity invalid','INVALID_FIELD','summary.by_severity.'..k) end
    end end
    if type(report.summary.by_category)~='table' then bad('summary category missing','MISSING_FIELD','summary.by_category')
    else for _,c in ipairs(report.summary.by_category) do
      if type(c)~='table' or not M.CATEGORIES[c.category] or type(c.count)~='number' or c.count~=math.floor(c.count) then bad('summary category invalid','INVALID_FIELD','summary.by_category') end
    end end
    if type(report.summary.headline)~='string' then bad('summary headline missing','MISSING_FIELD','summary.headline') end
  end
  for _,v in ipairs(report.limitations or {}) do
    if type(v)~='string' then bad('limitations entry invalid','INVALID_FIELD','limitations') end
  end
  if type(report.truncation)=='table' then
    if report.truncation.findings_capped and not (function()
      for _,v in ipairs(report.limitations or {}) do if v=='ADVISOR_FINDINGS_CAPPED_AT_64' then return true end end
    end)() then bad('missing findings truncation limitation','TRUNCATION_SIGNAL','limitations') end
  end
  if input~=nil then
    for _,e in ipairs(referential_errors(report,input)) do errors[#errors+1]=e end
  end
  return #errors==0,errors
end

function M._debug_report(input,raw,options)
  local ctx,e=build_context(input)
  if not ctx then return nil,e end
  options=options or {}
  local built,report=pcall(build_report,ctx,options,raw)
  if not built then return nil,{code='advisor_unavailable',message=tostring(report)} end
  return report
end

function M.analyze(input,options)
  options=options or {}
  local ctx,e=build_context(input)
  if not ctx then return nil,err(e.code,e.message) end
  if options.ruleset_version~=nil and options.ruleset_version~=M.RULESET_VERSION then
    return nil,err('unsupported_ruleset','ruleset version is not supported')
  end
  if options.advisor_version~=nil and options.advisor_version~=M.VERSION then
    return nil,err('unsupported_advisor','advisor version is not supported')
  end
  local rok,rerrs=M.validate_ruleset()
  if not rok then return nil,{code='advisor_unavailable',message='ruleset metadata invalid',errors=rerrs} end
  local built,report=pcall(build_report,ctx,options)
  if not built then
    return nil,{code='advisor_unavailable',message='advisor evaluation failed closed',detail=tostring(report)}
  end
  local ok,errors=M.validate(report)
  if not ok then return nil,{code='advisor_unavailable',message='generated report failed validation',errors=errors} end
  return report
end

function M.summary(report)
  if type(report)~='table' then return 'advisor unavailable' end
  local s=report.summary or {}
  local counts=s.by_severity or {}
  return string.format('Evidence Advisor %d: %d finding(s); HIGH %d, MEDIUM %d, LOW %d, INFO %d. Evidence only; no automatic change.',
    report.ruleset_version or 0,s.finding_count or 0,counts.HIGH or 0,counts.MEDIUM or 0,counts.LOW or 0,counts.INFO or 0)
end

function M.explain(report,finding_id)
  if type(report)~='table' or type(report.findings)~='table' then return nil,err('invalid_report') end
  for _,f in ipairs(report.findings) do
    if f.finding_id==finding_id then
      return {finding=f,rule_id=f.rule_id,rule_metadata=f.rule_metadata,
        matched_evidence=f.evidence_refs,limitations=f.limitations,
        explanation='Rule '..f.rule_id..' matched because the cited evidence fields changed or remained unknown.'}
    end
  end
  return nil,err('finding_not_found')
end

return M
