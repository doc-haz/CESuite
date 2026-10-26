-- Neutral evidence comparison. Classifications are evidence states, not verdicts.
local U=require('util')
local M={}

local function arr(v) return U.array(v or {}) end
local function n(v) return v==nil and U.null or v end

local function field_diff(fields,name,a,b)
  local av,bv=n(a),n(b)
  local same
  if type(av)=='table' or type(bv)=='table' then
    same=tostring(av)==tostring(bv)
  else
    same=av==bv
  end
  if not same then
    fields[#fields+1]={field=name,a=av,b=bv}
    return true
  end
  return false
end

local function section(fields,a,b)
  local out={changed=false,fields=U.array()}
  for _,name in ipairs(fields) do
    if field_diff(out.fields,name,a and a[name],b and b[name]) then out.changed=true end
  end
  return out
end

local function coverage_section(fields,a,b)
  local out=section(fields,a,b)
  out.a_status=a and a.status or U.null
  out.b_status=b and b.status or U.null
  return out
end

local function metadata(s)
  return {snapshot_id=s.snapshot_id or U.null,created_at=s.created_at or U.null,
    suite_version=s.suite_version or U.null}
end

local function has_strong(snapshot)
  for _,c in ipairs(snapshot.candidates or {}) do
    if c.identity and c.identity.strong==true then return true end
  end
  return false
end

local function comparability(a,b)
  local sa,sb=a.source or {},b.source or {}
  local ta,tb=a.target or {},b.target or {}
  local afp,bfp=sa.fingerprint~=U.null and sa.fingerprint or nil,
    sb.fingerprint~=U.null and sb.fingerprint or nil
  local same_source=afp~=nil and bfp~=nil and afp==bfp
  local source_changed=afp~=nil and bfp~=nil and afp~=bfp
  local source_unknown=afp==nil or bfp==nil
  local an,bn=ta.process_name~=U.null and ta.process_name or nil,
    tb.process_name~=U.null and tb.process_name or nil
  local different_target=(an~=nil and bn~=nil and an~=bn) or (ta.attached~=tb.attached)
  local both_build_known=(ta.build_fingerprint_known==true and tb.build_fingerprint_known==true
    and ta.fingerprint~=U.null and tb.fingerprint~=U.null)
  local same_target_build=false
  local different_target_build=false
  local target_build_unknown=false
  if not different_target then
    if both_build_known and ta.fingerprint==tb.fingerprint then
      same_target_build=true
    elseif both_build_known then
      different_target_build=true
    else
      target_build_unknown=true
    end
  end
  local status
  if a.snapshot_version~=1 or b.snapshot_version~=1 then
    status='not_comparable'
  elseif different_target then
    status='different_target'
  elseif different_target_build then
    status='different_target_build'
  elseif source_changed then
    status='partial_comparison'
  elseif source_unknown then
    status='unknown'
  elseif same_target_build then
    status='comparable'
  else
    status='partial_comparison'
  end
  local strong_identity_only=source_changed
  local candidate_comparable=(same_source or (source_changed and has_strong(a) and has_strong(b)))
  local reasons=U.array()
  if source_unknown then reasons[#reasons+1]='A source fingerprint is unavailable.' end
  if source_changed then
    reasons[#reasons+1]='Source fingerprints differ; only strong-identity candidates are compared.'
  end
  if different_target then reasons[#reasons+1]='Targets differ; validation states are not directly comparable.' end
  if different_target_build then
    reasons[#reasons+1]='Different known target build fingerprints; validation is only contextual.'
  end
  if target_build_unknown and not different_target then
    reasons[#reasons+1]='Target build fingerprint is unavailable or incomplete.'
  end
  if status=='partial_comparison' then
    reasons[#reasons+1]='Comparison is partial; no semantic equivalence is claimed.'
  end
  return {
    status=status,same_source=same_source,source_changed=source_changed,
    source_unknown=source_unknown,same_target_build=same_target_build,
    different_target_build=different_target_build,
    target_build_unknown=target_build_unknown,different_target=different_target,
    partial_comparison=(status=='partial_comparison' or status=='different_target'
      or status=='different_target_build'),
    candidate_comparable=candidate_comparable,strong_identity_only=strong_identity_only,
    reasons=reasons
  }
end

local function candidate_key(c)
  local k=c.identity and c.identity.key
  if k==nil or k==U.null then return nil end
  return tostring(k)
end

local function candidate_summary(c)
  return {key=candidate_key(c) or U.null,symbol=c.symbol or U.null,kind=c.kind or U.null,
    validation=c.validation and c.validation.state or 'unknown'}
end

local function compare_candidates(a,b,comparable,strong_identity_only)
  local out={status='comparable',added=U.array(),removed=U.array(),changed=U.array(),
    unknown=U.array(),unchanged=0}
  if not comparable then
    out.status='not_comparable'
    if strong_identity_only then
      for _,c in ipairs(a.candidates or {}) do
        out.unknown[#out.unknown+1]={side='a',reason='weak_or_missing_identity',status='not_comparable'}
      end
      for _,c in ipairs(b.candidates or {}) do
        out.unknown[#out.unknown+1]={side='b',reason='weak_or_missing_identity',status='not_comparable'}
      end
    end
    return out
  end
  local function usable(c)
    if not strong_identity_only then return true end
    return c.identity and c.identity.strong==true
  end
  local amap,bmap={},{}
  local aunknown,bunknown=0,0
  for _,c in ipairs(a.candidates or {}) do
    local k=candidate_key(c)
    if not k or not usable(c) then aunknown=aunknown+1
    else amap[k]=c end
  end
  for _,c in ipairs(b.candidates or {}) do
    local k=candidate_key(c)
    if not k or not usable(c) then bunknown=bunknown+1
    else bmap[k]=c end
  end
  local akeys={}
  for k in pairs(amap) do akeys[#akeys+1]=k end
  table.sort(akeys)
  for _,k in ipairs(akeys) do
    local ac=amap[k]
    local bc=bmap[k]
    if not bc then
      out.removed[#out.removed+1]=candidate_summary(ac)
    else
      local fields=U.array()
      local changed_flags={}
      local function add(name,av,bv)
        if n(av)~=n(bv) then
          fields[#fields+1]={field=name,a=n(av),b=n(bv)}
          changed_flags[name]=true
        end
      end
      add('pattern',ac.pattern,bc.pattern)
      add('kind',ac.kind,bc.kind)
      add('consumer',ac.consumer,bc.consumer)
      add('provider',ac.provider,bc.provider)
      add('helper',ac.helper,bc.helper)
      add('validation_state',ac.validation and ac.validation.state,
        bc.validation and bc.validation.state)
      add('runtime_validated',ac.runtime_validated,bc.runtime_validated)
      local ap,bp={},{}
      for _,v in ipairs(ac.provenance and ac.provenance.kinds or {}) do ap[#ap+1]=v end
      for _,v in ipairs(bc.provenance and bc.provenance.kinds or {}) do bp[#bp+1]=v end
      add('provenance',table.concat(ap,','),table.concat(bp,','))
      add('condition',ac.condition and ac.condition.text, bc.condition and bc.condition.text)
      if #fields>0 then
        out.changed[#out.changed+1]={key=k,symbol=ac.symbol or U.null,status='changed',
          changed=changed_flags,fields=fields,a=candidate_summary(ac),b=candidate_summary(bc)}
      else
        out.unchanged=out.unchanged+1
      end
    end
  end
  local bkeys={}
  for k in pairs(bmap) do bkeys[#bkeys+1]=k end
  table.sort(bkeys)
  for _,k in ipairs(bkeys) do
    if not amap[k] then out.added[#out.added+1]=candidate_summary(bmap[k]) end
  end
  for i=1,aunknown do out.unknown[#out.unknown+1]={side='a',reason='weak_or_missing_identity',status='not_comparable'} end
  for i=1,bunknown do out.unknown[#out.unknown+1]={side='b',reason='weak_or_missing_identity',status='not_comparable'} end
  local compared=#out.added+#out.removed+#out.changed+out.unchanged
  if strong_identity_only and compared==0 then out.status='not_comparable'
  elseif #out.unknown>0 or strong_identity_only then out.status='partial' end
  return out
end

local function dep_key(d) return tostring(d.name or '')..'\0'..tostring(d.relation or '')..'\0'..tostring(d.scope or '') end

local function compare_dependencies(a,b)
  local out={added=U.array(),removed=U.array(),changed=U.array()}
  local amap,bmap={},{}
  for _,d in ipairs(a.dependencies or {}) do amap[dep_key(d)]=d end
  for _,d in ipairs(b.dependencies or {}) do bmap[dep_key(d)]=d end
  local keys={}
  for k in pairs(amap) do keys[#keys+1]=k end
  for k in pairs(bmap) do if not amap[k] then keys[#keys+1]=k end end
  table.sort(keys)
  for _,k in ipairs(keys) do
    local ad,bd=amap[k],bmap[k]
    if not bd then out.removed[#out.removed+1]={name=ad.name,relation=ad.relation,scope=ad.scope,count=ad.count}
    elseif not ad then out.added[#out.added+1]={name=bd.name,relation=bd.relation,scope=bd.scope,count=bd.count}
    elseif n(ad.count)~=n(bd.count) then
      out.changed[#out.changed+1]={name=ad.name,relation=ad.relation,scope=ad.scope,a=ad.count,b=bd.count}
    end
  end
  return out
end

local function unresolved_key(u) return tostring(u.code or '')..'\0'..tostring(u.name or '')..'\0'..tostring(u.source_script or '')..'\0'..tostring(u.source_line or '') end

local function compare_unresolved(a,b)
  local out={added=U.array(),removed=U.array()}
  local amap,bmap={},{}
  for _,u in ipairs(a.unresolved or {}) do amap[unresolved_key(u)]=u end
  for _,u in ipairs(b.unresolved or {}) do bmap[unresolved_key(u)]=u end
  local keys={}
  for k in pairs(amap) do keys[#keys+1]=k end
  for k in pairs(bmap) do if not amap[k] then keys[#keys+1]=k end end
  table.sort(keys)
  for _,k in ipairs(keys) do
    if not bmap[k] then out.removed[#out.removed+1]=amap[k]
    elseif not amap[k] then out.added[#out.added+1]=bmap[k] end
  end
  return out
end

function M.compare(a,b)
  assert(type(a)=='table' and type(b)=='table','two snapshots required')
  local c=comparability(a,b)
  local cov={
    collection=coverage_section({'status','complete','units_discovered','units_processed','universe_known','percentage'},a.coverage and a.coverage.collection,b.coverage and b.coverage.collection),
    discovery=coverage_section({'status','complete','entities_discovered','patterns_discovered','candidates','linked','unresolved','unsupported','universe_known','percentage'},a.coverage and a.coverage.discovery,b.coverage and b.coverage.discovery),
    validation=coverage_section({'status','complete','candidates','attempted','validated','unique','ambiguous','no_match','error','unavailable','unsupported','unresolved','universe_known','percentage'},a.coverage and a.coverage.validation,b.coverage and b.coverage.validation)
  }
  local candidates=compare_candidates(a,b,c.candidate_comparable,c.strong_identity_only)
  local dependencies=compare_dependencies(a,b)
  local unresolved=compare_unresolved(a,b)
  local notes=U.array()
  for _,r in ipairs(c.reasons) do notes[#notes+1]=r end
  if not c.candidate_comparable then notes[#notes+1]='Candidate comparison is not attempted because identity is not comparable.' end
  if c.strong_identity_only then notes[#notes+1]='Only strong-identity candidates are compared across changed source.' end
  if a.operation and b.operation then
    if a.operation.status~=b.operation.status then
      notes[#notes+1]='Operation status changed; this is context, not a table verdict.'
    end
    if a.operation.source_complete~=b.operation.source_complete then
      notes[#notes+1]='Operation source completeness changed; this is context, not a table verdict.'
    end
  end
  return {
    diff_version=1,a=metadata(a),b=metadata(b),comparability=c,
    coverage=cov,candidates=candidates,dependencies=dependencies,unresolved=unresolved,
    modules={a=a.modules and a.modules.main_module or U.null,
      b=b.modules and b.modules.main_module or U.null,
      changed=(a.modules and a.modules.inventory_fingerprint)~=(b.modules and b.modules.inventory_fingerprint)},
    operation={a=a.operation and a.operation.status or U.null,
      b=b.operation and b.operation.status or U.null,
      source_complete_a=a.operation and a.operation.source_complete,
      source_complete_b=b.operation and b.operation.source_complete},
    notes=notes
  }
end

return M
