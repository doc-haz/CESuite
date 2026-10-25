-- Coverage model (030C): collection, discovery and validation are separate
-- dimensions. Static analysis never promotes candidates to runtime validation.
local U=require('util')
local M={}

local function count_limits(dynamic)
  local codes={}
  for _,entry in ipairs(dynamic and dynamic.unresolved or {}) do
    if type(entry.code)=='string' and entry.code:match('_LIMIT$') then
      codes[entry.code]=(codes[entry.code] or 0)+1
    end
  end
  local list=U.array()
  for code,count in pairs(codes) do
    list[#list+1]={code=code,count=count}
  end
  table.sort(list,function(a,b) return a.code<b.code end)
  return list
end

local function percentage(numerator,denominator,known)
  if not known or type(denominator)~='number' or denominator<=0 then return U.null end
  if type(numerator)~='number' then return U.null end
  return math.floor((numerator/denominator)*1000+0.5)/10
end

function M.collection(scripts, dynamic, opts)
  opts=opts or {}
  local units=#(scripts or {})
  local limits=count_limits(dynamic)
  local limited=#limits>0 or (dynamic and dynamic.status=='limit_reached')
  local complete = not limited
  local status
  if units==0 then status=limited and 'limit_reached' or 'complete'
  elseif limited then status='limit_reached'
  else status='complete' end
  local limitations=U.array()
  for _,item in ipairs(limits) do
    limitations[#limitations+1]=item.code..' reached during collection'
  end
  if dynamic and dynamic.status=='limit_reached' and #limitations==0 then
    limitations[#limitations+1]='dynamic parser reached a structural limit'
  end
  return {
    scope='captured_scripts_and_embedded_lua',
    units_discovered=units,
    units_processed=units,
    complete=complete,
    universe_known=true,
    denominator='captured_units',
    status=status,
    percentage=percentage(units,units,true),
    limitations=limitations
  }
end

function M.discovery(dynamic, opts)
  opts=opts or {}
  local counts=dynamic and dynamic.counts or {}
  local literal=counts.literal or 0
  local derived=counts.derived or 0
  local conditional=counts.conditional or 0
  local symbol_only=counts.symbol_only or 0
  local specs=counts.specs or (literal+derived+symbol_only)
  local candidates=counts.candidates or (literal+derived)
  local unresolved=0
  local unsupported=0
  local linked=0
  for _,candidate in ipairs(dynamic and dynamic.patterns or {}) do
    if candidate.status=='candidate' then linked=linked+1
    elseif candidate.status=='unresolved' then unresolved=unresolved+1
    elseif candidate.status=='unsupported' then unsupported=unsupported+1 end
  end
  for _,entry in ipairs(dynamic and dynamic.unresolved or {}) do
    if entry.code~='TABLE_LIMIT' and entry.code~='PARSE_LIMIT'
      and entry.code~='EDGE_LIMIT' and entry.code~='CANDIDATE_LIMIT'
      and entry.code~='CONDITIONAL_DEPENDENCY' then
      unresolved=unresolved+1
    end
  end
  local limited=dynamic and dynamic.status=='limit_reached'
  local universe_known=opts.universe_known==true
  local complete=universe_known and not limited and unresolved==0 and unsupported==0
  local status
  if limited then status='limit_reached'
  elseif universe_known and unresolved==0 and unsupported==0 then status='complete'
  elseif unresolved>0 or unsupported>0 then status='partial'
  else status='unknown' end
  local limitations=U.array()
  if not universe_known then
    limitations[#limitations+1]='The total number of patterns in uncaptured source is unknown.'
  end
  if unresolved>0 then limitations[#limitations+1]='Some candidates remain unresolved.' end
  if limited then limitations[#limitations+1]='Discovery stopped at a structural limit.' end
  return {
    patterns_discovered=literal+derived+conditional,
    patterns_literal=literal,
    patterns_derived=derived,
    patterns_conditional=conditional,
    patterns_symbol_only=symbol_only,
    entities_discovered=specs,
    candidates=candidates,
    linked=linked,
    unresolved=unresolved,
    unsupported=unsupported,
    complete=complete,
    universe_known=universe_known,
    denominator='discovered_entities',
    status=status,
    percentage=percentage(linked,specs,universe_known),
    limitations=limitations
  }
end

local function aob_counts(aobs)
  local c={attempted=0,validated=0,unique=0,ambiguous=0,no_match=0,error=0,
    unavailable=0,unresolved=0,unsupported=0}
  for _,aob in ipairs(aobs or {}) do
    local status=aob.status
    if status=='observed' then
      c.attempted=c.attempted+1
      local count=aob.match_count
      local uniqueness=aob.uniqueness
      if count==1 and uniqueness=='unique_current_scan' then
        c.validated=c.validated+1;c.unique=c.unique+1
      elseif (type(count)=='number' and count>1) or uniqueness=='multiple_matches' then
        c.ambiguous=c.ambiguous+1
      elseif count==0 or uniqueness=='no_match' then
        c.no_match=c.no_match+1
      else
        c.no_match=c.no_match+1
      end
    elseif status=='error' then c.attempted=c.attempted+1;c.error=c.error+1
    elseif status=='invalidated' then c.attempted=c.attempted+1;c.unavailable=c.unavailable+1
    elseif status=='unavailable' then c.unavailable=c.unavailable+1
    elseif status=='unsupported' then c.unsupported=c.unsupported+1
    elseif status=='unresolved' then c.unresolved=c.unresolved+1
    end
  end
  return c
end

function M.validation(discovery, aobs, opts)
  opts=opts or {}
  local c=aob_counts(aobs)
  local candidates=discovery.candidates or 0
  local universe_known=(opts.universe_known==true) and (discovery.unresolved==0)
  local status
  if candidates==0 then status='not_applicable'
  elseif c.attempted==0 then status='unavailable'
  elseif c.attempted<candidates or c.error>0 or not universe_known then status='partial'
  else status='complete' end
  local complete=(candidates>0 and c.attempted>=candidates and c.error==0 and universe_known)
  local limitations=U.array()
  if candidates==0 then limitations[#limitations+1]='No validation candidates were discovered.' end
  if c.attempted==0 and candidates>0 then
    limitations[#limitations+1]='No runtime scan was attempted for the discovered candidates.'
  end
  if not universe_known and candidates>0 then
    limitations[#limitations+1]='Validation universe is unknown; no percentage is claimed.'
  end
  return {
    candidates=candidates,
    runtime_attempted=c.attempted,
    runtime_validated=c.validated,
    runtime_unique=c.unique,
    runtime_ambiguous=c.ambiguous,
    runtime_no_match=c.no_match,
    runtime_error=c.error,
    runtime_unavailable=c.unavailable,
    unresolved=discovery.unresolved+c.unresolved,
    unsupported=discovery.unsupported+c.unsupported,
    complete=complete,
    universe_known=universe_known,
    denominator='validation_candidates',
    status=status,
    percentage=percentage(c.validated,candidates,universe_known),
    limitations=limitations
  }
end

function M.for_static(dynamic, scripts, opts)
  local collection=M.collection(scripts,dynamic,opts)
  local discovery=M.discovery(dynamic,opts)
  local validation=M.validation(discovery,nil,opts)
  return {collection=collection,discovery=discovery,validation=validation}
end

function M.for_runtime(report, dynamic, opts)
  local collection=M.collection(report and report.scripts or {},dynamic,opts)
  local discovery=M.discovery(dynamic,opts)
  local validation=M.validation(discovery,report and report.aobs or {},opts)
  return {collection=collection,discovery=discovery,validation=validation}
end

function M.summaryText(cov)
  if not cov or type(cov)~='table' then return 'Coverage Summary\n\nNo coverage data available.' end
  local coll=cov.collection or {}
  local disc=cov.discovery or {}
  local val=cov.validation or {}
  local lines={
    'Coverage Summary',
    '',
    'Collection',
    string.format('  Status: %s',tostring(coll.status or 'unknown')),
    string.format('  Processed: %d / %d',coll.units_processed or 0,coll.units_discovered or 0),
    '',
    'Discovery',
    string.format('  Status: %s',tostring(disc.status or 'unknown')),
    string.format('  Entities: %d',disc.entities_discovered or 0),
    string.format('  Candidates: %d',disc.candidates or 0),
    string.format('  Linked: %d',disc.linked or 0),
    '',
    'Validation',
    string.format('  Status: %s',tostring(val.status or 'unknown')),
    string.format('  Attempted: %d / %d',val.runtime_attempted or 0,val.candidates or 0),
    string.format('  Validated: %d',val.runtime_validated or 0)
  }
  return table.concat(lines,'\n')
end

return M
