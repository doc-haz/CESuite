"""Validate the v0.2.1 assessment contract against the real Lua serializer.

The extensive report is produced by the shipped bundle with synthetic CE mocks;
the JSON is then validated with the runtime schema. No target or CE is touched.
"""
import copy
import ctypes
import ctypes.util
import json
import os
import re
from pathlib import Path
import tempfile
import unittest

from jsonschema import Draft202012Validator, ValidationError

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / 'schemas/runtime-report.schema.json'

HARNESS = r'''
local realDate=os.date
os.date=function(f,...)
  if f=='!%Y-%m-%dT%H:%M:%SZ' then return '2026-10-24T00:00:00Z' end
  return realDate(f,...)
end
package.path='ce/modules/?.lua;'..package.path
getMainForm=function() return {Menu={Items={Count=0,add=function() end}}} end
createMenuItem=function()
  return {add=function() end,destroy=function() end,children={}}
end
local foundCalls=0
local api={
  soExactValue=0,vtByteArray=8,rtRounded=0,fsmNotAligned=0,
  getOpenedProcessID=function() return 7 end,
  getCEVersion=function() return 7.72 end,
  targetIs64Bit=function() return true end,
  process='game.exe',
  enumModules=function()
    return {{Name='game.exe',Address=0x1000,PathToFile='C:/g/game.exe',Is64Bit=true}}
  end,
  getModuleSize=function() return 0x1000 end,
  vtAutoAssembler=11,
  getAddressList=function()
    return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
      return {ID=1,Description='Health',Type=11,OffsetCount=0,Active=false,
        Script='[ENABLE]\naobscanmodule(health,game.exe,48 8B ??)\naobscan(second,90 90)\nregistersymbol(health)\n{$lua}\nlocal p="AA BB"\naobScan(p)\n{$asm}\n[DISABLE]\ndealloc(health)'}
    end}
  end,
  createMemScan=function()
    return {ErrorString='',firstScan=function() end,waitTillDone=function() end,destroy=function() end}
  end,
  createFoundList=function()
    foundCalls=foundCalls+1
    if foundCalls==1 then
      return {Count=0,Address={},initialize=function() end,destroy=function() end}
    end
    return {Count=1,Address={[0]='1000'},initialize=function() end,destroy=function() end}
  end
}
for k,v in pairs(api) do _G[k]=v end
local Core=assert(loadfile('releases/CESuite_Core.lua','t',setmetatable({api=api,require=require},{__index=_G})))()
local one=Core.exportReports('__BASE_ONE__',{confirmOverwrite=function() return true end})
foundCalls=0
local two=Core.exportReports('__BASE_TWO__',{confirmOverwrite=function() return true end})
assert(one.status=='complete','first export failed: '..tostring(one.error))
assert(two.status=='complete','second export failed: '..tostring(two.error))
assert(Core.state.busy==false,'busy guard not cleared')
local marker=assert(io.open('__MARKER__','w'))
marker:write('ok')
marker:close()
'''


class AssessmentContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema = json.loads(SCHEMA.read_text(encoding='utf-8'))
        Draft202012Validator.check_schema(schema)
        cls.schema = schema
        cls.validator = Draft202012Validator(schema)
        cls.directory = tempfile.TemporaryDirectory(prefix='CESuite assessment ')
        cls.tmp = Path(cls.directory.name)
        library = os.environ.get('CESUITE_LUA_LIBRARY') or ctypes.util.find_library('lua5.3')
        library = library or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        lib = ctypes.CDLL(str(library))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
        state = lib.luaL_newstate()
        cls.assertIsNotNone(cls, state)
        base_one = str(cls.tmp / 'one').replace('\\', '/')
        base_two = str(cls.tmp / 'two').replace('\\', '/')
        marker = str(cls.tmp / 'done').replace('\\', '/')
        script = (HARNESS.replace('__BASE_ONE__', base_one)
                          .replace('__BASE_TWO__', base_two)
                          .replace('__MARKER__', marker))
        try:
            lib.luaL_openlibs(state)
            status = lib.luaL_loadstring(state, script.encode('utf-8'))
            if not status:
                status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
            if status:
                err = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
                cls.fail(cls, f'harness failed: {err}')
        finally:
            lib.lua_close(state)
        if not Path(marker).exists():
            raise AssertionError('harness did not complete')
        cls.extensive_one = json.loads((cls.tmp / 'one_Extensive.json').read_text(encoding='utf-8'))
        cls.extensive_two = json.loads((cls.tmp / 'two_Extensive.json').read_text(encoding='utf-8'))
        cls.simple_one = (cls.tmp / 'one_Simple.md').read_text(encoding='utf-8')
        cls.simple_two = (cls.tmp / 'two_Simple.md').read_text(encoding='utf-8')

    def test_extensive_report_conforms_to_runtime_schema(self):
        self.validator.validate(self.extensive_one)
        self.validator.validate(self.extensive_two)

    def test_assessment_counts_and_repair_path_are_internally_consistent(self):
        a = self.extensive_one['assessment']
        self.assertEqual(a['counts']['total'], len(a['diagnostics']))
        problems = sum(1 for d in a['diagnostics'] if d['outcome'] == 'problem')
        healthy = sum(1 for d in a['diagnostics'] if d['outcome'] == 'healthy')
        advisory = sum(1 for d in a['diagnostics'] if d['outcome'] == 'advisory')
        not_assessed = sum(1 for d in a['diagnostics'] if d['outcome'] == 'not_assessed')
        self.assertEqual([a['counts']['problems'], a['counts']['healthy'],
                          a['counts']['advisory'], a['counts']['not_assessed']],
                         [problems, healthy, advisory, not_assessed])
        by_id = {d['id']: d for d in a['diagnostics']}
        self.assertEqual(len(by_id), len(a['diagnostics']), 'diagnostic ids must be unique')
        self.assertEqual([s['order'] for s in a['repair_path']],
                         list(range(1, len(a['repair_path']) + 1)))
        for step in a['repair_path']:
            self.assertIn(step['diagnostic_id'], by_id)
            self.assertIn(by_id[step['diagnostic_id']]['outcome'], ('problem', 'advisory'))

    def test_runtime_and_static_evidence_keep_their_status(self):
        a = self.extensive_one['assessment']
        for d in a['diagnostics']:
            if d['outcome'] == 'healthy':
                self.assertEqual(d['status'], 'observed')
                self.assertEqual(d['source'], 'runtime')
            if d['source'] in ('lexical', 'static'):
                self.assertIn(d['status'], ('candidate', 'unknown', 'unsupported'))
            if d['status'] == 'observed':
                self.assertEqual(d['source'], 'runtime')
        rules = {d['rule'] for d in a['diagnostics']}
        self.assertIn('AOB-NO-MATCH', rules)
        self.assertIn('STATIC-CANDIDATE-ONLY', rules)
        static = next(d for d in a['diagnostics'] if d['rule'] == 'STATIC-CANDIDATE-ONLY')
        self.assertEqual(static['confidence'], 'low')
        self.assertIn('source only', static['summary'].lower())
        self.assertTrue(static['do_not_assume'])

    def test_schema_rejects_promoted_or_malformed_assessment(self):
        base = self.extensive_one
        corruptions = []
        promoted = copy.deepcopy(base)
        for d in promoted['assessment']['diagnostics']:
            if d['source'] == 'static':
                d['status'] = 'observed'
        corruptions.append(('static promoted to observed', promoted))

        healthy_candidate = copy.deepcopy(base)
        for d in healthy_candidate['assessment']['diagnostics']:
            if d['outcome'] == 'healthy':
                d['status'] = 'candidate'
        corruptions.append(('healthy check demoted to candidate', healthy_candidate))

        lexical_observed = copy.deepcopy(base)
        for d in lexical_observed['assessment']['diagnostics']:
            if d['source'] == 'lexical':
                d['status'] = 'observed'
        corruptions.append(('lexical promoted to observed', lexical_observed))

        bad_confidence = copy.deepcopy(base)
        bad_confidence['assessment']['diagnostics'][0]['confidence'] = 'runtime'
        corruptions.append(('invalid confidence level', bad_confidence))

        unknown_field = copy.deepcopy(base)
        unknown_field['assessment']['diagnostics'][0]['verified'] = True
        corruptions.append(('unknown diagnostic field', unknown_field))

        missing = copy.deepcopy(base)
        missing['assessment']['diagnostics'][0].pop('do_not_assume')
        corruptions.append(('missing required diagnostic field', missing))

        bad_order = copy.deepcopy(base)
        if bad_order['assessment']['repair_path']:
            bad_order['assessment']['repair_path'][0]['order'] = 0
            corruptions.append(('repair order below 1', bad_order))

        for label, doc in corruptions:
            with self.subTest(case=label):
                with self.assertRaises(ValidationError):
                    self.validator.validate(doc)

    def test_simple_report_is_a_view_of_the_same_assessment(self):
        a = self.extensive_one['assessment']
        text = self.simple_one
        self.assertTrue(text.startswith('# CESuite Simple Report'))
        self.assertIn('## Suggested Repair Path', text)
        for step in a['repair_path']:
            self.assertIn(step['action'], text)
        for d in a['diagnostics']:
            if d['outcome'] == 'problem':
                self.assertIn(d['summary'], text)

    def test_reports_are_deterministic_and_keep_core_version(self):
        self.assertEqual(self.simple_one, self.simple_two)
        self.assertEqual(self.extensive_one['assessment'], self.extensive_two['assessment'])
        self.assertEqual(self.extensive_one['core_version'], '0.1.9')
        self.assertEqual(self.extensive_one['static_lua_analysis']['suite_version'], '0.2.3')
        self.assertEqual(self.extensive_one['schema_version'], '0.1')
        operation = self.extensive_one['operation']
        self.assertEqual(operation['status'], 'complete')
        self.assertFalse(operation['cancelled'])
        self.assertIsInstance(operation['metrics']['duration_ms'], (int, float))
        self.assertGreaterEqual(operation['metrics']['duration_ms'], 0)

    def test_legacy_reports_still_validate(self):
        legacy = json.loads((ROOT / 'fixtures/runtime-v0.1.4.json').read_text(encoding='utf-8'))
        self.validator.validate(legacy)
        plain = copy.deepcopy(self.extensive_one)
        del plain['assessment']
        self.validator.validate(plain)
        enriched = copy.deepcopy(plain)
        self.validator.validate(enriched)


if __name__ == '__main__':
    unittest.main()
