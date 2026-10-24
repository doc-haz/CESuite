package.path = 'ce/modules/?.lua;' .. package.path
local U = require('util')
local LuaStatic = require('luastatic')

local tests = 0
local function test(name, fn)
  fn()
  tests = tests + 1
  print('PASS ' .. name)
end

local function eq(a, b)
  assert(a == b, tostring(a) .. ' ~= ' .. tostring(b))
end

test('normalize patterns with spaces, lower/upper, wildcards', function()
  eq(LuaStatic.normalize('48 8B 05 ?? ?? ?? ??'), '48 8B 05 ?? ?? ?? ??')
  eq(LuaStatic.normalize('488b05xxxxxxxx'), '48 8B 05 ?? ?? ?? ??')
  eq(LuaStatic.normalize('48 8B 05 ** ** ** **'), '48 8B 05 ?? ?? ?? ??')
  eq(LuaStatic.normalize(''), nil)
  eq(LuaStatic.normalize('1'), nil)
  eq(LuaStatic.normalize('ZZ ZZ'), nil)
end)

test('literals concat alias and table index in Lua static analysis', function()
  local src = "local a='48'; local b=a..'8B'; local t={p=b..'xx'}; aobScan(t.p)"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 1)
  eq(obs[1].pattern, '48 8B ??')
  eq(obs[1].status, 'source-candidate')
  eq(obs[1].sink, 'aobScan')
  eq(obs[1].confidence, 'lexical')
end)

test('positional args preserved when intermediate args unresolved (aobScanRegion)', function()
  local src = "aobScanRegion('sym_reg', start, start+size, '48 8B 05 ??')"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 1)
  eq(obs[1].pattern, '48 8B 05 ??')
  eq(obs[1].symbol, 'sym_reg')
  eq(obs[1].sink, 'aobScanRegion')
  eq(obs[1].scope, 'region')
  eq(obs[1].status, 'source-candidate')
end)

test('all sink forms extract pattern and symbol properly', function()
  local src = "aobScan('AA BB'); aobScanModule('game','CC DD'); aobScanModule('s_mod','game','EE FF'); aobScanRegion('s_reg',start,stop,'11 22'); customScan('s_cst','33 44',1)"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 5)
  eq(obs[1].pattern, 'AA BB')
  eq(obs[1].symbol, U.null)
  eq(obs[1].scope, 'unknown')

  eq(obs[2].pattern, 'CC DD')
  eq(obs[2].symbol, U.null)
  eq(obs[2].scope, 'module')

  eq(obs[3].pattern, 'EE FF')
  eq(obs[3].symbol, 's_mod')
  eq(obs[3].scope, 'module')

  eq(obs[4].pattern, '11 22')
  eq(obs[4].symbol, 's_reg')
  eq(obs[4].scope, 'region')

  eq(obs[5].pattern, '33 44')
  eq(obs[5].symbol, 's_cst')
  eq(obs[5].scope, 'unknown')
end)

test('wrapper Register.multiCustomScan with nested rows and unknown patterns', function()
  local src = "local t={bad={{type(x)=='a' and start}}, good={{'s','48xx',1,start,size}}, dynamic={{'d',f()}}}; Register.multiCustomScan(t)"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 2)
  eq(obs[1].symbol, 's')
  eq(obs[1].pattern, '48 ??')
  eq(obs[1].status, 'source-candidate')
  eq(obs[1].scope, 'wrapper-unknown')

  eq(obs[2].symbol, 'd')
  eq(obs[2].pattern, U.null)
  eq(obs[2].status, 'unknown')
  eq(obs[2].scope, 'wrapper-unknown')
end)

test('reassignments, unknown functions and forward references stay unresolved', function()
  local src = "local a='AA'; a='BB'; aobScan(a); local b=unknownFunc(); aobScan(b); aobScan(forwardRef); local forwardRef='CC'"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 3)
  eq(obs[1].pattern, U.null)
  eq(obs[1].status, 'unknown')
  eq(obs[2].pattern, U.null)
  eq(obs[2].status, 'unknown')
  eq(obs[3].pattern, U.null)
  eq(obs[3].status, 'unknown')
end)

test('unlinked library declarations with Sig', function()
  local src = "Obj.Sig = '55 48 89 E5'; UE.Sig.Player = '48 83 EC 28'"
  local obs = LuaStatic.analyzeSource(src, 'test')
  eq(#obs, 2)
  eq(obs[1].sink, 'unlinked-library-declaration')
  eq(obs[1].pattern, '55 48 89 E5')
  eq(obs[2].sink, 'unlinked-library-declaration')
  eq(obs[2].pattern, '48 83 EC 28')
end)

test('diagnostics emitted when static limits are hit instead of silent 0 observations', function()
  -- Unterminated string
  local scripts = {
    { language = 'Lua', id = 'bad_script', text = "local s = 'unterminated" }
  }
  local observations, diagnostics, limitations = LuaStatic.analyze(scripts)
  eq(#observations, 0)
  eq(#diagnostics, 1)
  eq(diagnostics[1].rule, 'LUA-STATIC-LIMIT')
  eq(diagnostics[1].severity, 'warning')
  assert(diagnostics[1].message:find('unterminated string'))
  eq(diagnostics[1].script_id, 'bad_script')
end)

test('enrichReport requires explicit suiteVersion (fail-closed)', function()
  local ok, err = pcall(function()
    LuaStatic.enrichReport({}, nil, nil)
  end)
  assert(not ok, 'enrichReport should fail without suiteVersion')
  assert(err:find('suite version required'), 'error message should mention suite version required')

  ok, err = pcall(function()
    LuaStatic.enrichReport({}, '', nil)
  end)
  assert(not ok, 'enrichReport should fail with empty suiteVersion')
  assert(err:find('suite version required'), 'error message should mention suite version required')
end)

print(string.format('%d direct luastatic tests passed', tests))
