import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from ct_analyzer.core import analyze, markdown, MAX_BYTES

ROOT = Path(__file__).resolve().parents[2]


def table(script):
    return ('<CheatTable><CheatEntries><CheatEntry><AssemblerScript><![CDATA[' + script +
            ']]></AssemblerScript></CheatEntry></CheatEntries></CheatTable>').encode()


class AnalyzerTests(unittest.TestCase):
    def test_fixture_inventory(self):
        r = analyze((ROOT / 'fixtures/synthetic.CT').read_bytes())
        self.assertEqual(len(r['records']), 2)
        self.assertEqual(r['records'][1]['parent_key'], 'record-1')
        self.assertEqual(r['records'][0]['children'], ['record-2'])
        self.assertEqual([s['language'] for s in r['scripts']], ['AA', 'Lua', 'Lua'])
        self.assertEqual(r['aobs'][0]['arguments'][1], '"synthetic,module.exe"')
        self.assertEqual(r['aobs'][0]['uniqueness'], 'unverified')
        self.assertEqual(r['allocations'][0]['arguments'][1], '1000')
        self.assertTrue(any(d['consumer'] == 'record-2' for d in r['dependencies']))

    def test_scopes_comments_sections_and_cleanup(self):
        r = analyze(table('[ENABLE]\n// alloc(fake,20)\n{dealloc(*)}\naobscan(a,AA ??)\naobscanregion(b,start,stop,BB *)\n[DISABLE]\ndealloc(*)\nunregistersymbol(*)'))
        self.assertEqual([a['scope'] for a in r['aobs']], ['process', 'region'])
        self.assertEqual(len(r['allocations']), 1)
        self.assertEqual(r['allocations'][0]['section'], 'disable')
        self.assertEqual(sum(w['rule'] == 'RESOURCE-OWNERSHIP' for w in r['warnings']), 2)

    def test_empty_disable_is_advisory(self):
        r = analyze(table('[ENABLE]\n[DISABLE]\n// persistent library'))
        self.assertEqual(r['warnings'][0]['rule'], 'EMPTY-DISABLE')
        self.assertEqual(r['warnings'][0]['severity'], 'review')

    def test_embedded_lua_not_parsed_as_aa(self):
        r = analyze(table('{$lua}\nalloc(fake,10)\n{$asm}\nalloc(real,20)'))
        self.assertEqual([a['arguments'][0] for a in r['allocations']], ['real'])

    def test_lua_disable_is_not_empty(self):
        r = analyze(table('[ENABLE]\n[DISABLE]\n{$lua}\ncleanup()'))
        self.assertNotIn('EMPTY-DISABLE', [w['rule'] for w in r['warnings']])

    def test_duplicate_ids_do_not_break_tree(self):
        r = analyze(b'<CheatTable><CheatEntries><CheatEntry><ID>1</ID></CheatEntry><CheatEntry><ID>1</ID></CheatEntry></CheatEntries></CheatTable>')
        self.assertEqual([x['key'] for x in r['records']], ['record-1', 'record-2'])

    def test_reject_entities_even_utf16(self):
        for encoding in ('utf-8', 'utf-16', 'utf-32'):
            with self.assertRaises(ValueError):
                analyze('<!DOCTYPE CheatTable [<!ENTITY x "abc">]><CheatTable/>'.encode(encoding))

    def test_invalid_and_oversize(self):
        for data in (b'<Other/>', b'x' * (MAX_BYTES + 1)):
            with self.assertRaises(ValueError):
                analyze(data)

    def test_markdown_fence_cannot_be_closed_by_script(self):
        r = analyze(table('```\n<script>unsafe</script>'))
        self.assertIn('````json', markdown(r))

    def test_deterministic_and_no_execution(self):
        data = b'<CheatTable><LuaScript>error("never execute")</LuaScript></CheatTable>'
        self.assertEqual(analyze(data), analyze(data))

    def test_cli_outputs_and_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            good = subprocess.run([sys.executable, '-m', 'ct_analyzer', str(ROOT / 'fixtures/synthetic.CT'), '--output', temp], capture_output=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            report = json.loads((output / 'report.json').read_text(encoding='utf-8'))
            self.assertEqual(report['schema_version'], '0.1')
            self.assertIn('MemoryRecord', (output / 'report.md').read_text(encoding='utf-8'))
            bad = output / 'bad.CT'
            bad.write_text('<CheatTable>', encoding='utf-8')
            failure = subprocess.run([sys.executable, '-m', 'ct_analyzer', str(bad)], capture_output=True)
            self.assertEqual(failure.returncode, 2)
            self.assertNotIn(b'Traceback', failure.stderr)


if __name__ == '__main__':
    unittest.main()
