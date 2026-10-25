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
local Address=require('address')
local Dynamic=require('dynamic')
local Coverage=require('coverage')
local Operations=require('operations')
local Core={identity='CESuiteCore',version='0.3.0',schema_version='0.1',status='stopped',state=Life.new()}
local function tableHelpers()
  local helpers=U.array()
  local function add(name,alias)
    local ok,tf=pcall(api.findTableFile,name)
    if not ok or not tf or not tf.stream then return end
    local okText,text=pcall(api.readStringLocal,tf.stream.memory,tf.stream.size)
    if okText and type(text)=='string' and text~='' then
      helpers[#helpers+1]={name=name:gsub('%.lua$',''),alias=alias,text=text,file=name}
    end
  end
  add('UE.lua','Obj')
  add('Register.lua','Register')
  return helpers
end

local function dynamicFor(report, options)
  local sources=Dynamic.sources_from_scripts(report and report.scripts or {})
  if #sources==0 then return nil end
  options=options or {}
  if not options.helpers then
    local helpers=tableHelpers()
    if #helpers>0 then
      options={helpers=helpers,limits=options.limits,universe_known=options.universe_known}
    end
  end
  return Dynamic.analyze(sources,options)
end

local function sourceBytes(r)
  local total=0
  for _,script in ipairs(r.scripts or {}) do
    if type(script.text)=='string' then total=total+#script.text end
  end
  return total
end

local function collectReport(mode)
  local operation=Operations.new('analysis')
  local started=Operations.begin()
  local r={schema_version=Core.schema_version,core_version='0.1.9',
    generated_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),mode=mode,observation_only=true,
    operation=operation,
    records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),dependencies=U.array(),diagnostics=U.array(),
    limitations=U.array({'Dependencies are partial lexical occurrences, not resolved cross-script links or runtime availability; provides/requires remain unverified.',
      'Not an atomic process snapshot; target memory and modules may change during collection.',
      'Uniqueness applies only to CE-readable memory in this scan, not other builds or hook compatibility.',
      'No source scripts, symbol callbacks, includes or macros are executed. Computed expressions can remain unresolved.',
      'Up to 256 addresses per AOB; byte and instruction context omitted because CE disassembly may invoke unaudited callbacks/overrides.',
      'Instruction boundaries, ownership, restore-before-free, overwrite length and relocation safety remain unverified.',
      'CE scan memory-type preferences and unreadable pages can limit coverage; no complete address-space accessibility claim.',
      'Table Lua is unavailable: no audited passive source; Lua Engine editor contents, external Lua files, closures and arbitrary globals are not captured.'})}
  local parseStart=Operations.begin()
  Env.capture(api,r)
  r.semantics_profile=Semantics.profile(r.ce_version)
  if mode~='process' then CT.capture(api,r,mode=='selected') end
  Operations.stage(operation,'parse_ms',parseStart,'parse')
  r.dependency_summary=Dependencies.summarize(r.dependencies)
  local scanStart=Operations.begin()
  local stats={attempted=0,completed=0,truncated=false}
  if mode=='validate' or mode=='export' then stats=AOB.validate(api,r) end
  Operations.stage(operation,'scan_ms',scanStart,'scan')
  operation.metrics.items_total=#r.aobs
  operation.metrics.items_processed=stats.completed
  operation.metrics.operations_attempted=stats.attempted
  operation.metrics.operations_completed=stats.completed
  operation.metrics.source_bytes=sourceBytes(r)
  r.completed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
  local changed=false
  if U.call(api,'getOpenedProcessID')~=r.target.pid then
    changed=true
    U.warn(r,'PROCESS-CHANGED','Process changed during collection; runtime results invalidated.')
    for _,a in ipairs(r.aobs) do a.status='invalidated';a.uniqueness='unverified';a.match_count=U.null;a.matches=U.array();a.hook_candidates=U.array();a.matches_truncated=false end
  end
  local attached=r.target and r.target.attached==true and
    type(r.modules)=='table' and #r.modules>0
  local items_total=#r.aobs
  local items_complete=(items_total==0) or (stats.completed>=items_total)
  operation.source_complete=attached and not changed and not stats.truncated and items_complete
  operation.partial=stats.attempted>0 and stats.completed<stats.attempted
  if not attached then
    operation.status='unavailable'
    Operations.warn(operation,'RUNTIME_SOURCE_UNAVAILABLE',
      'No proven live target was available; runtime evidence was not captured.','capture')
  end
  if changed then
    Operations.warn(operation,'PROCESS_CHANGED_DURING_CAPTURE',
      'The opened process changed before collection completed.','capture')
  end
  if stats.truncated then
    Operations.warn(operation,'MATCHES_TRUNCATED',
      'At least one AOB match list was truncated at the documentation limit.','scan')
  end
  Operations.finish(operation,started,'analysis')
  Operations.finalize(operation)
  local dynamic=dynamicFor(r)
  r.coverage=Coverage.for_runtime(r,dynamic,{})
  if dynamic then
    r.dynamic_analysis=dynamic
  end
  Core.last_operation=operation
  Core.last_report=r
  return r
end
function Core.analyze(mode)
  return Core.state.run(function()
    return collectReport(mode)
  end)
end
function Core.analyzeStaticLua(options)
  return Core.state.run(function()
    local operation=Operations.new('static_lua')
    local started=Operations.begin()
    local r={schema_version=Core.schema_version,core_version='0.1.9',
      generated_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),mode='table',observation_only=true,
      records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),dependencies=U.array(),diagnostics=U.array(),
      limitations=U.array({
        'Static Lua source candidates only; original runtime aobs and match counts are unchanged.',
        'Library signature declarations remain unlinked when object initialization is unknown.',
        'No target, Lua, cheats, wrappers or scan APIs were executed.',
        'Static source observations are separate from memory-verified AOB matches.'
      })}
    local parseStart=Operations.begin()
    Env.capture(api,r)
    r.semantics_profile=Semantics.profile(r.ce_version)
    CT.capture(api,r,false)
    Operations.stage(operation,'parse_ms',parseStart,'parse')
    local staticStart=Operations.begin()
    local observations,diagnostics,limitations=LuaStatic.analyze(r.scripts)
    Operations.stage(operation,'scan_ms',staticStart,'static_lua')
    operation.metrics.items_total=#observations
    operation.metrics.items_processed=#observations
    operation.metrics.source_bytes=sourceBytes(r)
    operation.metrics.operations_attempted=1
    operation.metrics.operations_completed=1
    operation.source_complete=(r.ct and r.ct.status=='captured') and true or false
    local patterns={}
    for _,obs in ipairs(observations) do
      if obs.pattern and obs.pattern~=U.null then
        patterns[obs.pattern]=true
      end
    end
    local uniqueCount=0
    for _ in pairs(patterns) do uniqueCount=uniqueCount+1 end
    r.completed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
    Operations.finish(operation,started,'static_lua')
    Operations.finalize(operation)
    local staticReport={
      title='CESuite Static Lua AOB Analysis',
      core_version='0.1.9',
      suite_version=Core.version,
      ce_version=r.ce_version,
      generated_at=r.generated_at,
      completed_at=r.completed_at,
      observation_only=true,
      operation=operation,
      target=r.target,
      candidate_count=#observations,
      unique_pattern_count=uniqueCount,
      observations=observations,
      diagnostics=diagnostics,
      limitations=limitations
    }
    local dynamic=dynamicFor(r,options)
    if dynamic then staticReport.dynamic_analysis=dynamic end
    staticReport.coverage=Coverage.for_static(dynamic,r.scripts,{})
    Core.last_static_report=staticReport
    return staticReport
  end)
end
-- Explicit static Lua report export (0.3.0-dev). Analysis is read-only text.
function Core.exportStaticLuaReport(path,options)
  assert(type(path)=='string' and path~='','Choose a destination')
  local report=Core.analyzeStaticLua(options)
  return Export.write(report,path)
end
function Core.export(path)
  return Core.state.run(function()
    local r=collectReport('export')
    local written,timing=Export.writeTimed(r,path)
    Core.last_export_operation=Operations.exportOperation(timing)
    r.export_operation=Core.last_export_operation
    return written
  end)
end
function Core.exportEnriched(path)
  return Core.state.run(function()
    local r=collectReport('export')
    LuaStatic.enrichReport(r, nil, Core.version)
    local written,timing=Export.writeTimed(r,path)
    Core.last_export_operation=Operations.exportOperation(timing)
    r.export_operation=Core.last_export_operation
    return written
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
-- Operational telemetry for the last analysis/export. This is separate from
-- the evidence report and never changes its statuses.
function Core.operationText()
  local operation=Core.last_operation or (Core.last_report and Core.last_report.operation)
  return Operations.render(operation,Core.last_export_operation)
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
local function fileBytes(path)
  local f=io.open(path,'rb')
  if not f then return U.null end
  local size=f:seek('end')
  f:close()
  return type(size)=='number' and size or U.null
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
    local operation=Operations.new('export')
    local started=Operations.begin()
    local function finishOperation(status)
      operation.metrics.duration_ms=Operations.elapsed(started)
      operation.metrics.export_ms=operation.metrics.duration_ms
      operation.status=status
      operation.source_complete=(status=='complete')
      operation.metrics.items_total=2
      operation.metrics.items_processed=(status=='complete') and 2 or 0
      operation.metrics.operations_attempted=2
      operation.metrics.operations_completed=(status=='complete') and 2 or 0
      return Operations.finalize(operation)
    end
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
        operation.cancelled=true
        finishOperation('cancelled')
        return {status='cancelled',simple=simplePath,extensive=extensivePath,
          error='Overwrite declined; existing reports were kept.',operation=operation}
      end
    end
    local function failed(message)
      removeQuietly(simpleTemp);removeQuietly(extensiveTemp)
      finishOperation('failed')
      return {status='failed',simple=simplePath,extensive=extensivePath,
        error=message,operation=operation}
    end
    -- Reserved names must never be deleted blind: if one already exists we
    -- cannot prove we created it, so the export fails closed.
    for _,reserved in ipairs({simpleTemp,extensiveTemp}) do
      if fileExists(reserved) then
        finishOperation('failed')
        return {status='failed',simple=simplePath,extensive=extensivePath,
          error='Reserved temporary file already exists: '..reserved,operation=operation}
      end
    end
    local r=collectAssessed()
    local simpleStart=Operations.begin()
    local okSimple,failureSimple=SimpleReport.write(SimpleReport.render(r.assessment,r),simpleTemp)
    local simpleMs=Operations.elapsed(simpleStart)
    if not okSimple or not fileExists(simpleTemp) then
      return failed('Could not write the simple report: '..tostring(failureSimple))
    end
    local okExt,writtenExt,timingExt=pcall(Export.writeTimed,r,extensiveTemp)
    if not okExt or not fileExists(extensiveTemp) then
      return failed('Could not write the extensive report: '..tostring(writtenExt))
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
    local simpleBytes=fileBytes(simplePath)
    local extensiveBytes=fileBytes(extensivePath)
    operation.metrics.serialize_ms=timingExt and timingExt.serialize_ms or U.null
    local writeMs=U.null
    if type(simpleMs)=='number' then writeMs=simpleMs end
    if timingExt and type(timingExt.write_ms)=='number' then
      writeMs=(writeMs or 0)+timingExt.write_ms
    end
    operation.metrics.write_ms=writeMs
    if type(simpleBytes)=='number' and type(extensiveBytes)=='number' then
      operation.metrics.export_bytes=simpleBytes+extensiveBytes
    end
    finishOperation('complete')
    Core.last_export_operation=operation
    return {status='complete',simple=simplePath,extensive=extensivePath,
      counts=r.assessment.counts,operation=operation,
      retained_backups=retained>0 and retained or nil}
  end)
end
-- Address evidence: explicit, read-only inspection of one address. It is never
-- called from collectReport() and never writes memory or sets breakpoints.
function Core.inspectAddress(input,options)
  return Core.state.run(function()
    local evidence=Address.inspect(api,input,options)
    Core.last_address_evidence=evidence
    return evidence
  end)
end
function Core.exportAddressEvidence(evidence,path)
  assert(type(evidence)=='table','Address evidence required')
  assert(type(path)=='string' and path~='','Choose a destination')
  return Core.state.run(function()
    return Export.write(evidence,path)
  end)
end
function Core.listDumpModules()
  assert(not Core.state.busy,'CESuite is busy')
  return ModuleDump.list(api)
end
function Core.dumpModule(name,path,options) return Core.state.run(function() return ModuleDump.write(api,name,path,options) end) end
function Core.shutdown()
  -- Stop the one-shot icon refresh before the menu items disappear.
  if Core.icon_timer then
    pcall(function() Core.icon_timer.Enabled=false end)
    pcall(function() Core.icon_timer.destroy() end)
    Core.icon_timer=nil
  end
  Core.state.shutdown()
  Core.viewer=nil;Core.memo=nil;Core.status='stopped'
  Core.address_form=nil;Core.address_edit=nil;Core.address_memo=nil;Core.address_refresh=nil
end
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
