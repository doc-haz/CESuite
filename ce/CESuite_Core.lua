-- Entry point receives a private module loader and the CE API from the bundle.
local U=require('util')
local Env=require('environment')
local CT=require('ct')
local AOB=require('aob')
local Disasm=require('disassembly')
local Export=require('exporter')
local Life=require('lifecycle')
local Core={version='0.1.0',schema_version='0.1',state=Life.new()}
function Core.analyze(mode)
  return Core.state.run(function()
    local r={schema_version=Core.schema_version,core_version=Core.version,
      generated_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),mode=mode,observation_only=true,
      records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),diagnostics=U.array(),
      limitations=U.array({'Not an atomic process snapshot; target memory and modules may change during collection.',
        'Uniqueness applies only to CE-readable memory in this scan, not other builds or hook compatibility.',
        'No source scripts, symbol callbacks, includes or macros are executed. Computed expressions can remain unresolved.',
        'Up to 256 addresses per AOB; context for first 8 matches and first 8 resolved hook candidates.',
        'Instruction boundaries, ownership, restore-before-free, overwrite length and relocation safety remain unverified.',
        'CE scan memory-type preferences and unreadable pages can limit coverage; no complete address-space accessibility claim.',
        'Table Lua is an editor snapshot; external Lua files, closures and arbitrary globals are not captured.'})}
    Env.capture(api,r)
    if mode~='process' then CT.capture(api,r,mode=='selected') end
    if mode=='validate' or mode=='export' then AOB.validate(api,r,Disasm.capture) end
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
function Core.shutdown() Core.state.shutdown();Core.viewer=nil;Core.memo=nil end
function Core.showReport(report)
  if not Core.viewer then
    Core.viewer=Core.state.own(api.createForm(false))
    Core.viewer.Caption='CESuite observation report'
    Core.viewer.Width=900;Core.viewer.Height=650
    Core.memo=api.createMemo(Core.viewer)
    Core.memo.Parent=Core.viewer;Core.memo.Align='alClient'
    Core.memo.ReadOnly=true;Core.memo.ScrollBars='ssBoth';Core.memo.WordWrap=false
  end
  Core.memo.Lines.Text=Export.encode(report)
  Core.viewer.show()
end
function Core.install()
  local parent=api.getMainForm().Menu
  local menu=Core.state.own(api.createMenuItem(parent));menu.Caption='CESuite'
  parent.Items.add(menu)
  local function command(caption,callback)
    local item=api.createMenuItem(menu);item.Caption=caption
    item.OnClick=function()
      local ok,result=pcall(callback)
      if not ok then api.showMessage('CESuite: '..tostring(result)) end
    end
    menu.add(item)
  end
  local function inspect(mode)
    local r=Core.analyze(mode)
    Core.showReport(r)
  end
  command('Analyze Current Process',function() inspect('process') end)
  command('Analyze Loaded Table',function() inspect('table') end)
  command('Validate AOBs',function() inspect('validate') end)
  command('Inspect Selected Script',function() inspect('selected') end)
  command('Export ChatGPT Report',function()
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName='CESuite_Runtime_Report.json';dialog.DefaultExt='json';dialog.Filter='JSON report|*.json'
      dialog.Options='[ofOverwritePrompt,ofPathMustExist]'
      if dialog.execute() then Core.export(dialog.FileName);api.showMessage('CESuite report saved: '..dialog.FileName) end
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)
  command('Remove CESuite Menu',function() Core.shutdown() end)
  return Core
end
return Core
