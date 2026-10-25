package.path='ce/modules/?.lua;'..package.path
-- Static dataflow tests for 030B. Text only: no CE, no load, no execution.
local D=require('dynamic')
local Export=require('exporter')

local tests=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(a,b,label)
  assert(a==b,(label or 'value')..': expected '..tostring(b)..' got '..tostring(a))
end
local function read(path)
  local f=assert(io.open(path,'rb'))
  local t=f:read('*a');f:close();return t
end
local function analyze(text,opts)
  opts=opts or {}
  return D.analyze({{script_id=opts.script_id or 'probe',text=text}},opts)
end
local function dep(result,name)
  for _,d in ipairs(result.dependencies) do if d.name==name then return d end end
end
local function has_edge(result,relation,from,to)
  for _,e in ipairs(result.edges) do
    if e.relation==relation and e.from==from and (not to or e.to==to) then return e end
  end
end
local function candidates(result,kind)
  local n=0
  for _,p in ipairs(result.patterns) do if p.kind==kind then n=n+1 end end
  return n
end

local SCRIPT95=read('ce/tests/fixtures/dynamic/script95.lua')
local UE=read('ce/tests/fixtures/dynamic/ue.lua')
local LOADER=read('ce/tests/fixtures/dynamic/loader.lua')
local function analyze95()
  return D.analyze({{script_id='script-95',text=SCRIPT95}},{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}},
    loader=LOADER,loader_script_id='script-1'
  })
end

test('local scalar is scoped local',function()
  local r=analyze("local x = 1\nprint(x)")
  eq(dep(r,'x').scope,'local')
  eq(dep(r,'x').provenance,'lua_local')
  eq(dep(r,'print').scope,'global')
end)

test('local table with nested rows yields one candidate',function()
  local r=analyze("local t = { ['K'] = { {'symA', '90 90'} } }\nRegister.onEnable(t)")
  eq(#r.patterns,1)
  eq(r.patterns[1].kind,'literal_pattern')
  eq(r.patterns[1].symbol,'symA')
  eq(r.patterns[1].consumer,'Register.onEnable')
  eq(r.counts.entries,1)
  eq(r.counts.specs,1)
end)

test('numeric and string table keys keep entry order',function()
  local r=analyze("local t = { ['B'] = { {'b','91'} }, ['A'] = { {'a','92'} } }\nRegister.onEnable(t)")
  eq(r.counts.entries,2)
  eq(r.patterns[1].symbol,'b')
  eq(r.patterns[2].symbol,'a')
end)

test('array index member reference resolves through a helper table',function()
  local r=analyze("local t = { ['K'] = { {'s', UE.Sig.GEnigne[2]} } }\nRegister.onEnable(t)",{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}}})
  eq(r.patterns[1].kind,'derived_pattern')
  eq(r.patterns[1].status,'candidate')
  eq(r.patterns[1].derivation.path,'UE.Sig.GEnigne[2]')
  eq(r.patterns[1].derivation.source_file,'ue.lua')
end)

test('member reference resolves through a helper table',function()
  local r=analyze("local t = { ['K'] = { {'s', UE.Sig.FName} } }\nRegister.onEnable(t)",{
    helpers={{name='UE',alias='Obj',text=UE,file='ue.lua'}}})
  eq(r.patterns[1].kind,'derived_pattern')
  eq(r.patterns[1].pattern,'48xxxxxxxxxxxxEBxx48xxxxxxxxxxxxE8xxxxxxxxC6')
end)

test('local shadowing does not collapse scopes',function()
  local r=analyze("local x = 1\nlocal function f()\n  local x = 'inner'\n  print(x)\nend\nprint(x)")
  local refs={}
  for _,d in ipairs(r.dependencies) do if d.name=='x' then refs[#refs+1]=d end end
  eq(#refs>=2,true)
  for _,d in ipairs(refs) do eq(d.scope,'local') end
end)

test('unresolved wrapper argument is reported, not guessed',function()
  local r=analyze("Register.onEnable(mysteryTable)")
  local found=false
  for _,u in ipairs(r.unresolved) do if u.code=='UNRESOLVED_WRAPPER_ARGUMENT' then found=true end end
  assert(found,'UNRESOLVED_WRAPPER_ARGUMENT expected')
  eq(#r.patterns,0)
end)

test('wrapper passes_to and nested forwarding edges exist',function()
  local r=analyze("local t = { ['K'] = { {'s','90'} } }\nRegister.onEnable(t)")
  assert(has_edge(r,'passes_to','t','Register.onEnable'),'passes_to expected')
  assert(has_edge(r,'calls','Register.onEnable','register.multicustomscan'),'calls expected')
  assert(has_edge(r,'constructs','register.multicustomscan','aobScanRegion'),'constructs expected')
end)

test('loader bindings become providers and include edges',function()
  local r=analyze95()
  local provider={}
  for _,p in ipairs(r.providers) do provider[p]=true end
  for _,name in ipairs({'Register','UE','Starter','Recorder'}) do
    assert(provider[name],'provider '..name..' missing')
  end
  assert(has_edge(r,'includes','script-1','UE.lua'),'include edge expected')
end)

test('unresolved helper reference stays unresolved and is not linked',function()
  local r=analyze("local t = { ['K'] = { {'s', UE.Sig.FName} } }\nRegister.onEnable(t)")
  eq(r.patterns[1].kind,'derived_pattern')
  eq(r.patterns[1].status,'unresolved')
  eq(r.patterns[1].pattern,nil)
  local found=false
  for _,u in ipairs(r.unresolved) do if u.code=='UNRESOLVED_DERIVED' then found=true end end
  assert(found,'UNRESOLVED_DERIVED expected')
end)

test('literal pattern carries bytes and no runtime promotion',function()
  local r=analyze("local t = { ['K'] = { {'s','48 8B 05 ??'} } }\nRegister.onEnable(t)")
  eq(r.patterns[1].pattern_length,4)
  eq(r.patterns[1].runtime_validated,false)
  eq(r.counts.runtime_validated,0)
end)

test('symbol_only rows are not converted into patterns',function()
  local r=analyze("local t = { ['K'] = { {'s'} } }\nRegister.onEnable(t)")
  eq(r.patterns[1].kind,'symbol_only')
  eq(r.patterns[1].pattern,nil)
  eq(r.counts.candidates,0)
end)

test('conditional expression is preserved as unresolved',function()
  local r=analyze("local t = { ['K'] = { {(type(LaunchUEInfoScanner) == 'function') and start} } }\nRegister.onEnable(t)")
  eq(r.patterns[1].kind,'conditional_pattern')
  eq(r.patterns[1].status,'unresolved')
  eq(#r.patterns[1].dependencies>=1,true)
  eq(r.patterns[1].runtime_validated,false)
end)

test('duplicate pattern instances are preserved',function()
  local r=analyze95()
  local seen={}
  for _,p in ipairs(r.patterns) do
    if p.symbol=='func_give_item' then seen[#seen+1]=p end
  end
  eq(#seen,2)
  eq(seen[1].pattern,seen[2].pattern)
  assert(seen[1].id~=seen[2].id,'instance ids must differ')
end)

test('no callback provenance is invented',function()
  local r=analyze95()
  for _,e in ipairs(r.edges) do assert(e.provenance~='callback','unexpected callback edge') end
  local d=dep(r,'DhaosCollider')
  eq(d.scope,'local')
  eq(d.provenance,'lua_local')
end)

test('script-95 fixture matches the acceptance counts',function()
  local r=analyze95()
  local c=r.counts
  eq(c.entries,47)
  eq(c.specs,52)
  eq(c.literal,28)
  eq(c.literal_unique,27)
  eq(c.derived,3)
  eq(c.conditional,1)
  eq(c.symbol_only,21)
  eq(c.symbol_only_pure,20)
  eq(c.unique_symbols,30)
  eq(c.candidates,31)
  eq(c.runtime_validated,0)
  eq(#r.unresolved,1)
  eq(r.unresolved[1].name,'LaunchUEInfoScanner')
  eq(candidates(r,'literal_pattern'),28)
  eq(candidates(r,'derived_pattern'),3)
  eq(candidates(r,'conditional_pattern'),1)
  eq(candidates(r,'symbol_only'),20)
end)

test('script-95 literals and derived keep stable source lines',function()
  local r=analyze95()
  local first,derived
  for _,p in ipairs(r.patterns) do
    if p.kind=='literal_pattern' and p.symbol=='read_inventory' then first=p end
    if p.kind=='derived_pattern' and p.symbol=='write_GEngine' then derived=p end
  end
  eq(first.source_line,21)
  eq(derived.source_line,12)
  eq(derived.derivation.source_line~=nil,true)
end)

test('same input produces identical deterministic result',function()
  local a=analyze95()
  local b=analyze95()
  eq(#a.patterns,#b.patterns)
  eq(#a.edges,#b.edges)
  for i=1,#a.patterns do
    eq(a.patterns[i].id,b.patterns[i].id)
    eq(a.patterns[i].kind,b.patterns[i].kind)
    eq(a.patterns[i].source_line,b.patterns[i].source_line)
  end
end)

test('token limit fails closed with a limit result',function()
  local r=analyze("local t = { {'s','90'} }\nRegister.onEnable(t)",{limits={max_tokens=5}})
  eq(r.status,'limit_reached')
  local found=false
  for _,u in ipairs(r.unresolved) do if u.code=='PARSE_LIMIT' or u.code=='TABLE_LIMIT' then found=true end end
  assert(found,'limit evidence expected')
end)

test('numeric array rows keep order and count specs',function()
  local r=analyze("local t = { ['K'] = { {'a','90'}, {'b','91'} } }\nRegister.onEnable(t)")
  eq(r.counts.entries,1)
  eq(r.counts.specs,2)
  eq(r.patterns[1].symbol,'a')
  eq(r.patterns[2].symbol,'b')
end)

test('candidate exposes multiple provenance edges',function()
  local r=analyze95()
  local c
  for _,p in ipairs(r.patterns) do if p.kind=='literal_pattern' then c=p;break end end
  assert(c,'literal candidate expected')
  eq(#c.provenance>=2,true)
  assert(has_edge(r,'constructs',c.consumer,'aobScanRegion'),'constructs edge expected')
  assert(has_edge(r,'provides',c.consumer,c.symbol),'provides edge expected')
end)

test('constructed AA is provenance, not execution',function()
  local r=analyze95()
  assert(has_edge(r,'constructs','register.multicustomscan','aobScanRegion'),'AA construct edge expected')
  for _,p in ipairs(r.patterns) do eq(p.runtime_validated,false) end
  eq(r.counts.runtime_validated,0)
end)

test('no candidate is promoted to runtime validated',function()
  local r=analyze95()
  for _,p in ipairs(r.patterns) do
    eq(p.runtime_validated,false)
    assert(p.status~='runtime_validated','runtime promotion is forbidden')
  end
end)

test('embedded blocks merge with preserved line numbers',function()
  local sources=D.sources_from_scripts({
    {id='x',language='AA'},
    {id='x-lua-2',language='Lua',parent_script_id='x',line=2,
      text="local t = {\n  ['K'] = { {'s','90'} }\n}"},
    {id='x-lua-9',language='Lua',parent_script_id='x',line=9,
      text='Register.onEnable(t)'}
  })
  eq(#sources,1)
  local r=D.analyze(sources,{})
  eq(r.counts.specs,1)
  eq(r.patterns[1].symbol,'s')
  eq(r.patterns[1].source_line,3)
end)

test('script-95 dynamic result encodes as JSON',function()
  local r=analyze95()
  local ok,json=pcall(Export.encode,r)
  assert(ok,'Export.encode failed: '..tostring(json))
  assert(json:find('"conditional_expression"',1,true),'condition representation missing')
  assert(json:find('LaunchUEInfoScanner',1,true),'condition dependency missing')
end)

test('conditional public representation is stable and JSON-safe',function()
  local r=analyze95()
  local c
  for _,p in ipairs(r.patterns) do if p.kind=='conditional_pattern' then c=p;break end end
  assert(c and c.condition,'conditional candidate expected')
  eq(c.condition.kind,'conditional_expression')
  eq(type(c.condition.text),'string')
  eq(c.condition.resolution,'unknown')
  eq(type(c.condition.dependencies),'table')
  eq(c.condition.dependencies[1],'LaunchUEInfoScanner')
  eq(c.condition.fallback,'start')
  eq(c.runtime_validated,false)
  eq(getmetatable(c.condition.dependencies).__json_array,true)
end)

test('max_entries produces TABLE_LIMIT and limit_reached',function()
  local r=analyze("local t = { a=1, b=2, c=3 }\nRegister.onEnable(t)",{limits={max_entries=2}})
  eq(r.status,'limit_reached')
  local found=false
  for _,u in ipairs(r.unresolved) do if u.code=='TABLE_LIMIT' then found=true end end
  assert(found,'TABLE_LIMIT expected')
end)

test('exact duplicate edges are deduplicated',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t); Register.onEnable(t)")
  local n=0
  for _,e in ipairs(r.edges) do
    if e.relation=='passes_to' and e.from=='t' and e.to=='Register.onEnable' then n=n+1 end
  end
  eq(n,1)
end)

test('different lines and different relations are not deduplicated',function()
  local r=analyze("local t = { ['K'] = { {'a','90'} } }\nRegister.onEnable(t)\nRegister.onEnable(t)")
  local n=0
  for _,e in ipairs(r.edges) do
    if e.relation=='passes_to' and e.from=='t' and e.to=='Register.onEnable' then n=n+1 end
  end
  eq(n,2)
  local requires=0
  for _,e in ipairs(r.edges) do if e.relation=='requires' and e.to=='Register' then requires=requires+1 end end
  eq(requires>=1,true)
end)

print(string.format('%d dynamic tests passed (text-only, no execution)',tests))
