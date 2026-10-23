-- Entry point receives a private module loader and the CE API from the bundle.
local U=require('util')
local Env=require('environment')
local CT=require('ct')
local AOB=require('aob')
local Export=require('exporter')
local Life=require('lifecycle')
local UI=require('ui')
local Dependencies=require('dependencies')
local Semantics=require('semantics')
local ModuleDump=require('moduledump')
local Core={identity='CESuiteCore',version='0.1.9.1',schema_version='0.1',status='stopped',state=Life.new()}
function Core.analyze(mode)
  return Core.state.run(function()
    local r={schema_version=Core.schema_version,core_version='0.1.9',
      generated_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),mode=mode,observation_only=true,
      records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),dependencies=U.array(),diagnostics=U.array(),
      limitations=U.array({'Dependencies are partial lexical occurrences, not resolved cross-script links or runtime availability; provides/requires remain unverified.',
        'Not an atomic process snapshot; target memory and modules may change during collection.',
        'Uniqueness applies only to CE-readable memory in this scan, not other builds or hook compatibility.',
        'No source scripts, symbol callbacks, includes or macros are executed. Computed expressions can remain unresolved.',
        'Up to 256 addresses per AOB; byte and instruction context omitted because CE disassembly may invoke unaudited callbacks/overrides.',
        'Instruction boundaries, ownership, restore-before-free, overwrite length and relocation safety remain unverified.',
        'CE scan memory-type preferences and unreadable pages can limit coverage; no complete address-space accessibility claim.',
        'Table Lua is unavailable: no audited passive source; Lua Engine editor contents, external Lua files, closures and arbitrary globals are not captured.'})}
    Env.capture(api,r)
    r.semantics_profile=Semantics.profile(r.ce_version)
    if mode~='process' then CT.capture(api,r,mode=='selected') end
    r.dependency_summary=Dependencies.summarize(r.dependencies)
    if mode=='validate' or mode=='export' then AOB.validate(api,r) end
    r.completed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
    if U.call(api,'getOpenedProcessID')~=r.target.pid then
      U.warn(r,'PROCESS-CHANGED','Process changed during collection; runtime results invalidated.')
      for _,a in ipairs(r.aobs) do a.status='invalidated';a.uniqueness='unverified';a.match_count=U.null;a.matches=U.array();a.hook_candidates=U.array();a.matches_truncated=false end
    end
    Core.last_report=r
    return r
  end)
end
function Core.export(path) return Export.write(Core.analyze('export'),path) end
function Core.listDumpModules()
  assert(not Core.state.busy,'CESuite is busy')
  return ModuleDump.list(api)
end
function Core.dumpModule(name,path,options) return Core.state.run(function() return ModuleDump.write(api,name,path,options) end) end
function Core.shutdown() Core.state.shutdown();Core.viewer=nil;Core.memo=nil;Core.status='stopped' end
function Core.showReport(report) return UI.showReport(Core,api,report) end
function Core.install()
  if Core.status=='ready' then return Core end
  assert(Core.status~='loading','CESuite menu is already loading')
  Core.status='loading'
  local ok,err=pcall(UI.install,Core,api)
  if not ok then Core.shutdown();error(err) end
  Core.status='ready'
  return Core
end
return Core
