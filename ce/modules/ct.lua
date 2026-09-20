local U=require('util')
local P=require('parser')
local M={}
function M.capture(api,report,selectedOnly)
  local al,err=U.call(api,'getAddressList')
  report.ct={status='unavailable',selection_only=selectedOnly or false,table_lua_status='unavailable'}
  if not al then U.warn(report,'CT-UNAVAILABLE',err or 'Address list unavailable');return end
  local count=U.get(al,'Count')
  if type(count)~='number' then U.warn(report,'CT-UNAVAILABLE','Address list count unavailable');return end
  local refs,keys,indexKeys={},{},{}
  for i=0,math.min(count,10000)-1 do
    local ok,r=pcall(function() return al.getMemoryRecord(i) end)
    if ok and r then
      refs[#refs+1]=r;keys[r]='record-'..(i+1)
      local index=U.get(r,'Index');if type(index)=='number' then indexKeys[index]=keys[r] end
    else U.warn(report,'RECORD-UNAVAILABLE','Could not read MemoryRecord index '..i) end
  end
  if count>10000 then U.warn(report,'CT-LIMIT','Inventory limited to 10000 records.') end
  local selected=U.get(al,'SelectedRecord')
  local selectedIndex=selected and U.get(selected,'Index')
  if api.vtAutoAssembler==nil then U.warn(report,'AA-TYPE-UNAVAILABLE','vtAutoAssembler constant unavailable; AA script extraction cannot be classified.') end
  local function addScript(text,language,key,origin)
    local s={id='script-'..(#report.scripts+1),language=language,text=text,record_key=key or U.null,origin=origin}
    report.scripts[#report.scripts+1]=s
    if language=='AA' then P.inspect(s,report) end
    return s.id
  end
  for _,r in ipairs(refs) do
    if not selectedOnly or r==selected or (selectedIndex~=nil and U.get(r,'Index')==selectedIndex) then
      local parent=U.get(r,'Parent')
      local parentKey=parent and (indexKeys[U.get(parent,'Index')] or keys[parent])
      -- Address can evaluate dynamic offsets and execute Lua, even inside pcall.
      -- Keep the nullable report field without resolving it during passive capture.
      local row={key=keys[r],id=U.get(r,'ID') or U.null,parent_key=parentKey or U.null,
        description=U.get(r,'Description') or '',address=U.null,
        variable_type=U.get(r,'Type') or U.null,active=U.get(r,'Active')==true,scripts=U.array(),offsets=U.array()}
      for j=0,(U.get(r,'OffsetCount') or 0)-1 do
        local ok,offset=pcall(function() return r.OffsetText[j] end)
        row.offsets[#row.offsets+1]=ok and tostring(offset) or 'unavailable'
      end
      if api.vtAutoAssembler~=nil and row.variable_type==api.vtAutoAssembler then
        local source=U.get(r,'Script')
        if type(source)=='string' then row.scripts[#row.scripts+1]=addScript(source,'AA',row.key,'MemoryRecord.Script')
        else U.warn(report,'SCRIPT-UNAVAILABLE','MemoryRecord.Script unavailable',nil) end
      end
      report.records[#report.records+1]=row
      if row.active then U.warn(report,'ACTIVE-RECORD','Active record observed; bytes/signatures may already be modified by the loaded table.',nil) end
    end
  end
  if selectedOnly and not selected then U.warn(report,'SELECTION-EMPTY','Select an AA MemoryRecord first.') end
  -- Read the documented editor property, never execute it or serialize the table.
  if not selectedOnly then
    local ok,text=pcall(function() return api.getLuaEngine().mScript.Lines.Text end)
    if ok and type(text)=='string' then
      addScript(text,'Lua',nil,'LuaEngine.mScript.Lines.Text')
      report.ct.table_lua_status='editor_snapshot'
    else U.warn(report,'TABLE-LUA-UNAVAILABLE','Table Lua editor unavailable; globals, closures and external files are not introspected.') end
  end
  report.ct.status='captured'
  report.ct.loaded_table_version=U.get(al,'LoadedTableVersion') or U.null
  for _,s in ipairs(report.scripts) do
    if s.language=='Lua' then
      for _,hint in ipairs({{'createTimer','TIMER-LIFECYCLE'}, {'debug_setBreakpoint','BREAKPOINT-OWNERSHIP'},
        {'debugger_onBreakpoint','HANDLER-CHAIN'}}) do
        if s.text:find(hint[1],1,true) then U.warn(report,hint[2],
          'Lexical Lua candidate (comments/strings may match); review resource ownership and callback teardown.',s.id) end
      end
    end
  end
end
return M
