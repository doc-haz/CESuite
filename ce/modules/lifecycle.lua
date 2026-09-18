local M={}
function M.new()
  local state={owned={},busy=false}
  function state.own(object) state.owned[#state.owned+1]=object;return object end
  function state.shutdown()
    assert(not state.busy,'CESuite is busy')
    for i=#state.owned,1,-1 do pcall(function() state.owned[i].destroy() end) end
    state.owned={}
  end
  function state.run(callback)
    assert(not state.busy,'CESuite is already analyzing')
    state.busy=true
    local ok,result=xpcall(callback,function(e) return tostring(e) end)
    state.busy=false
    if not ok then error(result) end
    return result
  end
  return state
end
return M
