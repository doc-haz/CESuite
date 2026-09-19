local Export=require('exporter')
local M={}

function M.showReport(Core,api,report)
  if not Core.viewer then
    Core.viewer=Core.state.own(api.createForm(false))
    Core.viewer.Caption='CESuite observation report'
    Core.viewer.Width=900
    Core.viewer.Height=650

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

  command('Export ChatGPT Report',function()
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
end

return M
