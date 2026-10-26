-- Read-only snapshot presentation. No CE API, no writes.
local U=require('util')
local M={}
local MAX_ROWS=50

local function text(v)
  if v==nil or v==U.null then return 'unknown' end
  return tostring(v)
end
local function list(values)
  local out={}
  for _,v in ipairs(values or {}) do out[#out+1]=text(v) end
  return table.concat(out,', ')
end
local function line(out,label,value) out[#out+1]=label..': '..text(value) end

function M.render(snapshot)
  local out={'# CESuite Evidence Snapshot',''}
  out[#out+1]='## Overview'
  line(out,'Snapshot version',snapshot.snapshot_version)
  line(out,'Suite version',snapshot.suite_version)
  line(out,'Core version',snapshot.core_version)
  line(out,'Created at',snapshot.created_at)
  line(out,'Snapshot ID',snapshot.snapshot_id)
  line(out,'Source kind',snapshot.source and snapshot.source.kind)
  line(out,'Target',snapshot.target and snapshot.target.process_name)
  out[#out+1]=''

  out[#out+1]='## Target'
  line(out,'Attached',snapshot.target and snapshot.target.attached)
  line(out,'Architecture',snapshot.target and snapshot.target.architecture)
  line(out,'Build fingerprint known',snapshot.target and snapshot.target.build_fingerprint_known)
  line(out,'Target fingerprint',snapshot.target and snapshot.target.fingerprint)
  local m=snapshot.target and snapshot.target.main_module
  if m and m~=U.null then
    line(out,'Main module',m.name)
    line(out,'Main module size',m.size)
  end
  out[#out+1]=''

  out[#out+1]='## Source'
  line(out,'Fingerprint scope',snapshot.source and snapshot.source.fingerprint_scope)
  line(out,'Source fingerprint',snapshot.source and snapshot.source.fingerprint)
  line(out,'Records',snapshot.source and snapshot.source.record_count)
  line(out,'Scripts',snapshot.source and snapshot.source.script_count)
  line(out,'Source bytes',snapshot.source and snapshot.source.source_bytes)
  out[#out+1]=''

  out[#out+1]='## Coverage'
  for _,name in ipairs({'collection','discovery','validation'}) do
    local c=snapshot.coverage and snapshot.coverage[name]
    out[#out+1]='### '..name:gsub('^%l',string.upper)
    if c then
      line(out,'Status',c.status);line(out,'Complete',c.complete)
      if name=='collection' then
        line(out,'Units',tostring(c.units_processed)..' / '..tostring(c.units_discovered))
      elseif name=='discovery' then
        line(out,'Entities',c.entities_discovered);line(out,'Candidates',c.candidates)
        line(out,'Linked',c.linked);line(out,'Unresolved',c.unresolved)
      else
        line(out,'Candidates',c.candidates);line(out,'Attempted',c.attempted)
        line(out,'Validated',c.validated);line(out,'Unique',c.unique)
        line(out,'Ambiguous',c.ambiguous);line(out,'No match',c.no_match)
        line(out,'Error',c.error);line(out,'Unavailable',c.unavailable)
      end
      line(out,'Percentage',c.percentage)
    else out[#out+1]='not present' end
    out[#out+1]=''
  end

  out[#out+1]='## Validation'
  local v=snapshot.coverage and snapshot.coverage.validation
  if v then
    line(out,'Status',v.status);line(out,'Complete',v.complete)
    line(out,'Candidates',v.candidates);line(out,'Attempted',v.attempted)
    line(out,'Validated',v.validated);line(out,'Unique',v.unique)
    line(out,'Ambiguous',v.ambiguous);line(out,'No match',v.no_match)
    line(out,'Error',v.error);line(out,'Unavailable',v.unavailable)
    line(out,'Percentage',v.percentage)
  else out[#out+1]='not present' end
  out[#out+1]=''

  out[#out+1]='## Candidates'
  local n=#(snapshot.candidates or {})
  out[#out+1]='Total: '..tostring(n)..'; showing up to '..MAX_ROWS..'.'
  for i=1,math.min(n,MAX_ROWS) do
    local c=snapshot.candidates[i]
    out[#out+1]=string.format('%d. %s [%s] %s | source=%s:%s consumer=%s | validation=%s | identity=%s',
      i,text(c.symbol),text(c.kind),text(c.pattern),text(c.source_script),text(c.source_line),
      text(c.consumer),text(c.validation and c.validation.state),
      (c.identity and c.identity.strong) and 'strong' or 'weak')
    line(out,'   provider',c.provider);line(out,'   helper',c.helper)
  end
  if n>MAX_ROWS then out[#out+1]='... '..tostring(n-MAX_ROWS)..' more candidates; use Compare/Extensive data for full evidence.' end
  out[#out+1]=''

  out[#out+1]='## Provenance'
  line(out,'Edges',snapshot.provenance and snapshot.provenance.edge_count)
  local kinds={}
  for _,k in ipairs(snapshot.provenance and snapshot.provenance.kinds or {}) do kinds[#kinds+1]=k.kind..'='..tostring(k.count) end
  out[#out+1]='Kinds: '..table.concat(kinds,', ')
  out[#out+1]=''

  out[#out+1]='## Dependencies'
  for i,d in ipairs(snapshot.dependencies or {}) do
    if i>MAX_ROWS then break end
    out[#out+1]=string.format('%s [%s/%s] x%s',text(d.name),text(d.relation),text(d.scope),text(d.count))
  end
  out[#out+1]=''

  out[#out+1]='## Unresolved'
  for i,u in ipairs(snapshot.unresolved or {}) do
    if i>MAX_ROWS then break end
    out[#out+1]=string.format('%s %s (%s:%s)',text(u.code),text(u.name),text(u.source_script),text(u.source_line))
  end
  out[#out+1]=''

  out[#out+1]='## Limitations'
  for _,v in ipairs(snapshot.limitations or {}) do out[#out+1]='- '..text(v) end
  out[#out+1]=''

  out[#out+1]='## Modules'
  line(out,'Count',snapshot.modules and snapshot.modules.count)
  line(out,'Inventory fingerprint',snapshot.modules and snapshot.modules.inventory_fingerprint)
  out[#out+1]=''

  out[#out+1]='## Address Evidence'
  if #(snapshot.address_evidence or {})==0 then out[#out+1]='not present'
  else
    for _,e in ipairs(snapshot.address_evidence) do
      out[#out+1]=string.format('%s %s rva=%s read=%s instruction=%s',text(e.status),
        text(e.module_name),text(e.rva),text(e.read_status),text(e.instruction_status))
    end
  end
  return table.concat(out,'\n')
end

local function section(out,title,fields)
  out[#out+1]='## '..title
  for _,f in ipairs(fields) do
    local a,b=f[1],f[2]
    if f[3] then out[#out+1]='- '..f[3]..': '..text(a)..' → '..text(b)
    else out[#out+1]='- '..f[1]..': '..text(a)..' → '..text(b) end
  end
  out[#out+1]=''
end

function M.renderDiff(diff)
  local out={'# CESuite Evidence Snapshot Comparison',''}
  local c=diff.comparability or {}
  local header=c.status or 'unknown'
  if header=='comparable' then header='Comparable'
  elseif header=='partial_comparison' then header='Partial comparison'
  elseif header=='different_source' then header='Different source'
  elseif header=='different_target' then header='Different target'
  elseif header=='different_target_build' then header='Different target build'
  elseif header=='unknown' then header='Unknown'
  else header='Not comparable' end
  out[#out+1]='## '..header
  line(out,'Same source',c.same_source);line(out,'Source changed',c.source_changed)
  line(out,'Same target build',c.same_target_build);line(out,'Different target build',c.different_target_build)
  line(out,'Target build unknown',c.target_build_unknown);line(out,'Different target',c.different_target)
  line(out,'Strong identities only',c.strong_identity_only)
  for _,r in ipairs(c.reasons or {}) do out[#out+1]='- '..text(r) end
  out[#out+1]=''

  for _,name in ipairs({'collection','discovery','validation'}) do
    local sec=diff.coverage and diff.coverage[name]
    if sec then
      out[#out+1]='## '..name:gsub('^%l',string.upper)..' coverage'
      out[#out+1]='Changed: '..text(sec.changed)
      for _,f in ipairs(sec.fields or {}) do out[#out+1]='- '..f.field..': '..text(f.a)..' → '..text(f.b) end
      out[#out+1]=''
    end
  end

  out[#out+1]='## Candidates'
  local cd=diff.candidates or {}
  out[#out+1]='Status: '..text(cd.status)
  out[#out+1]='Unchanged: '..text(cd.unchanged)
  for _,group in ipairs({'changed','added','removed','unknown'}) do
    local rows=cd[group] or {}
    out[#out+1]='### '..group:gsub('^%l',string.upper)..' ('..#rows..')'
    for i,row in ipairs(rows) do
      if i>MAX_ROWS then out[#out+1]='... more';break end
      if group=='changed' then
        local fields={}
        for _,f in ipairs(row.fields or {}) do fields[#fields+1]=f.field..'='..text(f.a)..'→'..text(f.b) end
        out[#out+1]='- '..text(row.symbol)..': '..table.concat(fields,', ')
      else
        out[#out+1]='- '..text(row.symbol)..' ['..text(row.kind)..'] validation='..text(row.validation)
      end
    end
    out[#out+1]=''
  end

  out[#out+1]='## Dependencies'
  for _,group in ipairs({'added','removed','changed'}) do
    local rows=diff.dependencies and diff.dependencies[group] or {}
    out[#out+1]=group..': '..#rows
    for i,row in ipairs(rows) do if i>MAX_ROWS then break end;out[#out+1]='- '..text(row.name)..' ['..text(row.relation)..']' end
  end
  out[#out+1]=''
  out[#out+1]='## Unresolved'
  for _,group in ipairs({'added','removed'}) do
    local rows=diff.unresolved and diff.unresolved[group] or {}
    out[#out+1]=group..': '..#rows
    for i,row in ipairs(rows) do if i>MAX_ROWS then break end;out[#out+1]='- '..text(row.code)..' '..text(row.name) end
  end
  out[#out+1]=''

  out[#out+1]='## Modules'
  line(out,'Inventory changed',diff.modules and diff.modules.changed)
  out[#out+1]=''
  out[#out+1]='## Operation context'
  line(out,'A status',diff.operation and diff.operation.a)
  line(out,'B status',diff.operation and diff.operation.b)
  line(out,'A source complete',diff.operation and diff.operation.source_complete_a)
  line(out,'B source complete',diff.operation and diff.operation.source_complete_b)
  return table.concat(out,'\n')
end

return M
