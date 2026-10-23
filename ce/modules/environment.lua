local U = require('util')
local M = {}
function M.capture(api, report)
  local pid, err = U.call(api, 'getOpenedProcessID')
  local target = {pid=pid or U.null, attached=type(pid)=='number' and pid>0,
    name=type(api.process)=='string' and api.process or U.null, architecture='unknown',
    build_fingerprint=U.null}
  report.target=target
  report.modules=U.array()
  report.ce_version=tostring(U.call(api, 'getCEVersion') or 'unknown')
  if not target.attached then
    U.warn(report,'PROCESS-UNAVAILABLE',err or 'No process attached; no runtime reads or scans.')
    return
  end
  local x64=U.call(api,'targetIs64Bit')
  if type(x64)=='boolean' then target.architecture=x64 and 'x64' or 'x86' end
  local modules, failure=U.call(api,'enumModules')
  if type(modules)~='table' then U.warn(report,'MODULES-UNAVAILABLE',failure or 'Module enumeration failed'); return end
  -- Resolve the exact same name/path candidate set used by AOB bounds.
  for _,m in ipairs(modules) do
    table.insert(report.modules,{name=m.Name or U.null,base=U.hex(m.Address),size=U.null,
      path=m.PathToFile or U.null,architecture=m.Is64Bit==nil and 'unknown' or (m.Is64Bit and 'x64' or 'x86')})
  end
  for i,m in ipairs(modules) do
    local candidate,reason=U.moduleMatch(m.Name,report.modules)
    local _,pathReason=U.moduleMatch(m.PathToFile,report.modules)
    if pathReason and pathReason:match('^ambiguous') then candidate=nil;reason=pathReason end
    if not candidate then
      U.warn(report,'MODULE-SNAPSHOT-INCOMPLETE',tostring(reason)..'; size lookup omitted.')
    else
      local size=U.call(api,'getModuleSize',m.Name)
      report.modules[i].size=type(size)=='number' and size or U.null
    end
  end
end
return M
