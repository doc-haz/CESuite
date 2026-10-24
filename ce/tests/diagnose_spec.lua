package.path='ce/modules/?.lua;'..package.path
-- Deterministic tests for the diagnostic model, the simple report and the
-- paired report export. Synthetic evidence only; no CE and no target access.
local U=require('util')
local Diagnose=require('diagnose')
local Simple=require('simplereport')
local Export=require('exporter')

local tests=0

local function test(name,fn)
  fn()
  tests=tests+1
  print('PASS '..name)
end

local function eq(actual,expected,label)
  assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..' got '..tostring(actual))
end

local function report()
  return {
    schema_version='0.1',core_version='0.1.9',ce_version='7.72',
    generated_at='2026-10-24T00:00:00Z',completed_at='2026-10-24T00:00:01Z',
    mode='export',observation_only=true,
    target={pid=1234,attached=true,name='game.exe',architecture='x64',build_fingerprint=U.null},
    modules=U.array({{name='game.exe',base='0x1000',size=256,path='C:/g/game.exe',architecture='x64'}}),
    records=U.array(),scripts=U.array(),aobs=U.array(),resources=U.array(),
    dependencies=U.array(),diagnostics=U.array(),limitations=U.array(),dependency_summary=U.array()
  }
end

local function aob(fields)
  local a={id='aob-1',script_id='script-1',line=3,section='enable',command='aobscanmodule',
    arguments=U.array({'health','game.exe','48 8B ??'}),symbol='health',scope='module',
    pattern='48 8B ??',syntax_supported=true,status='observed',match_count=0,
    uniqueness='no_match',cross_build_robustness='unverified',matches=U.array(),
    matches_truncated=false,hook_candidates=U.array(),source_applicability='lexical_only',
    scan={start='0x1000',stop='0x1100',protection_flags='*X*C*W',alignment='none',
      method='MemScan/FoundList',stop_semantics='stop argument',error_visibility='available'}}
  for k,v in pairs(fields or {}) do a[k]=v end
  return a
end

local function staticBlock(patterns)
  local observations=U.array()
  for _,p in ipairs(patterns or {}) do
    observations[#observations+1]={script_id='script-1',line=10,sink='aobScan',
      symbol=U.null,pattern=p,raw_pattern=p,status='source-candidate',confidence='lexical',
      provenance='static-lua',evidence=U.array(),scope='unknown',unknowns=U.array(),
      match_count=U.null,uniqueness='unverified'}
  end
  return {version='0.1',suite_version='0.2.1',source={name='game.exe',sha256=string.rep('a',64)},
    runtime_report_sha256=string.rep('b',64),association='synthetic',observations=observations,
    diagnostics=U.array(),limitations=U.array({'static only'})}
end

local function findRule(assessment,rule)
  for _,d in ipairs(assessment.diagnostics) do
    if d.rule==rule then return d end
  end
end

local function ids(assessment)
  local out={}
  for _,step in ipairs(assessment.repair_path) do out[#out+1]=step.diagnostic_id end
  return table.concat(out,'|')
end

test('zero-match runtime evidence produces a high-confidence problem',function()
  local r=report(); r.aobs[1]=aob()
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-NO-MATCH')
  assert(d,'AOB-NO-MATCH missing')
  eq(d.outcome,'problem');eq(d.severity,'high');eq(d.status,'observed')
  eq(d.confidence,'high');eq(d.category,'aob');eq(d.source,'runtime')
  assert(d.summary:find('not found'),'summary must state the signature was not found')
  assert(#d.evidence>0 and d.evidence[1].description:find('zero matches'),'evidence must cite zero matches')
  assert(#d.suggested_next_steps>=3,'expected concrete review steps')
  assert(d.do_not_assume[1]:find('does not prove'),'must refuse to infer removal')
  eq(a.counts.problems,1)
end)

test('single-match scan is a healthy check with no repair step',function()
  local r=report(); r.aobs[1]=aob({match_count=1,uniqueness='unique_current_scan'})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-UNIQUE')
  assert(d,'AOB-UNIQUE missing')
  eq(d.outcome,'healthy');eq(d.status,'observed');eq(d.confidence,'high')
  eq(#a.repair_path,0)
  eq(a.counts.healthy,1)
end)

test('multi-match scan is an ambiguous problem without naming a winner',function()
  local r=report(); r.aobs[1]=aob({match_count=5,uniqueness='multiple_matches'})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-AMBIGUOUS')
  assert(d,'AOB-AMBIGUOUS missing')
  eq(d.severity,'medium');eq(d.outcome,'problem')
  local joined=table.concat(d.suggested_next_steps,' ')
  assert(joined:find('Extend the pattern'),'should suggest extending the pattern')
  assert(d.do_not_assume[1]:find('do not identify'),'must not pick a match')
end)

test('unsupported syntax is reported as not assessed, not as a failure',function()
  local r=report(); r.aobs[1]=aob({status='unsupported',match_count=U.null,uniqueness='unverified'})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-UNSUPPORTED')
  assert(d,'AOB-UNSUPPORTED missing')
  eq(d.outcome,'not_assessed');eq(d.status,'unsupported');eq(d.confidence,'unknown')
end)

test('unresolved scope is a problem with an explicit unknown status',function()
  local r=report(); r.aobs[1]=aob({status='unresolved',match_count=U.null,uniqueness='unverified',
    message='Module name/size unavailable; scope was not broadened.'})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-SCOPE-UNRESOLVED')
  assert(d,'AOB-SCOPE-UNRESOLVED missing')
  eq(d.outcome,'problem');eq(d.status,'unknown');eq(d.confidence,'medium')
  assert(d.do_not_assume[1]:find('not evidence'),'must not claim the signature is wrong')
end)

test('table-only evidence never claims runtime validity',function()
  local r=report(); r.aobs[1]=aob({status='not_scanned',match_count=U.null,uniqueness='unverified'})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-NOT-SCANNED')
  assert(d,'AOB-NOT-SCANNED missing')
  eq(d.outcome,'not_assessed');eq(d.status,'unknown');eq(d.confidence,'unknown')
  assert(d.do_not_assume[1]:find('Runtime validity has not been established'),'must state source-only')
  eq(#a.repair_path,0)
end)

test('unresolved dependency is lexical advisory evidence only',function()
  local r=report()
  r.dependencies[1]={name='PlayerBase',kind='symbol',relation='requires',source='lexical',
    status='unverified',script_id='script-1',line=2,section='enable',command='define'}
  local a=Diagnose.build(r)
  local d=findRule(a,'DEPENDENCY-UNRESOLVED-PROVIDER')
  assert(d,'dependency diagnostic missing')
  eq(d.outcome,'advisory');eq(d.status,'candidate');eq(d.confidence,'low');eq(d.source,'lexical')
  assert(#d.do_not_assume>0,'must state the lexical limitation')
end)

test('a provided dependency produces no diagnostic and no repair step',function()
  local r=report()
  r.dependencies[1]={name='PlayerBase',kind='symbol',relation='provides',source='lexical',
    status='unverified',script_id='script-1',line=1,section='enable',command='registersymbol'}
  r.dependencies[2]={name='PlayerBase',kind='symbol',relation='requires',source='lexical',
    status='unverified',script_id='script-1',line=2,section='enable',command='define'}
  local a=Diagnose.build(r)
  eq(findRule(a,'DEPENDENCY-UNRESOLVED-PROVIDER'),nil)
  eq(#a.repair_path,0)
end)

test('static candidates stay candidates and are never promoted',function()
  local r=report(); r.static_lua_analysis=staticBlock({'CC DD'})
  local a=Diagnose.build(r)
  local d=findRule(a,'STATIC-CANDIDATE-ONLY')
  assert(d,'static diagnostic missing')
  eq(d.status,'candidate');eq(d.outcome,'advisory');eq(d.confidence,'low');eq(d.source,'static')
  for _,x in ipairs(a.diagnostics) do
    if x.source=='static' then assert(x.status~='observed','static evidence promoted to observed') end
    if x.status=='observed' then eq(x.source,'runtime','observed must be runtime') end
  end
end)

test('static candidate corroborated by a runtime scan raises confidence, not status',function()
  local r=report()
  r.aobs[1]=aob({pattern='CC DD',match_count=2,uniqueness='multiple_matches'})
  r.static_lua_analysis=staticBlock({'CC DD'})
  local a=Diagnose.build(r)
  local d=findRule(a,'STATIC-CANDIDATE-ONLY')
  assert(d,'static diagnostic missing')
  eq(d.confidence,'medium');eq(d.status,'candidate')
  local found=false
  for _,e in ipairs(d.evidence) do if e.kind=='runtime_corroboration' then found=true end end
  assert(found,'expected corroboration evidence')
end)

test('empty collection yields an explicit insufficient-evidence result',function()
  local r=report()
  local a=Diagnose.build(r)
  local d=findRule(a,'EVIDENCE-INSUFFICIENT')
  assert(d,'insufficient evidence diagnostic missing')
  eq(d.summary,'Not enough evidence to recommend a repair step.')
  eq(d.confidence,'unknown')
  local text=Simple.render(a,r)
  assert(text:find('Not enough evidence to recommend a repair step.',1,true),'simple report must say so')
end)

test('missing attachment ranks first in the repair path and blocks trust',function()
  local r=report()
  r.target={pid=0,attached=false,name=U.null,architecture='unknown',build_fingerprint=U.null}
  r.aobs[1]=aob({status='unavailable',match_count=U.null,uniqueness='unverified'})
  local a=Diagnose.build(r)
  local d=findRule(a,'PROCESS-NOT-ATTACHED')
  assert(d,'target diagnostic missing')
  eq(d.severity,'high');eq(d.status,'observed');eq(d.source,'runtime')
  assert(a.repair_path[1].diagnostic_id=='target:not-attached','target issue must rank first')
  local unavailable=findRule(a,'AOB-SCAN-UNAVAILABLE')
  assert(unavailable,'expected aggregated unavailable diagnostic')
  eq(unavailable.evidence[1].count,1)
end)

test('process change is reported and invalidated scans are aggregated',function()
  local r=report()
  r.diagnostics[1]={rule='PROCESS-CHANGED',severity='review',message='Process changed during collection.'}
  r.aobs[1]=aob({status='invalidated',match_count=U.null,uniqueness='unverified'})
  local a=Diagnose.build(r)
  assert(findRule(a,'PROCESS-CHANGED'),'process change diagnostic missing')
  local inv=findRule(a,'AOB-INVALIDATED')
  assert(inv,'invalidated aggregate missing')
  eq(inv.evidence[1].count,1)
end)

test('ambiguous module snapshot withholds sizes as a problem',function()
  local r=report()
  r.diagnostics[1]={rule='MODULE-SNAPSHOT-INCOMPLETE',severity='review',
    message='Ambiguous module name game.exe; size lookup omitted.'}
  local a=Diagnose.build(r)
  local d=findRule(a,'MODULE-AMBIGUOUS')
  assert(d,'module ambiguity diagnostic missing')
  eq(d.severity,'medium');eq(d.status,'observed')
  assert(d.do_not_assume[1]:find('null module size'),'must explain null size')
end)

test('other review diagnostics are aggregated once per rule',function()
  local r=report()
  r.diagnostics[1]={rule='HOOK-REVIEW',severity='review',message='Review anchor versus hook.',script_id='script-1',line=4}
  r.diagnostics[2]={rule='HOOK-REVIEW',severity='review',message='Review anchor versus hook.',script_id='script-1',line=9}
  local a=Diagnose.build(r)
  local found,count=0,0
  for _,d in ipairs(a.diagnostics) do
    if d.rule=='HOOK-REVIEW' then found=found+1;count=d.evidence[1] and d.evidence[1].rule and 2 or 1 end
  end
  eq(found,1,'expected one aggregated review diagnostic')
  eq(count,2)
end)

test('confidence degrades when scan error visibility is unavailable',function()
  local r=report()
  r.aobs[1]=aob({uniqueness='unverified',scan={start='0x1000',stop='0x1100',
    protection_flags='*X*C*W',alignment='none',method='MemScan/FoundList',
    stop_semantics='stop argument',error_visibility='unavailable'}})
  local a=Diagnose.build(r)
  local d=findRule(a,'AOB-NO-MATCH')
  assert(d,'AOB-NO-MATCH missing')
  eq(d.confidence,'medium')
end)

test('repair ordering is deterministic regardless of input order',function()
  local function build(reverse)
    local r=report()
    local list={aob({id='aob-1',symbol='zeta',match_count=0,uniqueness='no_match'}),
                aob({id='aob-2',symbol='alpha',match_count=3,uniqueness='multiple_matches'}),
                aob({id='aob-3',symbol='beta',match_count=1,uniqueness='unique_current_scan'})}
    if reverse then list={list[3],list[2],list[1]} end
    for _,a in ipairs(list) do r.aobs[#r.aobs+1]=a end
    r.dependencies[1]={name='Zed',kind='symbol',relation='requires',source='lexical',
      status='unverified',script_id='s',line=1,section='enable',command='define'}
    r.dependencies[2]={name='Able',kind='symbol',relation='requires',source='lexical',
      status='unverified',script_id='s',line=2,section='enable',command='define'}
    if reverse then r.dependencies[1],r.dependencies[2]=r.dependencies[2],r.dependencies[1] end
    return Diagnose.build(r)
  end
  local a=build(false)
  local b=build(true)
  eq(ids(a),ids(b),'repair path order')
  local function actions(t)
    local out={}
    for _,s in ipairs(t.repair_path) do out[#out+1]=s.action end
    return table.concat(out,'||')
  end
  eq(actions(a),actions(b),'repair actions')
  local function diagIds(t)
    local out={}
    for _,d in ipairs(t.diagnostics) do out[#out+1]=d.id end
    return table.concat(out,'|')
  end
  eq(diagIds(a),diagIds(b),'diagnostic order')
end)

test('AOB sink names are not reported as unresolved dependencies',function()
  local r=report()
  for _,name in ipairs({'AOBScan','aobScan','AOBScanModule','AOBScanModuleUnique','aobScanRegion','customScan'}) do
    r.dependencies[#r.dependencies+1]={name=name,kind='symbol',relation='requires',
      source='lexical',status='unverified',script_id='script-1',line=1,section='enable',command='lua'}
  end
  local a=Diagnose.build(r)
  for _,d in ipairs(a.diagnostics) do
    assert(d.rule~='DEPENDENCY-UNRESOLVED-PROVIDER','AOB scan API reported as a table dependency: '..d.id)
  end
end)

test('repair priority follows the documented rule order',function()
  local r=report()
  r.aobs[1]=aob({id='aob-1',symbol='zero',match_count=0,uniqueness='no_match'})
  r.aobs[2]=aob({id='aob-2',symbol='multi',match_count=2,uniqueness='multiple_matches'})
  r.dependencies[1]={name='Needed',kind='symbol',relation='requires',source='lexical',
    status='unverified',script_id='s',line=1,section='enable',command='define'}
  local a=Diagnose.build(r)
  local order={}
  for i,s in ipairs(a.repair_path) do order[i]=s.diagnostic_id end
  eq(order[1],'aob:aob-1','zero-match before ambiguity')
  eq(order[2],'aob:aob-2','ambiguity before dependency')
  eq(order[3],'dependency:Needed','dependency last')
end)

test('simple and extensive presentations share one assessment',function()
  local r=report()
  r.aobs[1]=aob({symbol='HealthHook',match_count=0,uniqueness='no_match'})
  local a=Diagnose.build(r)
  local text=Simple.render(a,r)
  assert(text:find('# CESuite Simple Report',1,true),'missing title')
  assert(text:find('Suggested Repair Path',1,true),'missing repair path section')
  for _,step in ipairs(a.repair_path) do
    assert(text:find(step.action:gsub('%s+$',''),1,true),'repair action missing from simple report: '..step.action)
  end
  for _,d in ipairs(a.diagnostics) do
    if d.outcome=='problem' then
      assert(text:find(d.summary,1,true),'problem summary missing from simple report')
    end
  end
  -- The assessment is the single source: rendering twice is identical.
  eq(Simple.render(a,r),text,'simple rendering must be deterministic')
end)

test('markdown rendering escapes user-controlled labels and patterns',function()
  local r=report()
  r.aobs[1]=aob({symbol='bad`name\n## injected',match_count=0,uniqueness='no_match'})
  local a=Diagnose.build(r)
  local text=Simple.render(a,r)
  assert(not text:find('bad`name',1,true),'backticks must be neutralised')
  assert(not text:find('\n## injected',1,true),'newlines must not inject headings')
end)

test('no-evidence and unsupported states never invent repair advice',function()
  local r=report()
  r.aobs[1]=aob({status='unsupported',match_count=U.null,uniqueness='unverified'})
  local a=Diagnose.build(r)
  local text=Simple.render(a,r)
  assert(text:find('No repair step is suggested',1,true) or text:find('Not assessed',1,true),
    'unsupported evidence must not produce a repair path')
  eq(#a.repair_path,0)
end)

-- Core integration ---------------------------------------------------------
local function mockApi(addresses)
  local api={
    soExactValue=0,vtByteArray=8,rtRounded=0,fsmNotAligned=0,
    getOpenedProcessID=function() return 7 end,
    getCEVersion=function() return 7.72 end,
    targetIs64Bit=function() return true end,
    process='game.exe',
    enumModules=function() return {{Name='game.exe',Address=0x1000,PathToFile='C:/g/game.exe',Is64Bit=true}} end,
    getModuleSize=function() return 0x1000 end,
    vtAutoAssembler=11,
    getAddressList=function()
      return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
        return {ID=1,Description='Health',Type=11,OffsetCount=0,Active=false,
          Script='[ENABLE]\naobscanmodule(health,game.exe,48 8B ??)\n[DISABLE]\ndealloc(health)'}
      end}
    end,
    createMemScan=function()
      return {ErrorString='',firstScan=function() end,waitTillDone=function() end,destroy=function() end}
    end,
    createFoundList=function()
      local a={}
      for i,v in ipairs(addresses or {}) do a[i-1]=v end
      return {Count=#(addresses or {}),Address=a,initialize=function() end,destroy=function() end}
    end
  }
  return api
end

local function loadCore(api)
  return assert(loadfile('ce/CESuite_Core.lua','t',setmetatable({api=api,require=require},{__index=_G})))()
end

local function exists(path)
  local f=io.open(path,'rb');if f then f:close();return true end
  return false
end

test('Core.exportReports writes both reports from one collection and clears busy',function()
  local api=mockApi({}) -- zero matches
  local core=loadCore(api)
  local base=os.tmpname()..'-report'
  local result=core.exportReports(base)
  eq(result.status,'complete')
  assert(exists(result.simple),'simple report not written')
  assert(exists(result.extensive),'extensive report not written')
  local f=assert(io.open(result.simple,'rb'));local text=f:read('*a');f:close()
  assert(text:find('# CESuite Simple Report',1,true),'simple report title missing')
  assert(text:find('AOB  ',1,true) or text:find('not found',1,true),'simple report must describe the problem')
  local g=assert(io.open(result.extensive,'rb'));local json=g:read('*a');g:close()
  assert(json:find('"assessment"',1,true),'extensive report must embed the assessment')
  assert(json:find('"static_lua_analysis"',1,true),'extensive report must embed static Lua evidence')
  assert(json:find('"core_version":"0.1.9"',1,true),'core_version must remain 0.1.9')
  eq(core.state.busy,false)
  -- Subsequent analysis still works (no nested busy guard).
  core.export(result.extensive..'.plain.json')
  eq(core.state.busy,false)
  os.remove(result.simple);os.remove(result.extensive);os.remove(result.extensive..'.plain.json')
end)

test('Core.exportReports refuses silent overwrite and honours decline/confirm',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-overwrite'
  local first=core.exportReports(base)
  eq(first.status,'complete')
  local f=assert(io.open(first.simple,'rb'));local before=f:read('*a');f:close()

  local ok=pcall(function() core.exportReports(base) end)
  assert(not ok,'missing confirmation must fail closed')
  eq(core.state.busy,false)

  local declined=core.exportReports(base,{confirmOverwrite=function() return false end})
  eq(declined.status,'cancelled')
  local g=assert(io.open(first.simple,'rb'));local after=g:read('*a');g:close()
  eq(after,before,'declined overwrite must keep the previous report')

  local seen
  local confirmed=core.exportReports(base,{confirmOverwrite=function(files) seen=#files;return true end})
  eq(confirmed.status,'complete')
  eq(seen,2)
  os.remove(first.simple);os.remove(first.extensive)
end)

test('Core.simpleText renders the same assessment that the extensive report embeds',function()
  local core=loadCore(mockApi({}))
  local text=core.simpleText()
  assert(text:find('# CESuite Simple Report',1,true),'simple text title missing')
  assert(core.last_assessment,'assessment not retained')
  local base=os.tmpname()..'-consistency'
  local result=core.exportReports(base)
  local f=assert(io.open(result.simple,'rb'));local written=f:read('*a');f:close()
  eq(written:find(core.last_assessment.diagnostics[1].summary,1,true)~=nil,true,
    'simple text and written simple report must agree')
  os.remove(result.simple);os.remove(result.extensive)
end)

test('Core.version is 0.2.1 and assessment schema version is stable',function()
  local core=loadCore(mockApi({}))
  eq(core.version,'0.2.1')
  local a=core.buildAssessment({target={attached=false},aobs=U.array(),scripts=U.array(),
    dependencies=U.array(),diagnostics=U.array()})
  eq(a.schema_version,'0.1')
  assert(a.counts.total==#a.diagnostics,'counts.total must match diagnostics')
end)

-- Paired export semantics -------------------------------------------------
local function readFile(path)
  local f=io.open(path,'rb');if not f then return nil end
  local text=f:read('*a');f:close();return text
end

local function writeFile(path,text)
  local f=assert(io.open(path,'wb'),'cannot create '..path)
  f:write(text);f:close()
end

local function reservedLeft(base)
  for _,suffix in ipairs({'.cesuite-partial','.cesuite-backup'}) do
    for _,name in ipairs({'_Simple.md','_Extensive.json'}) do
      if exists(base..name..suffix) then return base..name..suffix end
    end
  end
  return nil
end

local function withStub(module,key,stub,callback)
  local real=module[key]
  module[key]=stub
  local ok,err=pcall(callback)
  module[key]=real
  if not ok then error(err) end
end

test('paired export writes both reports and leaves no temporaries',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-pair'
  local result=core.exportReports(base)
  eq(result.status,'complete')
  assert(exists(result.simple) and exists(result.extensive),'both reports must exist')
  eq(reservedLeft(base),nil,'temporaries or backups left behind')
  eq(core.state.busy,false)
  local simple=readFile(result.simple)
  local extensive=readFile(result.extensive)
  local mdStamp=simple and simple:match('Generated: ([%d%-T:Z]+)')
  local jsonStamp=extensive and extensive:match('"generated_at":"([^"]+)"')
  assert(mdStamp and jsonStamp,'expected timestamps in both reports')
  eq(mdStamp,jsonStamp,'both reports must come from one collection')
  assert(extensive:find('"assessment"',1,true),'assessment missing')
  os.remove(result.simple);os.remove(result.extensive)
end)

test('simple write failure leaves no report and releases busy',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-missing-directory/report'
  local result=core.exportReports(base)
  eq(result.status,'failed')
  assert(result.error and result.error:find('simple',1,true),'error must name the failing document')
  assert(not exists(base..'_Simple.md') and not exists(base..'_Extensive.json'),'no output expected')
  eq(core.state.busy,false)
end)

test('extensive failure after the simple document was written leaves no partial output',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-extfail'
  withStub(Export,'write',function() return nil,'synthetic extensive failure' end,function()
    local result=core.exportReports(base)
    eq(result.status,'failed')
    assert(result.error and result.error:find('extensive',1,true),'error must name the failing document')
  end)
  assert(not exists(base..'_Simple.md'),'simple report must not remain')
  assert(not exists(base..'_Extensive.json'),'extensive report must not exist')
  eq(reservedLeft(base),nil,'temporary files must be removed')
  eq(core.state.busy,false)
end)

test('extensive write raising an error is handled as a controlled failure',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-throw'
  withStub(Export,'write',function() error('synthetic disk full') end,function()
    local result=core.exportReports(base)
    eq(result.status,'failed')
    assert(result.error and result.error:find('disk full',1,true),'underlying error must be reported')
  end)
  assert(not exists(base..'_Simple.md') and not exists(base..'_Extensive.json'))
  eq(core.state.busy,false)
end)

test('failed export preserves the previous pair byte for byte',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-preserve'
  writeFile(base..'_Simple.md','OLD SIMPLE')
  writeFile(base..'_Extensive.json','OLD EXTENSIVE')
  withStub(Export,'write',function() return nil,'synthetic failure' end,function()
    local result=core.exportReports(base,{confirmOverwrite=function(files)
      eq(#files,2,'both existing reports must be offered for confirmation')
      return true
    end})
    eq(result.status,'failed')
  end)
  eq(readFile(base..'_Simple.md'),'OLD SIMPLE','previous simple report must be preserved')
  eq(readFile(base..'_Extensive.json'),'OLD EXTENSIVE','previous extensive report must be preserved')
  eq(reservedLeft(base),nil,'no backup or temporary files may remain')
  eq(core.state.busy,false)
  os.remove(base..'_Simple.md');os.remove(base..'_Extensive.json')
end)

test('successful overwrite replaces both reports and removes backups',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-replace'
  writeFile(base..'_Simple.md','OLD SIMPLE')
  writeFile(base..'_Extensive.json','OLD EXTENSIVE')
  local result=core.exportReports(base,{confirmOverwrite=function() return true end})
  eq(result.status,'complete')
  assert(readFile(base..'_Simple.md'):find('# CESuite Simple Report',1,true),'simple report not replaced')
  assert(readFile(base..'_Extensive.json'):find('"assessment"',1,true),'extensive report not replaced')
  eq(reservedLeft(base),nil,'backups must be removed after success')
  eq(core.state.busy,false)
  os.remove(result.simple);os.remove(result.extensive)
end)

test('only an existing simple report is replaced without touching the other side',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-onlysimple'
  writeFile(base..'_Simple.md','OLD SIMPLE')
  local result=core.exportReports(base,{confirmOverwrite=function(files)
    eq(#files,1);eq(files[1],base..'_Simple.md');return true
  end})
  eq(result.status,'complete')
  assert(readFile(base..'_Simple.md'):find('# CESuite Simple Report',1,true))
  assert(exists(base..'_Extensive.json'),'extensive report must be created')
  eq(reservedLeft(base),nil)
  os.remove(result.simple);os.remove(result.extensive)
end)

test('only an existing extensive report is replaced without touching the other side',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-onlyextensive'
  writeFile(base..'_Extensive.json','OLD EXTENSIVE')
  local result=core.exportReports(base,{confirmOverwrite=function(files)
    eq(#files,1);eq(files[1],base..'_Extensive.json');return true
  end})
  eq(result.status,'complete')
  assert(readFile(base..'_Extensive.json'):find('"assessment"',1,true))
  assert(exists(base..'_Simple.md'),'simple report must be created')
  eq(reservedLeft(base),nil)
  os.remove(result.simple);os.remove(result.extensive)
end)

test('declined overwrite leaves both reports untouched',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-decline'
  writeFile(base..'_Simple.md','OLD SIMPLE')
  writeFile(base..'_Extensive.json','OLD EXTENSIVE')
  local result=core.exportReports(base,{confirmOverwrite=function() return false end})
  eq(result.status,'cancelled')
  eq(readFile(base..'_Simple.md'),'OLD SIMPLE')
  eq(readFile(base..'_Extensive.json'),'OLD EXTENSIVE')
  eq(reservedLeft(base),nil)
  eq(core.state.busy,false)
  os.remove(base..'_Simple.md');os.remove(base..'_Extensive.json')
end)

test('reserved temporary names are never deleted or overwritten',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-reserved-temp'
  writeFile(base..'_Simple.md.cesuite-partial','USER DATA')
  local result=core.exportReports(base)
  eq(result.status,'failed')
  assert(result.error and result.error:find('Reserved temporary',1,true),'expected reserved-name failure')
  eq(readFile(base..'_Simple.md.cesuite-partial'),'USER DATA','reserved file must not be deleted')
  assert(not exists(base..'_Extensive.json'),'no report may be produced')
  eq(core.state.busy,false)
  os.remove(base..'_Simple.md.cesuite-partial')
end)

test('reserved backup names block promotion without deleting user data',function()
  local core=loadCore(mockApi({}))
  local base=os.tmpname()..'-reserved-backup'
  writeFile(base..'_Simple.md','OLD SIMPLE')
  writeFile(base..'_Simple.md.cesuite-backup','USER BACKUP')
  local result=core.exportReports(base,{confirmOverwrite=function() return true end})
  eq(result.status,'failed')
  assert(result.error and result.error:find('Reserved backup',1,true),'expected reserved-backup failure')
  eq(readFile(base..'_Simple.md'),'OLD SIMPLE','existing report must be preserved')
  eq(readFile(base..'_Simple.md.cesuite-backup'),'USER BACKUP','user file must be preserved')
  assert(not exists(base..'_Extensive.json'),'no report may be produced')
  eq(core.state.busy,false)
  os.remove(base..'_Simple.md');os.remove(base..'_Simple.md.cesuite-backup')
end)

print(tests..' diagnose tests passed')
