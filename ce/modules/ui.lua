local Export=require('exporter')
local SnapshotUI=require('snapshotui')
local M={}

local function present(Core,api,text)
  if not Core.viewer then
    Core.viewer=Core.state.own(api.createForm(false))
    Core.viewer.Caption='CESuite observation report'
    Core.viewer.Width=900
    Core.viewer.Height=650

    Core.viewer.OnClose=function()
      return caHide
    end

    Core.memo=api.createMemo(Core.viewer)
    Core.memo.Parent=Core.viewer
    Core.memo.Align='alClient'
    Core.memo.ReadOnly=true
    Core.memo.ScrollBars='ssBoth'
    Core.memo.WordWrap=false
  end

  if Core.memo.Lines then
    Core.memo.Lines.Text=text
  else
    Core.memo.Text=text
  end

  Core.viewer.show()
end

function M.showReport(Core,api,report)
  present(Core,api,Export.encode(report))
end

function M.showText(Core,api,text)
  assert(type(text)=='string','Text report required')
  present(Core,api,text)
end

local function memoSet(memo,text)
  if memo.Lines then memo.Lines.Text=text else memo.Text=text end
end

local function selectedMemoryViewerAddress(api)
  if type(api.getMemoryViewForm)~='function' then return nil end
  local ok,form=pcall(api.getMemoryViewForm)
  if not ok or not form then return nil end
  local dv
  pcall(function() dv=form.DisassemblerView or form.Disassemblerview end)
  local address=dv and dv.SelectedAddress
  if type(address)=='number' then return address end
  return nil
end

-- Read-only Address Evidence Inspector. Everything happens on explicit click;
-- nothing is collected in the background and no CE hook is installed.
local function openAddressInspector(Core,api,initial)
  if Core.address_form then
    Core.address_form.show()
    if type(initial)=='number' then
      Core.address_edit.Text=string.format('0x%X',initial)
      Core.address_refresh()
    end
    return
  end
  local form=Core.state.own(api.createForm(false))
  Core.address_form=form
  form.Caption='CESuite Address Evidence Inspector'
  form.Width=900
  form.Height=650
  form.OnClose=function() return caHide or 0 end

  local edit=api.createEdit(form)
  edit.Parent=form
  edit.Align='alTop'
  edit.Height=26
  edit.Text=type(initial)=='number' and string.format('0x%X',initial) or ''
  Core.address_edit=edit

  local panel=api.createPanel(form)
  panel.Parent=form
  panel.Align='alTop'
  panel.Height=34

  local memo=api.createMemo(form)
  memo.Parent=form
  memo.Align='alClient'
  memo.ReadOnly=true
  memo.ScrollBars='ssBoth'
  memo.WordWrap=false
  Core.address_memo=memo

  local current=nil
  local function inspectCurrent()
    local ok,result=pcall(function()
      return Core.inspectAddress(edit.Text or '',{bytes=32})
    end)
    if not ok then
      api.showMessage('CESuite: '..tostring(result))
      return
    end
    current=result
    memoSet(memo,Export.encode(result))
  end
  Core.address_refresh=inspectCurrent

  local function button(caption,left,width,onclick)
    local item=api.createButton(panel)
    item.Parent=panel
    item.Left=left
    item.Top=4
    item.Width=width
    item.Height=26
    item.Caption=caption
    item.OnClick=onclick
    return item
  end

  button('Inspect',8,80,inspectCurrent)
  button('Use Memory Viewer Selection',96,190,function()
    local address=selectedMemoryViewerAddress(api)
    if not address then
      api.showMessage('CESuite: no address is selected in Memory Viewer.')
      return
    end
    edit.Text=string.format('0x%X',address)
    inspectCurrent()
  end)
  button('Copy JSON',294,100,function()
    if type(api.writeToClipboard)~='function' then
      api.showMessage('CESuite: clipboard API is unavailable.')
      return
    end
    local text=current and Export.encode(current) or ''
    api.writeToClipboard(text)
    api.showMessage('CESuite address evidence copied to the clipboard.')
  end)
  button('Export JSON',402,110,function()
    local evidence=current
    if not evidence then
      local ok,result=pcall(function()
        return Core.inspectAddress(edit.Text or '',{bytes=32})
      end)
      if not ok then
        api.showMessage('CESuite: '..tostring(result))
        return
      end
      evidence=result
      current=result
      memoSet(memo,Export.encode(result))
    end
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName='CESuite_Address_Evidence.json'
      dialog.DefaultExt='json'
      dialog.Filter='JSON evidence|*.json'
      dialog.Options='[ofOverwritePrompt,ofPathMustExist]'
      if dialog.execute() then
        Core.exportAddressEvidence(evidence,dialog.FileName)
        api.showMessage('CESuite address evidence saved: '..dialog.FileName)
      end
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)
  button('Close',520,80,function() form.hide() end)

  form.show()
  if edit.Text~='' then inspectCurrent() end
end

-- Native Cheat Engine menu icons. CESuite never modifies the host ImageList: it
-- only references images that CE already loaded, through MenuItem.ImageIndex.
-- The mapping is validated per CE version; unknown versions stay text-only.
local NATIVE_ICONS={
  ['7.72']={
    ['Analyze Current Process']=7,      -- Open Process
    ['Analyze Loaded Table']=3,         -- Open File
    ['Validate AOBs']=8,                -- Add scan tab
    ['Inspect Selected Script']=10,     -- Show Cheat Table Lua Script
    ['Address Evidence Inspector']=17,  -- Set custom crosshair
    ['Dependency Summary']=9,           -- Add file
    ['Diagnostics Summary']=2,          -- Settings
    ['Export Analysis Report']=4,       -- Save
    ['Export Reports']=5,               -- Save As
    ['Export Module Dump']=38,          -- Save scan session
    ['Static Lua AOB Analysis']=10,     -- Show Cheat Table Lua Script
    ['Export Static Lua Report']=4,     -- Save
    ['Remove CESuite Menu']=0,          -- Clear list
    ['About CESuite']=11                -- About
  }
}

local function nativeIconMapping(api)
  if type(api.getCEVersion)~='function' or type(api.getMainForm)~='function' then
    return nil
  end
  local okVersion,value=pcall(api.getCEVersion)
  if not okVersion then return nil end
  local version
  if type(value)=='number' then version=string.format('%.2f',value)
  elseif type(value)=='string' then version=value end
  if version==nil then return nil end
  local mapping=NATIVE_ICONS[version]
  if mapping==nil then return nil end
  local okForm,form=pcall(api.getMainForm)
  if not okForm or form==nil then return nil end
  local menu=form.Menu
  local images=menu and menu.Images
  if images==nil then return nil end
  local okCount,count=pcall(function() return images.Count end)
  if not okCount or type(count)~='number' or count<=0 then return nil end
  local validated={}
  for caption,index in pairs(mapping) do
    if type(index)=='number' and index>=0 and index<count then
      validated[caption]=index
    end
  end
  if next(validated)==nil then return nil end
  return validated
end

function M.install(Core,api)
  local parent=api.getMainForm().Menu

  for i=0,(parent.Items.Count or 0)-1 do
    assert(
      parent.Items[i].Name~='CESuiteCoreMenu',
      'CESuite menu already exists; restart CE'
    )
  end

  local menu=Core.state.own(api.createMenuItem(parent))
  menu.Caption='CESuite'
  menu.Name='CESuiteCoreMenu'
  parent.Items.add(menu)

  -- Cheat Engine may still be building its main ImageList while autorun runs, so
  -- the mapping is applied at creation and once more after startup (one-shot
  -- timer that destroys itself). Unknown versions or missing lists stay iconless.
  local icon_items={}
  local native_icons=nativeIconMapping(api)
  local function applyNativeIcons()
    local mapping=nativeIconMapping(api)
    for caption,item in pairs(icon_items) do
      local index=mapping and mapping[caption]
      pcall(function()
        item.ImageIndex=(type(index)=='number') and index or -1
      end)
    end
  end
  applyNativeIcons()

  local function command(caption,callback)
    local item=api.createMenuItem(menu)
    item.Caption=caption

    item.OnClick=function()
      local ok,result=pcall(callback)
      if not ok then
        api.showMessage('CESuite: '..tostring(result))
      end
    end

    menu.add(item)
    icon_items[caption]=item
    local index=native_icons and native_icons[caption]
    if type(index)=='number' then
      pcall(function() item.ImageIndex=index end)
    else
      -- Unknown CE version, missing host ImageList or unmapped command: no icon.
      pcall(function() item.ImageIndex=-1 end)
    end
  end

  local function separator()
    local item=api.createMenuItem(menu)
    -- Delphi/VCL renders a menu item whose caption is "-" as a real separator.
    item.Caption='-'
    menu.add(item)
    -- Explicitly iconless even if CE ever assigns a default index.
    pcall(function() item.ImageIndex=-1 end)
  end

  local function inspect(mode)
    local r=Core.analyze(mode)
    Core.showReport(r)
  end

  command('Analyze Current Process',function()
    inspect('process')
  end)

  command('Analyze Loaded Table',function()
    inspect('table')
  end)

  command('Validate AOBs',function()
    inspect('validate')
  end)

  command('Inspect Selected Script',function()
    inspect('selected')
  end)

  command('Address Evidence Inspector',function()
    openAddressInspector(Core,api,selectedMemoryViewerAddress(api))
  end)

  separator()

  command('Dependency Summary',function()
    local r=Core.analyze('table')
    Core.showReport({dependency_summary=r.dependency_summary,
      note='Lexical groups only; all unverified. Counts include repeated uses. Occurrence indices refer to dependencies in the full report from this same analysis.'})
  end)

  command('Diagnostics Summary',function()
    local text=Core.simpleText()
    Core.showText(text..Core.operationText())
  end)

  local snapshots=Core.state.own(api.createMenuItem(menu))
  snapshots.Caption='Evidence Snapshots'
  snapshots.Name='CESuiteEvidenceSnapshotsMenu'
  pcall(function() snapshots.ImageIndex=-1 end)
  menu.add(snapshots)
  local function snapshotCommand(caption,callback)
    local item=api.createMenuItem(snapshots)
    item.Caption=caption
    item.OnClick=function()
      local ok,result=pcall(callback)
      if not ok then api.showMessage('CESuite: '..tostring(result)) end
    end
    pcall(function() item.ImageIndex=-1 end)
    snapshots.add(item)
  end
  local function selectSnapshot(Core,api,title)
    local dialog=api.createOpenDialog(api.getMainForm())
    local snapshot,path
    local ok,err=pcall(function()
      dialog.DefaultExt='json'
      dialog.Filter='CESuite evidence snapshot|*.json'
      dialog.Title=title
      dialog.Options='[ofFileMustExist]'
      if not dialog.execute() then return end
      path=dialog.FileName
      local readError
      snapshot,readError=Core.readSnapshot(path)
      if not snapshot then
        error('Snapshot could not be opened.\nReason: '..tostring(readError and readError.code or readError)..'.')
      end
    end)
    dialog.destroy()
    if not ok then error(err) end
    return snapshot,path
  end

  snapshotCommand('Capture Snapshot...',function()
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName='CESuite_Evidence_Snapshot.json'
      dialog.DefaultExt='json'
      dialog.Filter='CESuite evidence snapshot|*.json'
      dialog.Options='[ofOverwritePrompt,ofPathMustExist]'
      if not dialog.execute() then return end
      local snapshot=Core.captureSnapshot()
      local result,writeError=Core.writeSnapshot(snapshot,dialog.FileName,{overwrite=true})
      if not result then error('Snapshot could not be saved.\nReason: '..tostring(writeError and writeError.message or writeError)) end
      api.showMessage('CESuite evidence snapshot saved:\n'..dialog.FileName..'\nID: '..snapshot.snapshot_id)
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)
  snapshotCommand('Open Snapshot...',function()
    local dialog=api.createOpenDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.DefaultExt='json'
      dialog.Filter='CESuite evidence snapshot|*.json'
      dialog.Options='[ofFileMustExist]'
      if not dialog.execute() then return end
      local snapshot,readError=Core.readSnapshot(dialog.FileName)
      if not snapshot then
        error('Snapshot could not be opened.\nReason: '..tostring(readError and readError.code or readError)..'.')
      end
      Core.showText(SnapshotUI.render(snapshot))
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)
  snapshotCommand('Compare Snapshots...',function()
    local a=selectSnapshot(Core,api,'Select snapshot A')
    if not a then return end
    local b=selectSnapshot(Core,api,'Select snapshot B')
    if not b then return end
    Core.showText(SnapshotUI.renderDiff(Core.compareSnapshots(a,b)))
  end)

  snapshotCommand('Explain Comparison...',function()
    local a=selectSnapshot(Core,api,'Select snapshot A')
    if not a then return end
    local b=selectSnapshot(Core,api,'Select snapshot B')
    if not b then return end
    local report,advisorError=Core.explainComparison(a,b)
    if not report then
      error('Advisor report unavailable.\n'..Core.renderAdvisorError(advisorError,advisorError and advisorError.errors))
    end
    local shown,showError=Core.showAdvisor(report)
    if not shown then error('Advisor report unavailable.\n'..Core.renderAdvisorError(showError,showError and showError.errors)) end
  end)

  separator()

  command('Export Analysis Report',function()
    local dialog=api.createSaveDialog(api.getMainForm())

    local ok,err=pcall(function()
      dialog.FileName='CESuite_Runtime_Report.json'
      dialog.DefaultExt='json'
      dialog.Filter='JSON report|*.json'
      dialog.Options='[ofOverwritePrompt,ofPathMustExist]'

      if dialog.execute() then
        Core.export(dialog.FileName)
        api.showMessage('CESuite report saved: '..dialog.FileName)
      end
    end)

    dialog.destroy()

    if not ok then
      error(err)
    end
  end)

  command('Export Reports',function()
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName='CESuite_Report'
      dialog.DefaultExt='md'
      dialog.Filter='CESuite reports|*.md'
      dialog.Options='[ofPathMustExist]'
      if not dialog.execute() then return end
      local result=Core.exportReports(dialog.FileName,{confirmOverwrite=function(files)
        local answer=api.messageDialog('These report files already exist:\n'..table.concat(files,'\n')..
          '\n\nReplace them?',
          api.mtConfirmation or 3,api.mbYes or 0,api.mbNo or 1)
        return answer==(api.mrYes or 6)
      end})
      if result.status=='cancelled' then
        api.showMessage('CESuite: overwrite cancelled; existing reports were kept.')
      elseif result.status=='complete' then
        api.showMessage('CESuite reports saved:'..
          '\nSimple: '..result.simple..
          '\nExtensive: '..result.extensive..
          (result.retained_backups and
            ('\nPrevious copies retained as '..'.cesuite-backup files.') or ''))
      else
        api.showMessage('CESuite: '..(result.error or 'Report export failed')..
          '\nNo report files were changed.')
      end
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)

  command('Export Module Dump',function()
    local modules=Core.listDumpModules()
    assert(#modules>0,'No modules available')
    local name=api.inputQuery('Export Module Dump',
      'Attached module name (exact filename):',modules[1].Name)
    if not name or name=='' then return end
    local selected
    for _,module in ipairs(modules) do
      if module.Name:lower()==name:lower() then selected=module;break end
    end
    assert(selected,'Choose a module loaded in the attached process')
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName=selected.Name:gsub('[<>:"/\\|?*]','_')..'.module.bin'
      dialog.DefaultExt='bin'
      dialog.Filter='Mapped module image|*.bin'
      dialog.Options='[ofPathMustExist]'
      if not dialog.execute() then return end
      local progress=api.createForm(false)
      local cancelled=false
      local report
      local dumped,dumpError=pcall(function()
        progress.Caption='CESuite — Export Module Dump'
        progress.Width=470;progress.Height=160
        progress.OnClose=function() cancelled=true;return 0 end
        local label=api.createLabel(progress)
        label.Parent=progress;label.Left=12;label.Top=12
        label.Caption='Preparing module dump...'
        local bar=api.createProgressBar(progress)
        bar.Parent=progress;bar.Left=12;bar.Top=40;bar.Width=430
        bar.Min=0;bar.Max=100
        local cancel=api.createButton(progress)
        cancel.Parent=progress;cancel.Left=12;cancel.Top=78
        cancel.Caption='Cancel'
        cancel.OnClick=function() cancelled=true;cancel.Enabled=false end
        progress.show()
        report=Core.dumpModule(selected.Name,dialog.FileName,{confirmOverwrite=function(files)
          local result=api.messageDialog('These files already exist:\n'..table.concat(files,'\n')..
            '\n\nReplace them? Previous files will be kept with a .previous suffix.',
            api.mtConfirmation or 3,api.mbYes or 0,api.mbNo or 1)
          return result==(api.mrYes or 6)
        end,progress=function(done,total)
          bar.Position=math.floor(done*100/total)
          label.Caption=string.format('%.1f / %.1f MiB (%d%%)',done/1048576,total/1048576,bar.Position)
          -- Explicit export only; Core.state blocks reentrant analysis, dumping
          -- and shutdown while CE processes button/paint events.
          api.processMessages()
          return not cancelled
        end})
      end)
      progress.destroy()
      if not dumped then error(dumpError) end
      if report.status=='cancelled' then
        api.showMessage('CESuite: overwrite cancelled; existing files were kept.')
        return
      end
      api.showMessage('CESuite module dump: '..report.status..
        '\nBytes written: '..tostring(report.bytes_written)..' / '..tostring(report.size)..
        '\nFile: '..report.file..'\nMetadata: '..dialog.FileName..'.json'..
        (report.previous_files and '\nPrevious outputs retained with .previous suffixes (see metadata).' or '')..
        (report.error and ('\nReason: '..report.error) or '')..
        '\nMapped memory image; not a reconstructed executable. Not an atomic snapshot.')
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)

  command('Static Lua AOB Analysis',function()
    local r=Core.analyzeStaticLua()
    Core.showReport(r)
  end)

  command('Export Static Lua Report',function()
    local dialog=api.createSaveDialog(api.getMainForm())
    local ok,err=pcall(function()
      dialog.FileName='CESuite_Runtime_Report_enriched.json'
      dialog.DefaultExt='json'
      dialog.Filter='JSON report|*.json'
      dialog.Options='[ofOverwritePrompt,ofPathMustExist]'
      if dialog.execute() then
        Core.exportEnriched(dialog.FileName)
        api.showMessage('CESuite static Lua report saved: '..dialog.FileName)
      end
    end)
    dialog.destroy()
    if not ok then error(err) end
  end)

  separator()

  command('Remove CESuite Menu',function()
    Core.shutdown()
  end)

  separator()

  command('About CESuite',function()
    api.showMessage(
      'CESuite '..Core.version..
      ' | '..Core.status..
      ' | '..tostring(Core.distribution)
    )
  end)

  -- Re-apply once after startup: CE finishes populating its main ImageList after
  -- autorun scripts run, so high indices (e.g. 38) are only valid later.
  if type(api.createTimer)=='function' then
    local ok,timer=pcall(api.createTimer,nil,false)
    if ok and timer~=nil then
      Core.icon_timer=timer
      local armed=pcall(function()
        timer.Interval=750
        timer.OnTimer=function(handle)
          handle.Enabled=false
          pcall(function() handle.destroy() end)
          if Core.icon_timer==handle then Core.icon_timer=nil end
          pcall(applyNativeIcons)
        end
        timer.Enabled=true
      end)
      if not armed then
        Core.icon_timer=nil
        pcall(function() timer.destroy() end)
      end
    end
  end
end

return M
