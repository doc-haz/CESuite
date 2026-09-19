-- Derived lexical inventory only. Never evaluates inspected source or resolves links.
local U=require('util')
local M={}

-- Length prefixes keep arbitrary script IDs from colliding with delimiters.
local function key(values)
  local parts={}
  for i,v in ipairs(values) do v=tostring(v);parts[i]=#v..':'..v end
  return table.concat(parts)
end

function M.summarize(occurrences)
  local groups,index=U.array(),{}
  for i,d in ipairs(occurrences or {}) do
    local identity=key({d.name,d.kind,d.source,d.relation})
    local state=index[identity]
    if not state then
      local group={name=d.name,kind=d.kind,source=d.source,relation=d.relation,
        status='unverified',occurrence_count=0,location_count=0,
        script_ids=U.array(),sections=U.array(),locations=U.array()}
      state={group=group,scripts={},sections={},locations={}}
      index[identity]=state;groups[#groups+1]=group
    end
    local g=state.group
    g.occurrence_count=g.occurrence_count+1
    if not state.scripts[d.script_id] then
      state.scripts[d.script_id]=true;g.script_ids[#g.script_ids+1]=d.script_id
    end
    if not state.sections[d.section] then
      state.sections[d.section]=true;g.sections[#g.sections+1]=d.section
    end
    local locationKey=key({d.script_id,d.section,d.line,d.command})
    local location=state.locations[locationKey]
    if not location then
      location={script_id=d.script_id,section=d.section,line=d.line,command=d.command,
        occurrence_count=0,occurrence_indices=U.array()}
      state.locations[locationKey]=location
      g.locations[#g.locations+1]=location;g.location_count=g.location_count+1
    end
    location.occurrence_count=location.occurrence_count+1
    location.occurrence_indices[#location.occurrence_indices+1]=i
  end
  return groups
end

return M
