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
  for _,m in ipairs(modules) do
    local size=U.call(api,'getModuleSize',m.Name)
    table.insert(report.modules,{name=m.Name,base=U.hex(m.Address),size=type(size)=='number' and size or U.null,
      path=m.PathToFile or U.null,architecture=m.Is64Bit==nil and 'unknown' or (m.Is64Bit and 'x64' or 'x86')})
  end
end
return M
