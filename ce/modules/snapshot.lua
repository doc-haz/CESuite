-- Evidence snapshot v1: observed evidence, not truth. Pure: no UI, IO or execution.
local U=require('util')
local E=require('exporter')
local Json=require('json')
local M={}

M.VERSION=1
M.MAX_CANDIDATES=2000
M.MAX_DEPENDENCIES=500
M.MAX_UNRESOLVED=200
M.MAX_LIMITATIONS=200
M.MAX_USER_LIMITATIONS=195
M.MAX_ADDRESS_EVIDENCE=64
M.MAX_BYTES=8*1024*1024

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

local function arr(v) return U.array(v or {}) end
local function isnum(v) return type(v)=='number' and v==v and math.abs(v)~=math.huge end
local function int_or_null(v)
  if isnum(v) and v>=0 and v==math.floor(v) then return math.floor(v) end
  return U.null
end
local function num_or_null(v) if isnum(v) then return v end;return U.null end
local function int_zero(v) local n=int_or_null(v);return type(n)=='number' and n or 0 end
local function str_or_null(v) if type(v)=='string' and v~='' then return v end;return U.null end
local function basename(v)
  if type(v)~='string' then return v end
  return (v:gsub('^.*[\\/]',''))
end
local function norm_text(v)
  if type(v)~='string' then return '' end
  return (v:gsub('\r\n','\n'):gsub('\r','\n'))
end
local function norm_pattern(v)
  if type(v)~='string' then return U.null end
  local s=v:lower():gsub('%s+',''):gsub('%?%?','xx')
  if s=='' then return U.null end
  return s
end
local function unique_sorted(t)
  local seen,out={},U.array()
  for _,v in ipairs(t or {}) do
    if type(v)=='string' and not seen[v] then seen[v]=true;out[#out+1]=v end
  end
  table.sort(out)
  return out
end

local function sanitize(s,redactions)
  if type(s)~='string' then return s end
  local out=s
  local patterns={
    {'[A-Za-z]:[\\/][^%s"\']+','local_path'},
    {'\\\\[^%s"\']+','unc_path'},
    {'/home/[^%s]+','home_path'},
    {'/Users/[^%s]+','users_path'},
    {'[Tt]emp[\\/][^%s"\']+','temp_path'}
  }
  for _,p in ipairs(patterns) do
    local changed
    out,changed=out:gsub(p[1],'<redacted-path>')
    if changed>0 then redactions[p[2]]=true end
  end
  return out
end

local function sanitize_provider(v,redactions)
  if type(v)~='string' or v=='' then return U.null end
  local raw=v
  local out
  if raw:find('[\\/]') then
    out=basename(raw:gsub('\\','/'))
    redactions.provider_path=true
  else
    out=sanitize(raw,redactions)
  end
  return (type(out)=='string' and out~='') and out or U.null
end

local function sanitize_helper(v,redactions)
  if type(v)~='string' or v=='' then return U.null end
  local raw=v
  local out
  if raw:match('^%a:') or raw:match('^[\\/]') or raw:find('[Uu]sers[\\/]')
    or raw:find('home[\\/]') or raw:find('[Tt]emp[\\/]') then
    out=basename(raw:gsub('\\','/'))
    redactions.helper_path=true
  else
    out=sanitize(raw,redactions)
    out=out:gsub('\\','/'):gsub('^%a:/+',''):gsub('^/+','')
  end
  return (type(out)=='string' and out~='') and out or U.null
end

local function clean_list(list,redactions,max)
  local out=U.array()
  for _,v in ipairs(list or {}) do
    if #out>=max then break end
    if type(v)=='string' then out[#out+1]=sanitize(v,redactions) end
  end
  return out
end

local function coverage_default(status)
  return {status=status or 'unknown',complete=false}
end
local function copy_collection(c,redactions)
  c=c or {}
  return {
    status=c.status or 'unknown',complete=c.complete==true,
    units_discovered=int_zero(c.units_discovered),
    units_processed=int_zero(c.units_processed),
    universe_known=c.universe_known==true,
    denominator=c.denominator or 'captured_units',
    percentage=num_or_null(c.percentage),
    limitations=clean_list(c.limitations,redactions,200)
  }
end
local function copy_discovery(c,redactions)
  c=c or {}
  return {
    status=c.status or 'unknown',complete=c.complete==true,
    entities_discovered=int_zero(c.entities_discovered),
    patterns_discovered=int_zero(c.patterns_discovered),
    patterns_literal=int_zero(c.patterns_literal),
    patterns_derived=int_zero(c.patterns_derived),
    patterns_conditional=int_zero(c.patterns_conditional),
    patterns_symbol_only=int_zero(c.patterns_symbol_only),
    candidates=int_zero(c.candidates),
    linked=int_zero(c.linked),
    unresolved=int_zero(c.unresolved),
    unsupported=int_zero(c.unsupported),
    universe_known=c.universe_known==true,
    denominator=c.denominator or 'discovered_entities',
    percentage=num_or_null(c.percentage),
    limitations=clean_list(c.limitations,redactions,200)
  }
end
local function copy_validation(c,redactions)
  c=c or {}
  return {
    status=c.status or 'unknown',complete=c.complete==true,
    candidates=int_zero(c.candidates),
    attempted=int_zero(c.runtime_attempted~=nil and c.runtime_attempted or c.attempted),
    validated=int_zero(c.runtime_validated~=nil and c.runtime_validated or c.validated),
    unique=int_zero(c.runtime_unique~=nil and c.runtime_unique or c.unique),
    ambiguous=int_zero(c.runtime_ambiguous~=nil and c.runtime_ambiguous or c.ambiguous),
    no_match=int_zero(c.runtime_no_match~=nil and c.runtime_no_match or c.no_match),
    error=int_zero(c.runtime_error~=nil and c.runtime_error or c.error),
    unavailable=int_zero(c.runtime_unavailable~=nil and c.runtime_unavailable or c.unavailable),
    unsupported=int_zero(c.unsupported),
    unresolved=int_zero(c.unresolved),
    universe_known=c.universe_known==true,
    denominator=c.denominator or 'validation_candidates',
    percentage=num_or_null(c.percentage),
    limitations=clean_list(c.limitations,redactions,200)
  }
end

local function aob_state(a)
  if a.status=='observed' then
    if a.match_count==1 and a.uniqueness=='unique_current_scan' then return 'unique',true end
    if (isnum(a.match_count) and a.match_count>1) or a.uniqueness=='multiple_matches' then return 'ambiguous',true end
    if a.match_count==0 or a.uniqueness=='no_match' then return 'no_match',true end
    return 'unknown',true
  elseif a.status=='error' then return 'error',true
  elseif a.status=='invalidated' or a.status=='unavailable' then return 'unavailable',true
  elseif a.status=='unsupported' then return 'unsupported',false
  elseif a.status=='unresolved' then return 'unresolved',false end
  return 'unknown',false
end

local function ident_seg(v)
  v=tostring(v or '')
  return tostring(#v)..':'..v
end

local function build_candidates(report,redactions,options)
  local source=report.dynamic_analysis and report.dynamic_analysis.patterns or report.observations or {}
  local aobs={}
  for _,a in ipairs(report.aobs or {}) do
    local p=norm_pattern(a.pattern or a.normalized_pattern)
    if p~=U.null then
      local state,attempted=aob_state(a)
      local rank={unique=5,ambiguous=4,no_match=3,error=2,unavailable=1,unknown=0}
      if not aobs[p] or (rank[state] or 0)>(rank[aobs[p].state] or 0) then
        aobs[p]={state=state,attempted=attempted}
      end
    end
  end
  local list={}
  for _,c in ipairs(source) do
    local kind=c.kind
    if kind~='literal_pattern' and kind~='derived_pattern' then
      -- symbol-only and conditional rows are evidence, not candidates
    else
    local symbol=str_or_null(c.symbol)
    local kind=c.kind or 'unknown'
    local script=c.source_script or ''
    local line=isnum(c.source_line) and math.floor(c.source_line) or nil
    local consumer=c.consumer or ''
    local pattern=norm_pattern(c.pattern)
    local derivation=c.derivation or {}
    local provider=sanitize_provider(c.provider or derivation.source_file,redactions)
    local helper=sanitize_helper(derivation.path,redactions)
    local cond=U.null
    if type(c.condition)=='table' then
      local deps=U.array();local depseen={}
      for _,dep in ipairs(c.condition.dependencies or {}) do
        local clean=sanitize(tostring(dep),redactions)
        if clean~='' and not depseen[clean] then depseen[clean]=true;deps[#deps+1]=clean end
      end
      table.sort(deps)
      cond={kind=c.condition.kind or 'conditional_expression',
        text=sanitize(c.condition.text or '',redactions),
        dependencies=deps,
        resolution=c.condition.resolution or 'unknown',
        fallback=str_or_null(c.condition.fallback)}
    end
    local kinds,seen=U.array(),{}
    for _,p in ipairs(c.provenance or {}) do
      if type(p.kind)=='string' and not seen[p.kind] then seen[p.kind]=true;kinds[#kinds+1]=p.kind end
    end
    table.sort(kinds)
    local state,attempted
    if aobs[pattern] then state,attempted=aobs[pattern].state,aobs[pattern].attempted
    elseif c.status=='unresolved' then state,attempted='unresolved',false
    elseif c.status=='unsupported' then state,attempted='unsupported',false
    else state,attempted='not_attempted',false end
    local base
    local strong=(symbol~=U.null and script~='' and consumer~='' and kind~='')
    if symbol~=U.null then
      base=ident_seg(script)..ident_seg(consumer)..ident_seg(kind)..ident_seg(symbol)
    elseif line then
      base=ident_seg(script)..ident_seg(line)..ident_seg(consumer)..ident_seg(kind)
    end
    list[#list+1]={
      _base=base,_line=line or 0,_pattern=pattern==U.null and '' or pattern,
      symbol=symbol,kind=kind,pattern=pattern,source_script=script,
      source_line=line or U.null,consumer=consumer,provider=provider,helper=helper,
      validation={state=state,attempted=attempted},
      runtime_validated=aobs[pattern] and aobs[pattern].state=='unique' or false,
      provenance={kinds=kinds,count=#kinds},
      condition=cond
    }
    end
  end
  local occurrences={}
  local out=U.array()
  for _,c in ipairs(list) do
    local key,idkind,strong=false,false
    if c._base then
      occurrences[c._base]=(occurrences[c._base] or 0)+1
      key=c._base..'#occ='..occurrences[c._base]
      idkind=c.symbol~=U.null and 'symbol_consumer' or 'line'
      strong=(c.symbol~=U.null and c.source_script~='' and c.consumer~='' and c.kind~='')
    else
      key=U.null;idkind='unknown';strong=false
    end
    out[#out+1]={
      identity={key=key,kind=idkind,occurrence=(c._base and occurrences[c._base]) or 1,strong=strong},
      symbol=c.symbol,kind=c.kind,pattern=c.pattern,source_script=c.source_script,
      source_line=c.source_line,consumer=c.consumer,provider=c.provider,
      helper=c.helper,validation=c.validation,runtime_validated=c.runtime_validated,
      provenance=c.provenance,condition=c.condition
    }
    if #out>=M.MAX_CANDIDATES then break end
  end
  local total=#source
  table.sort(out,function(a,b) return tostring(a.identity.key or '~')<tostring(b.identity.key or '~') end)
  return out,total>#out
end

local function build_dependencies(report,redactions)
  local counts,order={},U.array()
  for _,d in ipairs(report.dependencies or {}) do
    local name=sanitize(d.name or '?',redactions)
    local rel=d.relation or 'unknown'
    local scope=d.scope or 'unknown'
    local key=name..'\0'..rel..'\0'..scope
    if not counts[key] then counts[key]={name=name,relation=rel,scope=scope,count=0};order[#order+1]=key end
    counts[key].count=counts[key].count+1
  end
  table.sort(order)
  local out=U.array()
  for _,key in ipairs(order) do
    if #out>=M.MAX_DEPENDENCIES then break end
    out[#out+1]=counts[key]
  end
  return out,#order>#out
end

local function build_unresolved(report,redactions)
  local list={}
  local function add_pool(pool)
    if type(pool)~='table' then return end
    for _,u in ipairs(pool) do
      list[#list+1]={code=sanitize(u.code or 'unknown',redactions),
        name=str_or_null(u.name),source_script=str_or_null(u.source_script),
        source_line=isnum(u.line) and math.floor(u.line) or U.null}
    end
  end
  add_pool(report.unresolved)
  add_pool(report.dynamic_analysis and report.dynamic_analysis.unresolved)
  table.sort(list,function(a,b)
    local ak=tostring(a.code)..'\0'..tostring(a.name)..'\0'..tostring(a.source_script)..'\0'..tostring(a.source_line)
    local bk=tostring(b.code)..'\0'..tostring(b.name)..'\0'..tostring(b.source_script)..'\0'..tostring(b.source_line)
    return ak<bk
  end)
  local out=U.array()
  for _,u in ipairs(list) do if #out>=M.MAX_UNRESOLVED then break end;out[#out+1]=u end
  return out,#list>#out
end

local function build_provenance(report)
  local counts={}
  local edges=report.dynamic_analysis and report.dynamic_analysis.edges or {}
  for _,e in ipairs(edges) do
    local kind=e.provenance or 'unknown'
    counts[kind]=(counts[kind] or 0)+1
  end
  local keys={}
  for k in pairs(counts) do keys[#keys+1]=k end
  table.sort(keys)
  local kinds=U.array()
  for _,k in ipairs(keys) do kinds[#kinds+1]={kind=k,count=counts[k]} end
  return {edge_count=#edges,kinds=kinds}
end

local function module_meta(m)
  if type(m)~='table' then return U.null end
  local name=basename(m.name or m.module_name)
  if type(name)=='string' and name~='' then return {
    name=name,size=int_or_null(m.size),timestamp=str_or_null(m.timestamp or m.time_date_stamp),
    hash=str_or_null(m.hash or m.sha256)
  } end
  return U.null
end

local function build_modules(report,target_name)
  local mods=report.modules or {}
  local main=U.null
  for _,m in ipairs(mods) do
    local name=basename(m.name or m.module_name)
    if name and target_name and name:lower()==tostring(target_name):lower() then main=module_meta(m);break end
  end
  if main==U.null and #mods>0 then main=module_meta(mods[1]) end
  local chunks={}
  for _,m in ipairs(mods) do
    chunks[#chunks+1]=tostring(basename(m.name or m.module_name))..'\0'..tostring(m.size or '')
  end
  table.sort(chunks)
  return {count=#mods,main_module=main,
    inventory_fingerprint=#chunks>0 and sha256(table.concat(chunks,'\1')) or U.null}
end

local function build_target(report,redactions,options)
  local t=report.target or {}
  local name=str_or_null(basename(t.name or t.process_name))
  local modules=build_modules(report,name)
  local main=modules.main_module
  local arch=str_or_null(t.architecture)
  local modname=main~=U.null and main.name or U.null
  local modsize=main~=U.null and main.size or U.null
  local modstamp=main~=U.null and main.timestamp or U.null
  local modhash=main~=U.null and main.hash or U.null
  local fp=U.null
  local known=false
  if name~=U.null then
    fp=sha256(table.concat({name,tostring(arch),tostring(modname),tostring(modsize),
      tostring(modstamp),tostring(modhash)},'|'))
    known=(modsize~=U.null) or (modstamp~=U.null) or (modhash~=U.null)
  end
  return {
    attached=t.attached==true,process_name=name,architecture=arch,
    main_module=main,fingerprint=fp,fingerprint_algorithm='sha256',
    build_fingerprint_known=known,
    pid_context=(options.include_pid and isnum(t.pid)) and math.floor(t.pid) or U.null
  },modules
end

local function build_source(report,redactions)
  local scripts={}
  for _,s in ipairs(report.scripts or {}) do
    if type(s.text)=='string' then scripts[#scripts+1]={id=s.id or s.script_id or '',
      line=s.line or 0,text=norm_text(s.text),language=s.language or 'unknown'} end
  end
  table.sort(scripts,function(a,b)
    if tostring(a.id)~=tostring(b.id) then return tostring(a.id)<tostring(b.id) end
    return a.line<b.line
  end)
  local bytes=0
  local chunks={}
  for _,s in ipairs(scripts) do
    bytes=bytes+#s.text
    chunks[#chunks+1]=tostring(s.id)..'\0'..s.language..'\0'..s.text
  end
  local kind=#scripts>0 and 'runtime_report' or 'unknown'
  local scope=#scripts>0 and 'captured_scripts' or 'none'
  local fp=#chunks>0 and sha256(table.concat(chunks,'\1')) or U.null
  if #scripts==0 and (report.dynamic_analysis or report.observations) then
    kind='static_lua_report'
    local surface={}
    for _,c in ipairs(report.dynamic_analysis and report.dynamic_analysis.patterns or report.observations or {}) do
      surface[#surface+1]=tostring(c.kind)..'\0'..tostring(c.symbol)..'\0'..
        tostring(norm_pattern(c.pattern))..'\0'..tostring(c.source_script)..'\0'..tostring(c.source_line)
    end
    table.sort(surface)
    if #surface>0 then
      scope='derived_candidates'
      fp=sha256(table.concat(surface,'\1'))
    end
  end
  local records=report.records and #report.records or nil
  return {
    kind=kind,fingerprint=fp,fingerprint_algorithm='sha256',
    fingerprint_scope=scope,record_count=records and math.floor(records) or U.null,
    script_count=#scripts,source_bytes=(#scripts>0) and bytes or U.null,
    normalization={line_endings='lf',trailing_whitespace='preserved',ordering='script_id_then_line'}
  },scripts
end

local function build_operation(report,redactions)
  local o=report.operation or {}
  local m=o.metrics or {}
  return {
    status=o.status or 'unknown',source_complete=o.source_complete==true,
    partial=o.partial==true,cancelled=o.cancelled==true,
    warnings=clean_list(o.warnings,redactions,200),
    parse_ms=num_or_null(m.parse_ms),scan_ms=num_or_null(m.scan_ms),
    total_ms=num_or_null(m.duration_ms),source_bytes=int_or_null(m.source_bytes),
    items_total=int_or_null(m.items_total),items_processed=int_or_null(m.items_processed)
  }
end

local function build_address_evidence(list,redactions)
  local out=U.array()
  local total=#(list or {})
  for _,ev in ipairs(list or {}) do
    if #out>=M.MAX_ADDRESS_EVIDENCE then break end
    local mod=ev.module or {}
    local bytes=ev.bytes or {}
    local ins=ev.instruction or {}
    out[#out+1]={
      status=ev.status or 'unknown',module_name=str_or_null(basename(mod.module_name or mod.name)),
      module_size=int_or_null(mod.module_size or mod.size),rva=str_or_null(mod.rva),
      read_status=str_or_null(bytes.read_status),instruction_status=str_or_null(ins.status),
      symbol_status=str_or_null((ev.symbol or {}).status)
    }
  end
  return out,total>#out
end

local function identity_payload(s)
  local target={}
  for k,v in pairs(s.target or {}) do
    if k~='pid_context' then target[k]=v end
  end
  return {
    snapshot_version=s.snapshot_version,suite_version=s.suite_version,core_version=s.core_version,
    source=s.source,target=target,coverage=s.coverage,provenance=s.provenance,
    candidates=s.candidates,dependencies=s.dependencies,unresolved=s.unresolved,
    modules=s.modules
  }
end
local function compute_id(s)
  return 'snap-'..sha256(E.encode(identity_payload(s))):sub(1,32)
end

function M.capture(report,options)
  assert(type(report)=='table','report required')
  options=options or {}
  local redactions={}
  local source,scripts=build_source(report,redactions)
  local target,modules=build_target(report,redactions,options)
  local coverage=report.coverage or {}
  local cov={
    collection=copy_collection(coverage.collection,redactions),
    discovery=copy_discovery(coverage.discovery,redactions),
    validation=copy_validation(coverage.validation,redactions)
  }
  local candidates,candidate_truncated=build_candidates(report,redactions,options)
  local dependencies,dependency_truncated=build_dependencies(report,redactions)
  local unresolved,unresolved_truncated=build_unresolved(report,redactions)
  local address_evidence,address_truncated=build_address_evidence(options.address_evidence,redactions)
  local limitations=clean_list(report.limitations,redactions,M.MAX_USER_LIMITATIONS)
  local limitation_seen={}
  for _,v in ipairs(limitations) do limitation_seen[v]=true end
  local function add_limit(code)
    if #limitations>=M.MAX_LIMITATIONS or limitation_seen[code] then return end
    limitation_seen[code]=true
    limitations[#limitations+1]=code
  end
  if candidate_truncated then add_limit('SNAPSHOT_CANDIDATE_LIMIT') end
  if dependency_truncated then add_limit('SNAPSHOT_DEPENDENCY_LIMIT') end
  if unresolved_truncated then add_limit('SNAPSHOT_UNRESOLVED_LIMIT') end
  if address_truncated then add_limit('SNAPSHOT_ADDRESS_EVIDENCE_LIMIT') end
  if #(report.limitations or {})>M.MAX_USER_LIMITATIONS then add_limit('SNAPSHOT_LIMITATION_LIMIT') end
  local redaction_keys={}
  for k in pairs(redactions) do redaction_keys[#redaction_keys+1]=k end
  table.sort(redaction_keys)
  local snapshot={
    snapshot_version=M.VERSION,schema_id='cesuite.evidence_snapshot',snapshot_id='',
    created_at=options.created_at or os.date('!%Y-%m-%dT%H:%M:%SZ'),
    suite_version=options.suite_version or '0.3.1',core_version=options.core_version or '0.1.9',
    source=source,target=target,coverage=cov,
    operation=build_operation(report,redactions),provenance=build_provenance(report),
    candidates=candidates,dependencies=dependencies,
    unresolved=unresolved,modules=modules,
    limitations=limitations,redactions=U.array(redaction_keys),address_evidence=address_evidence
  }
  snapshot.snapshot_id=compute_id(snapshot)
  return snapshot
end

local function copy(v,array_hint)
  if type(v)~='table' then return v end
  if v==U.null then return U.null end
  local is_array=array_hint
  if is_array==nil then
    is_array=getmetatable(v) and getmetatable(v).__json_array
    if not is_array then
      local n=0
      for k in pairs(v) do if type(k)=='number' and k==math.floor(k) and k>=1 then n=math.max(n,k) else is_array=false;break end end
      is_array=(n>0) or (next(v)==nil and false)
    end
  end
  local out=is_array and U.array() or {}
  for k,val in pairs(v) do out[k]=copy(val,nil) end
  return out
end

function M.normalize(snapshot)
  assert(type(snapshot)=='table','snapshot required')
  local s=copy(snapshot)
  if s.snapshot_version~=1 then return s end
  if type(s.candidates)=='table' then
    table.sort(s.candidates,function(a,b)
      return tostring(a.identity and a.identity.key or '~')<tostring(b.identity and b.identity.key or '~')
    end)
  end
  if type(s.dependencies)=='table' then
    table.sort(s.dependencies,function(a,b)
      local ak=tostring(a.name)..'\0'..tostring(a.relation)..'\0'..tostring(a.scope)
      local bk=tostring(b.name)..'\0'..tostring(b.relation)..'\0'..tostring(b.scope)
      return ak<bk
    end)
  end
  if type(s.unresolved)=='table' then
    table.sort(s.unresolved,function(a,b)
      local ak=tostring(a.code)..'\0'..tostring(a.name)..'\0'..tostring(a.source_script)..'\0'..tostring(a.source_line)
      local bk=tostring(b.code)..'\0'..tostring(b.name)..'\0'..tostring(b.source_script)..'\0'..tostring(b.source_line)
      return ak<bk
    end)
  end
  if s.provenance and type(s.provenance.kinds)=='table' then
    table.sort(s.provenance.kinds,function(a,b) return tostring(a.kind)<tostring(b.kind) end)
  end
  s.snapshot_id=compute_id(s)
  return s
end

local function type_is(v,t)
  if t=='integer' then return isnum(v) and v==math.floor(v) end
  if t=='number' then return isnum(v) end
  if t=='string' then return type(v)=='string' end
  if t=='boolean' then return type(v)=='boolean' end
  if t=='table' then return type(v)=='table' end
  if t=='null' then return v==U.null or v==nil end
  return type(v)==t
end

local TOP_KEYS={snapshot_version=true,schema_id=true,snapshot_id=true,created_at=true,
  suite_version=true,core_version=true,source=true,target=true,coverage=true,
  operation=true,provenance=true,candidates=true,dependencies=true,unresolved=true,
  modules=true,limitations=true,redactions=true,address_evidence=true}
local CANDIDATE_KEYS={identity=true,symbol=true,kind=true,pattern=true,source_script=true,
  source_line=true,consumer=true,provider=true,helper=true,validation=true,
  runtime_validated=true,provenance=true,condition=true}

function M.validate(snapshot)
  local errs=U.array()
  local function err(msg) errs[#errs+1]=msg end
  if type(snapshot)~='table' then return false,arr({'snapshot must be a table'}) end
  for k in pairs(snapshot) do if not TOP_KEYS[k] then err('unexpected top-level field '..tostring(k)) end end
  if snapshot.snapshot_version==nil then err('snapshot_version required')
  elseif type(snapshot.snapshot_version)~='number' then err('snapshot_version type')
  elseif snapshot.snapshot_version~=M.VERSION then err('unsupported snapshot_version') end
  if snapshot.schema_id~='cesuite.evidence_snapshot' then err('invalid schema_id') end
  if type(snapshot.snapshot_id)~='string' or not snapshot.snapshot_id:match('^snap%-[0-9a-f]+$') then err('invalid snapshot_id') end
  if type(snapshot.created_at)~='string' or snapshot.created_at=='' then err('created_at required') end
  if type(snapshot.suite_version)~='string' then err('suite_version required') end
  if type(snapshot.core_version)~='string' then err('core_version required') end
  for _,name in ipairs({'source','target','coverage','operation','provenance','modules'}) do
    if type(snapshot[name])~='table' then err(name..' required') end
  end
  for _,name in ipairs({'candidates','dependencies','unresolved','limitations','redactions'}) do
    if type(snapshot[name])~='table' then err(name..' array required') end
  end
  if type(snapshot.candidates)=='table' and #snapshot.candidates>M.MAX_CANDIDATES then err('candidate limit exceeded') end
  if type(snapshot.dependencies)=='table' and #snapshot.dependencies>M.MAX_DEPENDENCIES then err('dependency limit exceeded') end
  if type(snapshot.unresolved)=='table' and #snapshot.unresolved>M.MAX_UNRESOLVED then err('unresolved limit exceeded') end
  if type(snapshot.limitations)=='table' and #snapshot.limitations>M.MAX_LIMITATIONS then err('limitation limit exceeded') end
  if type(snapshot.source)=='table' then
    local src=snapshot.source
    if type(src.fingerprint)~='string' and src.fingerprint~=U.null then err('source fingerprint type') end
    if type(src.fingerprint)=='string' and not src.fingerprint:match('^[0-9a-f]+$') then err('source fingerprint hex') end
    if type(src.script_count)~='number' then err('source script_count') end
  end
  if type(snapshot.target)=='table' then
    if type(snapshot.target.attached)~='boolean' then err('target attached') end
    if type(snapshot.target.build_fingerprint_known)~='boolean' then err('target build_fingerprint_known') end
  end
  if type(snapshot.coverage)=='table' then
    for _,name in ipairs({'collection','discovery','validation'}) do
      if type(snapshot.coverage[name])~='table' then err('coverage.'..name) end
    end
  end
  if type(snapshot.candidates)=='table' then
    for i,c in ipairs(snapshot.candidates) do
      if type(c.identity)~='table' then err('candidate '..i..' identity') end
      if type(c.identity)=='table' and type(c.identity.strong)~='boolean' then err('candidate '..i..' identity strong') end
      if type(c.kind)~='string' then err('candidate '..i..' kind') end
      if type(c.validation)~='table' or type(c.validation.state)~='string' then err('candidate '..i..' validation') end
      for k in pairs(c) do if not CANDIDATE_KEYS[k] then err('candidate '..i..' unexpected field '..tostring(k)) end end
      for _,field in ipairs({'provider','helper'}) do
        local v=c[field]
        if type(v)=='string' and (v:match('^%a:') or v:match('^[/\\]') or v:find('[Uu]sers[\\/]')) then
          err('candidate '..i..' '..field..' contains a local path')
        end
      end
      for _,dep in ipairs(c.condition and c.condition.dependencies or {}) do
        if type(dep)=='string' and (dep:match('^%a:') or dep:match('^[/\\]') or dep:find('[Uu]sers[\\/]')) then
          err('candidate '..i..' condition dependency contains a local path')
        end
      end
      for _,forbidden in ipairs({'ast','raw','source_text','memory','bytes'}) do
        if c[forbidden]~=nil then err('candidate '..i..' forbidden field '..forbidden) end
      end
    end
  end
  if #errs==0 then
    local expected=compute_id(snapshot)
    if snapshot.snapshot_id~=expected then err('snapshot identity invalid') end
  end
  return #errs==0,errs
end

function M.decode(text,options)
  local value,parseError=Json.decode(text,{max_bytes=(options and options.max_bytes) or M.MAX_BYTES,
    max_depth=(options and options.max_depth) or 64})
  if not value then return nil,parseError end
  local ok,errs=M.validate(value)
  if not ok then
    local identity,version=false,false
    for _,e in ipairs(errs) do
      if e:find('identity',1,true) then identity=true end
      if e:find('unsupported snapshot_version',1,true) then version=true end
    end
    local code='schema_invalid'
    if version then code='unsupported_snapshot_version'
    elseif identity then code='identity_invalid' end
    return nil,{code=code,message=table.concat(errs,'; ')}
  end
  return value
end

function M.summary(snapshot)
  local counts={}
  for _,c in ipairs(snapshot.candidates or {}) do
    counts[c.kind]=(counts[c.kind] or 0)+1
  end
  local validated=0
  for _,c in ipairs(snapshot.candidates or {}) do
    if c.validation and c.validation.state=='unique' then validated=validated+1 end
  end
  return {
    snapshot_id=snapshot.snapshot_id,created_at=snapshot.created_at,
    suite_version=snapshot.suite_version,
    source_kind=snapshot.source and snapshot.source.kind,
    target_name=snapshot.target and snapshot.target.process_name,
    collection_status=snapshot.coverage and snapshot.coverage.collection.status,
    discovery_status=snapshot.coverage and snapshot.coverage.discovery.status,
    validation_status=snapshot.coverage and snapshot.coverage.validation.status,
    candidates=#(snapshot.candidates or {}),validated=validated,
    unresolved=#(snapshot.unresolved or {}),limitations=#(snapshot.limitations or {})
  }
end

function M.encode(snapshot)
  local ok,errs=M.validate(snapshot)
  assert(ok,table.concat(errs or {},'; '))
  return E.encode(snapshot)
end

function M.compare(a,b)
  local D=require('snapshotdiff')
  return D.compare(a,b)
end

return M
