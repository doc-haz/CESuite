import json
import unittest
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path
import sys
import tempfile
from ct_analyzer.lua_static import ALPHABET, MAX_DEPTH, analyze_lua, embedded_lua, normalize
from ct_analyzer.core import analyze


def encoded(data):
    data = len(data).to_bytes(4, 'little') + data
    compressor = zlib.compressobj(wbits=-15)
    data = compressor.compress(data) + compressor.flush()
    result = ''
    for i in range(0, len(data), 4):
        group = data[i:i+4]
        n = int.from_bytes(group.ljust(4, b'\0'), 'big')
        chars = ''
        for _ in range(5):
            chars = ALPHABET[n % 85] + chars
            n //= 85
        result += chars[:len(group)+1]
    return result


class StaticLuaTests(unittest.TestCase):
    def patterns(self, text):
        return [x['pattern'] for x in analyze_lua(text, 'test')]

    def test_literals_concat_alias_and_index(self):
        self.assertEqual(self.patterns("local a='48'; local b=a..'8B'; local t={p=b..'xx'}; aobScan(t.p)"), ['48 8B ??'])

    def test_all_sink_forms(self):
        self.assertEqual(self.patterns("aobScan('AA BB'); aobScanModule('game','CC DD'); aobScanModule('s','game','EE FF'); aobScanRegion('s',start,start+size,'11 22'); customScan('s','33 44',1)"), ['AA BB','CC DD','EE FF','11 22','33 44'])

    def test_wrapper_nested_rows_unknown_neighbors(self):
        result = analyze_lua("local t={bad={{type(x)=='a' and start}}, good={{'s','48xx',1,start,size}}, dynamic={{'d',f()}}}; Register.multiCustomScan(t)", 'test')
        self.assertEqual([(x['symbol'], x['pattern']) for x in result], [('s','48 ??'),('d',None)])

    def test_onenable_tables(self):
        self.assertEqual(self.patterns("local t={key={{'s','AABB'}}}; Register.onEnable(t)"), ['AA BB'])

    def test_comments_strings_and_function_declarations_are_inert(self):
        self.assertEqual(self.patterns('''-- aobScan('AA')
local s="aobScan('BB')"
--[==[ aobScan('CC') ]==]
function customScan(symbol,pattern) end
aobScan([=[48 8B]=])'''), ['48 8B'])

    def test_unknown_functions_reassignments_cycles_and_forward_refs(self):
        for text in ("local p=f(); aobScan(p)", "local p='AA'; p='BB'; aobScan(p)", "local a=b; local b=a; aobScan(a)", "aobScan(p); local p='AA'", "local p='AA' or 'BB'; aobScan(p)"):
            self.assertEqual(self.patterns(text), [None])

    def test_escaped_strings(self):
        self.assertEqual(self.patterns(r"aobScan('AA\nBB'); aobScan('\x41')"), ['AA BB',None])

    def test_no_execution_and_json_roundtrip(self):
        report = analyze(b'<CheatTable><LuaScript>os.execute("NEVER"); local p="AABB"; aobScan(p)</LuaScript></CheatTable>')
        observation = json.loads(json.dumps(report))['lua_aobs'][0]
        self.assertEqual(observation['pattern'], 'AA BB')
        self.assertIsNone(observation['match_count'])
        self.assertEqual(observation['confidence'], 'lexical')
        self.assertTrue(observation['unknowns'])

    def test_library_declarations_not_linked_by_guess(self):
        result = analyze_lua("Obj.Sig={FName='48xx', versions={'AABB','CCDD'}}; aobScan(UE.Sig.FName)", 'library')
        self.assertIsNone(result[0]['pattern'])
        self.assertEqual([x['pattern'] for x in result[1:]], ['48 ??','AA BB','CC DD'])

    def test_decoder_roundtrip_and_corruption(self):
        for data in (b'',b'a',b'error("MUST NOT EXECUTE")',b'x'*100000):
            root = ET.fromstring('<CheatTable><Files><a.lua Encoding="Ascii85">'+encoded(data)+'</a.lua></Files></CheatTable>')
            self.assertEqual(list(embedded_lua(root)), [('a.lua',data.decode(),None)])
        root.find('./Files/a.lua').text = 'invalid&'
        self.assertIsNotNone(list(embedded_lua(root))[0][2])

    def test_decoder_bomb_and_bad_size_are_unknown(self):
        root = ET.fromstring('<CheatTable><Files><a.lua Encoding="Ascii85"/></Files></CheatTable>')
        root.find('./Files/a.lua').text = encoded(b'x'*(2*1024*1024+1))
        self.assertIn('limit',list(embedded_lua(root))[0][2])

    def test_enrichment_preserves_runtime_and_rejects_overwrite(self):
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
        from enrich_static_aobs import enrich
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            table, runtime, output = (folder / x for x in ('a.CT','runtime.json','output.json'))
            table.write_text('<CheatTable><LuaScript>aobScan("AABB")</LuaScript></CheatTable>')
            baseline = {'aobs':[], 'scripts':[], 'sentinel':{'match_count':7}}
            runtime.write_text(json.dumps(baseline))
            result = enrich(table, runtime, output)
            self.assertEqual({k:result[k] for k in baseline}, baseline)
            self.assertEqual(json.loads(runtime.read_text()), baseline)
            self.assertIsNone(result['static_lua_analysis']['observations'][0]['match_count'])
            with self.assertRaises(ValueError):
                enrich(table, runtime, runtime)

    def test_resource_limits(self):
        with self.assertRaises(ValueError):
            analyze_lua('aobScan('+ '('*(MAX_DEPTH+2)+"'AA'"+')'*(MAX_DEPTH+3), 'deep')
        with self.assertRaises(ValueError):
            analyze_lua('x=1;'*40000, 'tokens')

    def test_normalization(self):
        self.assertEqual(normalize('48xx?f'), '48 ?? ?F')
        for value in ('', 'ABC', '48 GG', 'module.dll', None):
            self.assertIsNone(normalize(value))

    def test_synthetic_fixture_regression(self):
        path = Path(__file__).resolve().parents[2] / 'fixtures/lua-static-synthetic.CT'
        result = analyze(path.read_bytes())['lua_aobs']
        self.assertEqual(len(result), 22)
        self.assertEqual(len({x['pattern'] for x in result}), 21)
        self.assertTrue(all(x['pattern'] and x['match_count'] is None for x in result))
        symbols = {x['symbol'] for x in result if x['symbol']}
        self.assertTrue(all(s.startswith('synth_') for s in symbols))
