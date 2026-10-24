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
local LuaStatic=require('luastatic')
local Diagnose=require('diagnose')
local SimpleReport=require('simplereport')
local Core={identity='CESuiteCore',version='0.2.1',schema_version='0.1',status='stopped',state=Life.new()}
local function collectReport(mode)
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
end
function Core.analyze(mode)
  return Core.state.run(function()
    return collectReport(mode)
  end)
end
function Core.analyzeStaticLua()
  return Core.state.run(function()
    local r={schema_version=Core.schema_version,core_version='0.1.9',
      generated_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),mode='table',observation_only=true,
      records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),dependencies=U.array(),diagnostics=U.array(),
      limitations=U.array({
        'Static Lua source candidates only; original runtime aobs and match counts are unchanged.',
        'Library signature declarations remain unlinked when object initialization is unknown.',
        'No target, Lua, cheats, wrappers or scan APIs were executed.',
        'Static source observations are separate from memory-verified AOB matches.'
      })}
    Env.capture(api,r)
    r.semantics_profile=Semantics.profile(r.ce_version)
    CT.capture(api,r,false)
    local observations,diagnostics,limitations=LuaStatic.analyze(r.scripts)
    local patterns={}
    for _,obs in ipairs(observations) do
      if obs.pattern and obs.pattern~=U.null then
        patterns[obs.pattern]=true
      end
    end
    local uniqueCount=0
    for _ in pairs(patterns) do uniqueCount=uniqueCount+1 end
    r.completed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
    local staticReport={
      title='CESuite Static Lua AOB Analysis',
      core_version='0.1.9',
      suite_version=Core.version,
      ce_version=r.ce_version,
      generated_at=r.generated_at,
      completed_at=r.completed_at,
      observation_only=true,
      target=r.target,
      candidate_count=#observations,
      unique_pattern_count=uniqueCount,
      observations=observations,
      diagnostics=diagnostics,
      limitations=limitations
    }
    Core.last_static_report=staticReport
    return staticReport
  end)
end
function Core.export(path)
  return Core.state.run(function()
    local r=collectReport('export')
    return Export.write(r,path)
  end)
end
function Core.exportEnriched(path)
  return Core.state.run(function()
    local r=collectReport('export')
    LuaStatic.enrichReport(r, nil, Core.version)
    return Export.write(r,path)
  end)
end
-- Diagnostic layer: interprets the evidence already in a report. Never scans,
-- edits or executes; both reports derive from one assessment object.
function Core.buildAssessment(report)
  local r=report or Core.last_report
  assert(type(r)=='table','No report available; run an analysis first')
  return Diagnose.build(r)
end
local function collectAssessed()
  local r=collectReport('export')
  LuaStatic.enrichReport(r, nil, Core.version)
  local assessment=Diagnose.build(r)
  r.assessment=assessment
  Core.last_assessment=assessment
  return r
end
function Core.simpleText()
  return Core.state.run(function()
    local r=collectAssessed()
    return SimpleReport.render(r.assessment,r)
  end)
end
local function basePath(path)
  local lower=path:lower()
  for _,ext in ipairs({'.json','.md'}) do
    if #path>#ext and lower:sub(-#ext)==ext then return path:sub(1,#path-#ext) end
  end
  return path
end
local function fileExists(path)
  -- Readable or writable means the path exists; 'r+b' never creates or truncates.
  for _,mode in ipairs({'rb','r+b'}) do
    local f=io.open(path,mode)
    if f then f:close();return true end
  end
  return false
end
-- Paired export. Semantics documented in docs/reporting.md:
-- both documents are written to reserved temporary files first and only
-- promoted once both are complete; existing reports are moved aside to
-- reserved backup names until both promotions finish, then removed.
-- A failure restores the previous pair and leaves no partial output.
local PARTIAL_SUFFIX='.cesuite-partial'
local BACKUP_SUFFIX='.cesuite-backup'
local function removeQuietly(path) pcall(os.remove,path) end
function Core.exportReports(path,options)
  assert(type(path)=='string' and path~='','Choose a destination')
  return Core.state.run(function()
    local base=basePath(path)
    local simplePath=base..'_Simple.md'
    local extensivePath=base..'_Extensive.json'
    local simpleTemp=simplePath..PARTIAL_SUFFIX
    local extensiveTemp=extensivePath..PARTIAL_SUFFIX
    local existing=U.array()
    for _,candidate in ipairs({simplePath,extensivePath}) do
      if fileExists(candidate) then existing[#existing+1]=candidate end
    end
    if #existing>0 then
      options=options or {}
      assert(type(options.confirmOverwrite)=='function','Destination reports already exist; overwrite confirmation required')
      if options.confirmOverwrite(existing)~=true then
        return {status='cancelled',simple=simplePath,extensive=extensivePath,
          error='Overwrite declined; existing reports were kept.'}
      end
    end
    local function failed(message)
      removeQuietly(simpleTemp);removeQuietly(extensiveTemp)
      return {status='failed',simple=simplePath,extensive=extensivePath,error=message}
    end
    -- Reserved names must never be deleted blind: if one already exists we
    -- cannot prove we created it, so the export fails closed.
    for _,reserved in ipairs({simpleTemp,extensiveTemp}) do
      if fileExists(reserved) then
        return {status='failed',simple=simplePath,extensive=extensivePath,
          error='Reserved temporary file already exists: '..reserved}
      end
    end
    local r=collectAssessed()
    local okSimple,failureSimple=SimpleReport.write(SimpleReport.render(r.assessment,r),simpleTemp)
    if not okSimple or not fileExists(simpleTemp) then
      return failed('Could not write the simple report: '..tostring(failureSimple))
    end
    local okExt,failureExt=pcall(Export.write,r,extensiveTemp)
    if not okExt or not fileExists(extensiveTemp) then
      return failed('Could not write the extensive report: '..tostring(failureExt))
    end
    -- Both documents are complete; only now touch the destinations.
    local backups,promoted={},{}
    local function rollback()
      for _,target in ipairs(promoted) do removeQuietly(target) end
      for target,backup in pairs(backups) do
        if fileExists(backup) then pcall(os.rename,backup,target) end
      end
      removeQuietly(simpleTemp);removeQuietly(extensiveTemp)
    end
    for _,target in ipairs({simplePath,extensivePath}) do
      if fileExists(target) then
        local backup=target..BACKUP_SUFFIX
        if fileExists(backup) then
          rollback()
          return {status='failed',simple=simplePath,extensive=extensivePath,
            error='Reserved backup file already exists: '..backup}
        end
        local ok,err=os.rename(target,backup)
        if not ok then
          rollback()
          return {status='failed',simple=simplePath,extensive=extensivePath,
            error='Could not preserve the existing report: '..tostring(err)}
        end
        backups[target]=backup
      end
    end
    for _,pair in ipairs({{simpleTemp,simplePath},{extensiveTemp,extensivePath}}) do
      local ok,err=os.rename(pair[1],pair[2])
      if not ok then
        rollback()
        return {status='failed',simple=simplePath,extensive=extensivePath,
          error='Could not finalize the reports: '..tostring(err)}
      end
      promoted[#promoted+1]=pair[2]
    end
    local retained=0
    for _,backup in pairs(backups) do
      if not os.remove(backup) then retained=retained+1 end
    end
    return {status='complete',simple=simplePath,extensive=extensivePath,
      counts=r.assessment.counts,
      retained_backups=retained>0 and retained or nil}
  end)
end
function Core.listDumpModules()
  assert(not Core.state.busy,'CESuite is busy')
  return ModuleDump.list(api)
end
function Core.dumpModule(name,path,options) return Core.state.run(function() return ModuleDump.write(api,name,path,options) end) end
function Core.shutdown() Core.state.shutdown();Core.viewer=nil;Core.memo=nil;Core.status='stopped' end
function Core.showReport(report) return UI.showReport(Core,api,report) end
function Core.showText(text) return UI.showText(Core,api,text) end
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
