local Export=require('exporter')
local M={}

function M.showReport(Core,api,report)
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

  local text=Export.encode(report)

  if Core.memo.Lines then
    Core.memo.Lines.Text=text
  else
    Core.memo.Text=text
  end

  Core.viewer.show()
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

  command('About CESuite',function()
    api.showMessage(
      'CESuite '..Core.version..
      ' | '..Core.status..
      ' | '..tostring(Core.distribution)
    )
  end)

  command('Remove CESuite Menu',function()
    Core.shutdown()
  end)

  command('Dependency Summary',function()
    local r=Core.analyze('table')
    Core.showReport({dependency_summary=r.dependency_summary,
      note='Lexical groups only; all unverified. Counts include repeated uses. Occurrence indices refer to dependencies in the full report from this same analysis.'})
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
end

return M
