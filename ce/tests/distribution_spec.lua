-- Execute the actual extracted ZIP and CT Lua using synthetic CE objects only.
local root=assert(CESUITE_TEST_PACKAGE):gsub('\\','/')
local autorun=root..'/autorun/CESuite_Autorun.lua'
local portable=root..'/portable.lua'
local tests=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local menus,messages,created,failAt
local function reset()
  CESuiteCore=nil;CESuiteLoading=nil
  menus={Count=0};messages={};created=0;failAt=nil
  menus.add=function(item) menus[menus.Count]=item;menus.Count=menus.Count+1 end
  getMainForm=function() return {Menu={Items=menus}} end
  getCEVersion=nil
  createTimer=nil
  getAutorunPath=function() return root..'/autorun/' end
  showMessage=function(message) messages[#messages+1]=message end
  createMenuItem=function(owner)
    created=created+1
    if created==failAt then error('synthetic menu failure') end
    local item={children={}}
    item.add=function(child) item.children[#item.children+1]=child end
    item.destroy=function()
      for i=0,menus.Count-1 do
        if menus[i]==item then
          for j=i,menus.Count-2 do menus[j]=menus[j+1] end
          menus[menus.Count-1]=nil;menus.Count=menus.Count-1;break
        end
      end
    end
    return item
  end
end
local function test(name,fn) reset();fn();tests=tests+1;print('PASS '..name) end
local function item(caption)
  for _,child in ipairs(menus[0].children) do
    if child.Caption==caption then return child end
  end
  error('menu item not found: '..tostring(caption))
end

test('autorun then CT then autorun preserves instance, report and one menu',function()
  local core=assert(dofile(autorun));eq(core.status,'ready');eq(core.distribution,'autorun')
  core.last_report={sentinel=true}
  eq(dofile(portable),core);eq(dofile(autorun),core);eq(core.last_report.sentinel,true)
  eq(menus.Count,1);eq(created,24)
  eq(core.install(),core);eq(menus.Count,1)
end)
test('CT then autorun preserves portable instance',function()
  local core=assert(dofile(portable));eq(dofile(autorun),core);eq(menus.Count,1)
  eq(core.distribution,'portable')
end)

test('static lua menu items trigger analysis and export without executing target code',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    local core=assert(dofile(path))
    local staticCalls,shown=0,nil
    core.analyzeStaticLua=function()
      staticCalls=staticCalls+1
      return {title='CESuite Static Lua AOB Analysis',candidate_count=22}
    end
    core.showReport=function(r) shown=r end
    eq(item('Static Lua AOB Analysis').Caption,'Static Lua AOB Analysis')
    item('Static Lua AOB Analysis').OnClick()
    eq(staticCalls,1);eq(shown.candidate_count,22)

    eq(item('Export Static Lua Report').Caption,'Export Static Lua Report')
    local exported,destroyed=false,0
    createSaveDialog=function()
      return {
        execute=function() return true end,
        destroy=function() destroyed=destroyed+1 end,
        FileName='dummy.json'
      }
    end
    core.exportEnriched=function(p) exported=p end
    item('Export Static Lua Report').OnClick()
    eq(exported,'CESuite_Runtime_Report_enriched.json');eq(destroyed,1)
  end
end)

test('real static lua analyze and exportEnriched run without busy guard conflict',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    getAddressList=function() return {Count=0,getMemoryRecord=function() return nil end} end
    local core=assert(dofile(path))
    local staticReport=core.analyzeStaticLua()
    eq(staticReport.title,'CESuite Static Lua AOB Analysis')
    eq(staticReport.core_version,'0.1.9')
    eq(core.state.busy,false)

    local outPath=root..'/enriched_test_'..core.distribution..'.json'
    local ok,err=pcall(function() return core.exportEnriched(outPath) end)
    assert(ok,'exportEnriched failed: '..tostring(err))
    eq(core.state.busy,false)

    local f=assert(io.open(outPath,'rb'))
    local content=f:read('*a')
    f:close()
    os.remove(outPath)
    assert(#content>0)
    assert(content:find('"static_lua_analysis"',1,true))
    assert(content:find('"core_version":"0.1.9"',1,true))

    local normalPath=root..'/normal_test_'..core.distribution..'.json'
    local okNorm,errNorm=pcall(function() return core.export(normalPath) end)
    assert(okNorm,'export failed after exportEnriched: '..tostring(errNorm))
    eq(core.state.busy,false)
    os.remove(normalPath)
  end
end)

test('diagnostics summary shows the simple report in the viewer',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    getOpenedProcessID=function() return 0 end
    getAddressList=function() return {Count=0,getMemoryRecord=function() return nil end} end
    createForm=function() return {show=function() end,destroy=function() end} end
    createMemo=function() return {} end
    local core=assert(dofile(path))
    eq(item('Diagnostics Summary').Caption,'Diagnostics Summary')
    item('Diagnostics Summary').OnClick()
    assert(core.memo and core.memo.Text and core.memo.Text:find('# CESuite Simple Report',1,true),
      'viewer must show the simple report')
    eq(core.state.busy,false);eq(#messages,0)
  end
end)

test('export reports writes both report files from the real core',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    getOpenedProcessID=function() return 0 end
    getAddressList=function() return {Count=0,getMemoryRecord=function() return nil end} end
    local core=assert(dofile(path))
    local base=root..'/menu_reports_'..core.distribution
    os.remove(base..'_Simple.md');os.remove(base..'_Extensive.json')
    createSaveDialog=function()
      local dialog={destroy=function() end}
      dialog.execute=function() dialog.FileName=base;return true end
      return dialog
    end
    eq(item('Export Reports').Caption,'Export Reports')
    item('Export Reports').OnClick()
    local f=assert(io.open(base..'_Simple.md','rb'))
    local simple=f:read('*a');f:close()
    assert(simple:find('# CESuite Simple Report',1,true),'simple report missing')
    assert(simple:find('Suggested Repair Path',1,true),'repair path missing')
    local g=assert(io.open(base..'_Extensive.json','rb'))
    local extensive=g:read('*a');g:close()
    assert(extensive:find('"assessment"',1,true),'assessment missing from extensive report')
    assert(extensive:find('"schema_version":"0.1"',1,true),'schema version missing')
    assert(extensive:find('"core_version":"0.1.9"',1,true),'core_version must stay 0.1.9')
    assert(#messages>0 and messages[#messages]:find('Simple:',1,true),'expected confirmation message')
    eq(core.state.busy,false)
    os.remove(base..'_Simple.md');os.remove(base..'_Extensive.json')
  end
end)

test('export reports failure and cancellation are reported without throwing',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    local core=assert(dofile(path))
    createSaveDialog=function()
      local dialog={destroy=function() end}
      dialog.execute=function() dialog.FileName='chosen';return true end
      return dialog
    end
    core.exportReports=function() return {status='failed',error='synthetic write failure'} end
    item('Export Reports').OnClick()
    assert(#messages>0,'expected a message')
    assert(messages[#messages]:find('synthetic write failure',1,true),'message must name the failure')
    assert(messages[#messages]:find('No report files were changed',1,true),'message must state files were kept')
    eq(core.state.busy,false)

    core.exportReports=function() return {status='cancelled'} end
    item('Export Reports').OnClick()
    assert(messages[#messages]:find('overwrite cancelled',1,true),'expected cancellation message')
    eq(core.state.busy,false)
  end
end)

test('address evidence inspector opens a read-only form and exports JSON',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    getOpenedProcessID=function() return 0 end
    local memos,edits,buttons={},{},{}
    createForm=function() return {show=function() end,hide=function() end,destroy=function() end} end
    createEdit=function() local e={Text='0x401000'};edits[#edits+1]=e;return e end
    createPanel=function() return {} end
    createMemo=function() local m={};memos[#memos+1]=m;return m end
    createButton=function() local b={};buttons[#buttons+1]=b;return b end
    local core=assert(dofile(path))
    eq(item('Address Evidence Inspector').Caption,'Address Evidence Inspector')
    item('Address Evidence Inspector').OnClick()
    local byCaption={}
    for _,b in ipairs(buttons) do byCaption[b.Caption]=b end
    assert(byCaption.Inspect,'Inspect button missing')
    byCaption.Inspect.OnClick()
    assert(memos[1] and memos[1].Text,'memo text missing')
    assert(memos[1].Text:find('"title":"CESuite Address Evidence"',1,true),'evidence JSON missing')
    local copied
    writeToClipboard=function(text) copied=text end
    byCaption['Copy JSON'].OnClick()
    assert(copied and copied:find('CESuite Address Evidence',1,true),'copy failed')
    local exported=root..'/addr_evidence.json'
    createSaveDialog=function()
      local dialog={destroy=function() end}
      dialog.execute=function() dialog.FileName=exported;return true end
      return dialog
    end
    byCaption['Export JSON'].OnClick()
    local f=assert(io.open(exported,'rb'))
    local json=f:read('*a');f:close()
    os.remove(exported)
    assert(json:find('"schema_version":"0.1"',1,true),'exported JSON missing schema version')
    eq(core.state.busy,false)
  end
end)

test('summary menu refreshes a table analysis in both distributions',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    local core=assert(dofile(path))
    local shown,calls=nil,0
    core.analyze=function(mode)
      eq(mode,'table');calls=calls+1
      return {dependency_summary={{name='GAME_STATE',status='unverified'}}}
    end
    core.showReport=function(report) shown=report end
    eq(item('Dependency Summary').Caption,'Dependency Summary')
    item('Dependency Summary').OnClick()
    eq(calls,1);eq(shown.dependency_summary[1].name,'GAME_STATE')
    eq(shown.dependency_summary[1].status,'unverified');eq(#messages,0)
  end
end)
test('module dump menu is explicit, cancellation safe and destroys dialog',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    local core=assert(dofile(path));local calls,destroyed=0,0
    core.listDumpModules=function() return {{Name='game.exe'}} end
    local progressDestroyed,pumps=0,0
    createForm=function() return {show=function() end,destroy=function() progressDestroyed=progressDestroyed+1 end} end
    createLabel=function() return {} end
    createProgressBar=function() return {} end
    createButton=function() return {} end
    processMessages=function() pumps=pumps+1 end
    core.dumpModule=function(name,file,options)
      eq(name,'game.exe');eq(file,'chosen.bin');calls=calls+1
      eq(options.progress(5,10),true)
      messageDialog=function() return 7 end
      eq(options.confirmOverwrite({'chosen.bin','chosen.bin.json'}),false)
      messageDialog=function() return 6 end
      eq(options.confirmOverwrite({'chosen.bin'}),true)
      return {status='complete',bytes_written=10,size=10,file=file}
    end
    eq(item('Export Module Dump').Caption,'Export Module Dump')
    inputQuery=function() return nil end
    item('Export Module Dump').OnClick();eq(calls,0)
    inputQuery=function() return 'GAME.EXE' end
    local accepted=false
    createSaveDialog=function()
      local dialog={}
      dialog.execute=function() dialog.FileName='chosen.bin';return accepted end
      dialog.destroy=function() destroyed=destroyed+1 end
      return dialog
    end
    item('Export Module Dump').OnClick();eq(calls,0);eq(destroyed,1)
    accepted=true
    item('Export Module Dump').OnClick();eq(calls,1);eq(destroyed,2)
    eq(progressDestroyed,1);eq(pumps,1)
    assert(messages[#messages]:find('complete',1,true))
    core.dumpModule=function() error('synthetic dump failure') end
    item('Export Module Dump').OnClick();eq(destroyed,3)
    eq(progressDestroyed,2)
    assert(messages[#messages]:find('synthetic dump failure',1,true))
  end
end)
test('remove and reload restores one menu and exposes status',function()
  local core=assert(dofile(autorun))
  item('Remove CESuite Menu').OnClick();eq(core.status,'stopped');eq(menus.Count,0)
  eq(dofile(portable),core);eq(core.status,'ready');eq(menus.Count,1)
  item('About CESuite').OnClick();assert(messages[1]:find(core.version,1,true))
end)
test('partial menu failure cleans up and permits retry',function()
  failAt=3
  local core,err=dofile(autorun);eq(core,nil);assert(err);eq(menus.Count,0)
  eq(CESuiteCore,nil);eq(CESuiteLoading,nil);eq(#messages,1)
  failAt=nil;assert(dofile(autorun));eq(menus.Count,1)
end)
test('missing module fails without a partial singleton and can recover',function()
  local path=root..'/autorun/cesuite/aob.lua'
  assert(os.rename(path,path..'.bak'))
  local core,err=dofile(autorun)
  assert(os.rename(path..'.bak',path))
  eq(core,nil);assert(err:find('aob.lua',1,true));eq(CESuiteCore,nil);eq(CESuiteLoading,nil)
  eq(menus.Count,0);assert(dofile(autorun));eq(menus.Count,1)
end)
test('syntax error is reported and can recover',function()
  local path=root..'/autorun/cesuite/ui.lua'
  local f=assert(io.open(path,'rb'));local original=f:read('*a');f:close()
  f=assert(io.open(path,'wb'));f:write('invalid Lua !');f:close()
  local core,err=dofile(autorun)
  f=assert(io.open(path,'wb'));f:write(original);f:close()
  eq(core,nil);assert(err);eq(menus.Count,0);eq(CESuiteLoading,nil)
  assert(dofile(autorun));eq(menus.Count,1)
end)
test('relative path rejected and missing getAutorunPath handled',function()
  getAutorunPath=function() return 'relative/' end
  eq(dofile(autorun),nil);eq(menus.Count,0)
  getAutorunPath=nil;eq(dofile(autorun),nil);eq(#messages,2)
end)
test('absolute paths do not consult ambient require or package.path',function()
  local savedRequire,savedPath=require,package.path
  require=function() error('ambient require must not run') end;package.path=''
  local core,err=dofile(autorun)
  require=savedRequire;package.path=savedPath
  assert(core,err);eq(menus.Count,1)
end)
test('different version preserves existing instance and asks for restart',function()
  local core=assert(dofile(autorun));core.version='999.0.0'
  local again,err=dofile(portable);eq(again,core);assert(err);eq(menus.Count,1)
  eq(#messages,1)
end)
test('foreign or legacy global is preserved',function()
  local foreign={version='0.1.0',shutdown=function() error('do not call') end}
  CESuiteCore=foreign;eq(dofile(autorun),nil);eq(CESuiteCore,foreign);eq(menus.Count,0)
end)
test('reentrant load does not construct another Core',function()
  CESuiteLoading=true;eq(dofile(autorun),nil);eq(menus.Count,0)
end)
test('orphan named menu is preserved without a duplicate',function()
  menus.add({Name='CESuiteCoreMenu'})
  eq(dofile(portable),nil);eq(menus.Count,1);eq(CESuiteCore,nil)
end)
test('final menu order, separators and single menu are exact',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    local core=assert(dofile(path))
    local expected={
      'Analyze Current Process','Analyze Loaded Table','Validate AOBs',
      'Inspect Selected Script','Address Evidence Inspector','-',
      'Dependency Summary','Diagnostics Summary','Evidence Snapshots','-',
      'Export Analysis Report','Export Reports','Export Module Dump',
      'Static Lua AOB Analysis','Export Static Lua Report','-',
      'Remove CESuite Menu','-','About CESuite'}
    eq(menus.Count,1)
    eq(#menus[0].children,#expected)
    for i,caption in ipairs(expected) do
      eq(menus[0].children[i].Caption,caption,'item '..i)
    end
    local commands,separators=0,0
    for _,child in ipairs(menus[0].children) do
      if child.Caption=='-' then separators=separators+1 else commands=commands+1 end
    end
    eq(commands,15)
    eq(separators,4)
    eq(menus[0].children[#expected].Caption,'About CESuite')
    eq(menus[0].children[#expected-2].Caption,'Remove CESuite Menu')
    eq(menus[0].children[#expected-1].Caption,'-')
    eq(menus[0].children[#expected-3].Caption,'-')
    eq(core.status,'ready')
  end
end)
test('Core explain comparison validates and renders advisor evidence',function()
  local core=assert(dofile(portable))
  eq(type(core.explainComparison),'function')
  eq(type(core.renderAdvisor),'function')
  local a,errA=core.readSnapshot('ce/tests/fixtures/corpus/snapshots/pattern-changed-a.json')
  assert(a,errA and errA.code)
  local b,errB=core.readSnapshot('ce/tests/fixtures/corpus/snapshots/pattern-changed-b.json')
  assert(b,errB and errB.code)
  local report,err=core.explainComparison(a,b)
  assert(report,err and err.code)
  local text=core.renderAdvisor(report)
  assert(text:find('PATTERN_CHANGED',1,true))
  assert(text:find('## Overview',1,true))
end)

test('Explain Comparison menu command validates and renders into one read-only memo',function()
  local core=assert(dofile(portable))
  local dialogs=0
  local memo={Lines={}}
  createOpenDialog=function()
    dialogs=dialogs+1
    local path=dialogs==1 and 'ce/tests/fixtures/corpus/snapshots/pattern-changed-a.json'
      or 'ce/tests/fixtures/corpus/snapshots/pattern-changed-b.json'
    return {FileName=path,execute=function() return true end,destroy=function() end}
  end
  createForm=function() return {show=function() end,hide=function() end,destroy=function() end} end
  createMemo=function() return memo end
  local explain=nil;for _,c in ipairs(item('Evidence Snapshots').children) do if c.Caption=='Explain Comparison...' then explain=c end end;assert(explain)
  explain.OnClick()
  eq(dialogs,2)
  assert(memo.Lines.Text:find('## Overview',1,true))
  assert(memo.Lines.Text:find('PATTERN_CHANGED',1,true))
  assert(not memo.Lines.Text:find('table: 0',1,true))
end)

test('Explain pair selection freezes A before selecting B and rejects stale reuse',function()
  local core=assert(dofile(portable))
  local a='ce/tests/fixtures/corpus/snapshots/pattern-changed-a.json'
  local b='ce/tests/fixtures/corpus/snapshots/pattern-changed-b.json'
  local bad='ce/tests/fixtures/corpus/snapshots/corrupt/invalid-json.json'
  local sa=assert(core.readSnapshot(a)).snapshot_id
  local sb=assert(core.readSnapshot(b)).snapshot_id
  local memo={Lines={}};local messages={};local queue={};local qi=1
  showMessage=function(m) messages[#messages+1]=m end
  createForm=function() return {show=function() end,hide=function() end,destroy=function() end} end
  createMemo=function() return memo end
  local shared={FileName='',destroy=function() end}
  shared.execute=function()
    local p=queue[qi];qi=qi+1
    if not p then return false end
    shared.FileName=p;return true
  end
  createOpenDialog=function() return shared end
  local explain=nil;for _,c in ipairs(item('Evidence Snapshots').children) do if c.Caption=='Explain Comparison...' then explain=c end end;assert(explain)
  local function run(paths)
    queue=paths;qi=1;messages={};explain.OnClick()
    return memo.Lines.Text or ''
  end
  local function input(text)
    local x=text:match('Input ID: ([^\n]+)');return x
  end
  local first=run({a,b});assert(input(first),table.concat(messages,'|')..' || '..first);eq(input(first),sa..':'..sb)
  eq(input(run({b,a})),sb..':'..sa)
  eq(input(run({a,a})),sa..':'..sa)
  eq(input(run({b,b})),sb..':'..sb)
  assert(run({a,b}):find('PATTERN_CHANGED',1,true))
  assert(run({b,a}):find('PATTERN_CHANGED',1,true))

  memo.Lines.Text='sentinel'
  run({a,false});eq(memo.Lines.Text,'sentinel')
  run({false});eq(memo.Lines.Text,'sentinel')
  run({a,bad});eq(memo.Lines.Text,'sentinel');assert(#messages>0)
  run({bad,b});eq(memo.Lines.Text,'sentinel');assert(#messages>0)
end)

test('evidence snapshots submenu owns exactly four commands and is removed',function()
  local core=assert(dofile(autorun))
  eq(type(core.captureSnapshot),'function')
  eq(type(core.writeSnapshot),'function')
  eq(type(core.readSnapshot),'function')
  eq(type(core.compareSnapshots),'function')
  local sub=item('Evidence Snapshots')
  eq(#sub.children,4)
  eq(sub.children[1].Caption,'Capture Snapshot...')
  eq(sub.children[2].Caption,'Open Snapshot...')
  eq(sub.children[3].Caption,'Compare Snapshots...')
  eq(sub.children[4].Caption,'Explain Comparison...')
  item('Remove CESuite Menu').OnClick()
  eq(menus.Count,0)
  eq(core.status,'stopped')
  local again=assert(dofile(autorun))
  eq(again.status,'ready')
  eq(#item('Evidence Snapshots').children,4)
end)

test('removing the menu destroys separators and reinstall recreates one ordered menu',function()
  reset()
  local core=assert(dofile(autorun))
  eq(#menus[0].children,19)
  item('Remove CESuite Menu').OnClick()
  eq(menus.Count,0)
  eq(core.status,'stopped')
  local again=assert(dofile(autorun))
  eq(again.status,'ready')
  eq(menus.Count,1)
  eq(#menus[0].children,19)
  eq(menus[0].children[19].Caption,'About CESuite')
  eq(menus[0].children[6].Caption,'-')
end)
local function nativeForm()
  return {Menu={Items=menus,Images={Count=40,Width=16,Height=16}}}
end
local NATIVE_72={
  ['Analyze Current Process']=7,
  ['Analyze Loaded Table']=3,
  ['Validate AOBs']=8,
  ['Inspect Selected Script']=10,
  ['Address Evidence Inspector']=17,
  ['Dependency Summary']=9,
  ['Diagnostics Summary']=2,
  ['Export Analysis Report']=4,
  ['Export Reports']=5,
  ['Export Module Dump']=38,
  ['Static Lua AOB Analysis']=10,
  ['Export Static Lua Report']=4,
  ['Remove CESuite Menu']=0,
  ['About CESuite']=11}

test('native icons apply the validated CE 7.72 mapping',function()
  for _,path in ipairs({autorun,portable}) do
    reset()
    getCEVersion=function() return 7.72 end
    getMainForm=nativeForm
    assert(dofile(path))
    for caption,index in pairs(NATIVE_72) do
      eq(item(caption).ImageIndex,index,'index for '..caption)
      assert(index>=0 and index<40,'index out of range for '..caption)
    end
    eq(item('Remove CESuite Menu').ImageIndex,0)
    eq(item('About CESuite').ImageIndex,11)
    for _,child in ipairs(menus[0].children) do
      if child.Caption=='-' then eq(child.ImageIndex,-1,'separator has an icon') end
    end
    eq(#menus[0].children,19)
  end
end)
test('unknown CE version keeps the menu text-only',function()
  reset()
  getCEVersion=function() return 7.99 end
  getMainForm=nativeForm
  assert(dofile(autorun))
  for _,child in ipairs(menus[0].children) do
    eq(child.ImageIndex,-1,'unexpected icon for '..child.Caption)
  end
  eq(#menus[0].children,19)
  item('About CESuite').OnClick()
  assert(#messages>0)
end)
test('missing host ImageList keeps the menu text-only',function()
  reset()
  getCEVersion=function() return 7.72 end
  getMainForm=function() return {Menu={Items=menus}} end
  assert(dofile(autorun))
  for _,child in ipairs(menus[0].children) do
    eq(child.ImageIndex,-1,'unexpected icon for '..child.Caption)
  end
  eq(#menus[0].children,19)
end)
test('out-of-range mapping entries are dropped, others still apply',function()
  reset()
  getCEVersion=function() return 7.72 end
  getMainForm=function() return {Menu={Items=menus,Images={Count=10}}} end
  assert(dofile(autorun))
  eq(item('Analyze Current Process').ImageIndex,7)
  eq(item('Remove CESuite Menu').ImageIndex,0)
  eq(item('Inspect Selected Script').ImageIndex,-1)
  eq(item('Address Evidence Inspector').ImageIndex,-1)
  eq(item('Export Module Dump').ImageIndex,-1)
  eq(item('About CESuite').ImageIndex,-1)
end)
test('version API failure never breaks the menu',function()
  reset()
  getCEVersion=function() error('version unavailable') end
  getMainForm=nativeForm
  assert(dofile(autorun))
  eq(item('Analyze Current Process').ImageIndex,-1)
  eq(#menus[0].children,19)
  item('Dependency Summary').OnClick()
  eq(#messages,0)
end)
test('remove and recreate applies the native mapping again',function()
  reset()
  getCEVersion=function() return 7.72 end
  getMainForm=nativeForm
  local core=assert(dofile(autorun))
  eq(item('About CESuite').ImageIndex,11)
  item('Remove CESuite Menu').OnClick()
  eq(menus.Count,0)
  local again=assert(dofile(autorun))
  eq(menus.Count,1)
  eq(#menus[0].children,19)
  eq(item('Validate AOBs').ImageIndex,8)
  eq(item('About CESuite').ImageIndex,11)
  eq(again.status,'ready')
end)
test('late ImageList completion re-applies high indices once',function()
  reset()
  local count=38
  local timers={}
  getCEVersion=function() return 7.72 end
  getMainForm=function() return {Menu={Items=menus,Images={Count=count}}} end
  createTimer=function(owner,enabled)
    local timer={destroyed=0}
    timer.destroy=function() timer.destroyed=timer.destroyed+1 end
    timers[#timers+1]=timer
    return timer
  end
  local core=assert(dofile(autorun))
  eq(#timers,1)
  eq(item('Export Module Dump').ImageIndex,-1)
  eq(item('About CESuite').ImageIndex,11)
  count=40
  timers[1].OnTimer(timers[1])
  eq(item('Export Module Dump').ImageIndex,38)
  eq(timers[1].Enabled,false)
  eq(timers[1].destroyed,1)
  eq(core.icon_timer,nil)
end)
test('shutdown destroys the pending icon refresh',function()
  reset()
  local timers={}
  getCEVersion=function() return 7.72 end
  getMainForm=function() return {Menu={Items=menus,Images={Count=40}}} end
  createTimer=function()
    local timer={destroyed=0}
    timer.destroy=function() timer.destroyed=timer.destroyed+1 end
    timers[#timers+1]=timer
    return timer
  end
  local core=assert(dofile(autorun))
  eq(#timers,1)
  item('Remove CESuite Menu').OnClick()
  eq(timers[1].destroyed,1)
  eq(core.icon_timer,nil)
end)
print(string.format('%d distribution tests passed (synthetic CE objects; not live CE)',tests))
