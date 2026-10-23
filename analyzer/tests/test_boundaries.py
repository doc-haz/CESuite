import unittest
from ct_analyzer.core import analyze
from test_analyzer import table

class BoundaryTests(unittest.TestCase):
    def test_luacode_long_comments_and_incomplete(self):
        for ending in ('', '\n{$asm}\nalloc(real,16)'):
            r=analyze(table('{$luacode x}\nalloc(fake,16)\naobscanmodule(fake,x,90)\nregistersymbol(fake)\n--[=[\n{$asm}\nalloc(commentFake,16)\n]=]'+ending))
            self.assertEqual(len(r['aobs']),0)
            self.assertEqual(len(r['allocations']),bool(ending))
            self.assertEqual(len(r['scripts']),1)
        r=analyze(table('{$luacode}\n--[[\n{$asm}\nalloc(fake,16)'))
        self.assertEqual(r['allocations'],[])
        self.assertIn('OPAQUE-INCOMPLETE',[w['rule'] for w in r['warnings']])

    def test_conditionals_nested_unmatched_and_incomplete(self):
        r=analyze(table('{$ifdef X}\nalloc(fake,16)\n{$ifndef Y}\naobscan(fake,90)\n{$endif}\n{$endif}\n{$endif}\nalloc(real,16)'))
        self.assertEqual([x['arguments'][0] for x in r['allocations']],['real'])
        self.assertEqual(r['aobs'],[])
        self.assertIn('CONDITIONAL-UNMATCHED',[w['rule'] for w in r['warnings']])
        r=analyze(table('{$ifdef X}\nalloc(fake,16)'))
        self.assertEqual(r['allocations'],[])
        self.assertIn('OPAQUE-INCOMPLETE',[w['rule'] for w in r['warnings']])

    def test_post_source_commands_complex_arguments(self):
        for cmd in ('HOOK','UNHOOK','HOOK5','aobscanfunction','aobscanregion'):
            r=analyze(table(cmd+'(symbol,fn("a,b",nested(1,2)),90)\nalloc(real,16)'))
            self.assertEqual(r['aobs'],[])
            self.assertEqual(r['symbols'],[])
            self.assertEqual(len(r['allocations']),1)
            self.assertIn('OPAQUE-COMMAND',[w['rule'] for w in r['warnings']])

    def test_comments_and_fake_embedded_lua_cannot_leak(self):
        for text in ('/*\n{$lua}\nalloc(fake,16)\n*/', '{\nalloc(fake,16)\n}'):
            r=analyze(table(text+'\nalloc(real,16)'))
            self.assertEqual(len(r['scripts']),1)
            self.assertEqual([x['arguments'][0] for x in r['allocations']],['real'])
        r=analyze(table('{$luacode}\n{$lua}\ncreateTimer()\n{$asm}'))
        self.assertEqual(len(r['scripts']),1)

    def test_opaque_text_does_not_create_cross_script_dependencies(self):
        xml=b'<CheatTable><CheatEntries><CheatEntry><AssemblerScript>alloc(shared,16)</AssemblerScript></CheatEntry><CheatEntry><AssemblerScript>{$luacode}\nshared=1\n{$asm}</AssemblerScript></CheatEntry></CheatEntries></CheatTable>'
        self.assertEqual(analyze(xml)['dependencies'],[])


    def test_f01_incomplete_luacode(self):
        r=analyze(table('{$luacode\nalloc(fake,16)\naobscan(fake,90)\nlabel(fake)\ndefine(fake,real)\nfake:'))
        self.assertEqual(r['aobs']+r['symbols']+r['allocations']+r['dependencies'],[])
        self.assertIn('OPAQUE-INCOMPLETE',[w['rule'] for w in r['warnings']])

    def test_f02_embedded_luacode(self):
        r=analyze(table('alloc(prefix,16) {$luacode}\nalloc(fake,16)\n{$asm}\nalloc(real,16)'))
        self.assertEqual([x['arguments'][0] for x in r['allocations']],['real'])

    def test_f03_same_line_conditionals(self):
        for prefix in ('{$ifdef X}{$endif}','{$ifndef X}{$endif}',
                       '{$ifdef X}{$ifndef Y}{$endif}{$endif}', '{$ifdef X}{$endif}{$endif}'):
            with self.subTest(prefix=prefix):
                r=analyze(table(prefix+'\nalloc(real,16)'))
                self.assertEqual([x['arguments'][0] for x in r['allocations']],['real'])
                self.assertNotIn('OPAQUE-INCOMPLETE',[w['rule'] for w in r['warnings']])

    def test_f04_conditional_section(self):
        for header in ('[ENABLE]','[DISABLE]'):
            r=analyze(table('[ENABLE]\n{$ifdef X}\n'+header+'\n{$endif}\nalloc(real,16)\naobscan(anchor,90)\n[DISABLE]\ndealloc(real)'))
            self.assertEqual(r['allocations'][0]['section'],'unknown')
            self.assertEqual(r['aobs'][0]['section'],'unknown')
            self.assertEqual(r['allocations'][1]['section'],'disable')

    def test_magna_aob_prefix_cannot_reach_lookup(self):
        # COMMAND is an explicit allowlist; region is opaque before COMMAND.match.
        for command in ('aobscanex','aobscanbogus','aobscanfunction','aobscanregion'):
            r=analyze(table(command+'(x,game.exe,90)'))
            self.assertEqual(r['aobs'],[])
