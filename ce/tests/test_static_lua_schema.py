import copy
import ctypes
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from jsonschema import Draft202012Validator, FormatChecker, ValidationError

ROOT = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(ROOT / 'tools'))
from build_ce import version as get_suite_version


class StaticLuaReportSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema_path = ROOT / 'schemas/static-lua-report.schema.json'
        cls.schema = json.loads(schema_path.read_text(encoding='utf-8'))
        Draft202012Validator.check_schema(cls.schema)
        cls.format_checker = FormatChecker()
        @cls.format_checker.checks('date-time')
        def _check_datetime(val):
            if not isinstance(val, str):
                return True
            return bool(re.match(r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})$', val))
        cls.validator = Draft202012Validator(cls.schema, format_checker=cls.format_checker)

    def _generate_real_static_report(self, attached=False):
        library = os.environ.get('CESUITE_LUA_LIBRARY') or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        lib = ctypes.CDLL(str(library))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]

        state = lib.luaL_newstate()
        self.assertIsNotNone(state)
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
            output_file = tf.name.replace('\\', '/')

        pid = 1234 if attached else 0
        pname = "'test_game.exe'" if attached else 'nil'

        try:
            lib.luaL_openlibs(state)
            lua_script = f'''
            getMainForm = function() return {{ Menu = {{ Items = {{ Count = 0, add = function() end }} }} }} end
            createMenuItem = function() return {{ add = function() end, destroy = function() end, children = {{}} }} end
            getOpenedProcessID = function() return {pid} end
            getCEVersion = function() return 7.5 end
            targetIs64Bit = function() return true end
            enumModules = function() return {{}} end
            vtAutoAssembler = 11
            process = {pname}
            getAddressList = function()
              local memRec = {{
                ID = 1,
                Description = "Test Script",
                Type = 11,
                Script = "[ENABLE]\\n{{$lua}}\\nlocal sig = '48 8B 05 ?? ?? ?? ??'\\naobScan(sig)\\n{{$asm}}\\n[DISABLE]"
              }}
              return {{
                Count = 1,
                LoadedTableVersion = 45,
                getMemoryRecord = function(idx) return memRec end
              }}
            end
            local bundle_fn = assert(loadfile('releases/CESuite_Core.lua'))
            local Core = bundle_fn()
            Core.install()
            local rep = Core.analyzeStaticLua()
            local Export
            for i = 1, 20 do
              local name, val = debug.getupvalue(Core.export, i)
              if name == 'Export' then Export = val; break end
            end
            assert(Export, 'Export module must be present in Core.export upvalues')
            Export.write(rep, '{output_file}')
            '''
            status = lib.luaL_loadstring(state, lua_script.encode('utf-8'))
            if not status:
                status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
            if status:
                err = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
                self.fail(f"Harness failed: {err}")
            data = json.loads(Path(output_file).read_text(encoding='utf-8'))
            return data
        finally:
            lib.lua_close(state)
            Path(output_file).unlink(missing_ok=True)

    def test_real_static_report_detached_conforms_to_schema(self):
        rep = self._generate_real_static_report(attached=False)
        self.validator.validate(rep)
        self.assertEqual(rep['core_version'], '0.1.9')
        self.assertEqual(rep['suite_version'], get_suite_version())
        self.assertEqual(rep['observation_only'], True)
        self.assertEqual(rep['target']['attached'], False)

    def test_real_static_report_attached_conforms_to_schema(self):
        rep = self._generate_real_static_report(attached=True)
        self.validator.validate(rep)
        self.assertEqual(rep['core_version'], '0.1.9')
        self.assertEqual(rep['suite_version'], get_suite_version())
        self.assertEqual(rep['target']['attached'], True)
        self.assertEqual(rep['target']['pid'], 1234)

    def test_schema_rejects_missing_required_fields(self):
        rep = self._generate_real_static_report(attached=False)
        required_fields = [
            "title", "core_version", "suite_version", "ce_version",
            "generated_at", "completed_at", "observation_only", "target",
            "candidate_count", "unique_pattern_count", "observations",
            "diagnostics", "limitations"
        ]
        for field in required_fields:
            with self.subTest(missing_field=field):
                corrupt = copy.deepcopy(rep)
                del corrupt[field]
                with self.assertRaises(ValidationError):
                    self.validator.validate(corrupt)

    def test_schema_rejects_additional_properties_at_root(self):
        rep = self._generate_real_static_report(attached=False)
        corrupt = copy.deepcopy(rep)
        corrupt['extra_property'] = 'unexpected'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt)

    def test_schema_rejects_invalid_types_and_versions(self):
        rep = self._generate_real_static_report(attached=False)
        bad_types = [
            ('candidate_count', 'not-a-number'),
            ('unique_pattern_count', -1),
            ('core_version', '0.2.0'),  # core_version must be 0.1.9
            ('observation_only', False),  # must be true
            ('title', 'Wrong Title'),
            ('suite_version', 12345),  # must be string
        ]
        for key, val in bad_types:
            with self.subTest(key=key, bad_value=val):
                corrupt = copy.deepcopy(rep)
                corrupt[key] = val
                with self.assertRaises(ValidationError):
                    self.validator.validate(corrupt)

    def test_schema_rejects_promoted_or_verified_aobs(self):
        rep = self._generate_real_static_report(attached=False)
        self.assertTrue(len(rep['observations']) > 0)

        # 1. status cannot be 'verified' or 'observed' (only 'source-candidate' or 'unknown')
        corrupt1 = copy.deepcopy(rep)
        corrupt1['observations'][0]['status'] = 'observed'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt1)

        # 2. confidence must be lexical
        corrupt2 = copy.deepcopy(rep)
        corrupt2['observations'][0]['confidence'] = 'runtime'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt2)

        # 3. provenance must be static-lua
        corrupt3 = copy.deepcopy(rep)
        corrupt3['observations'][0]['provenance'] = 'runtime-scan'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt3)

        # 4. match_count must be null
        corrupt4 = copy.deepcopy(rep)
        corrupt4['observations'][0]['match_count'] = 1
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt4)

        # 5. uniqueness must be unverified
        corrupt5 = copy.deepcopy(rep)
        corrupt5['observations'][0]['uniqueness'] = 'unique'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt5)

        # 6. extra properties in observation rejected
        corrupt6 = copy.deepcopy(rep)
        corrupt6['observations'][0]['bogus_field'] = 'injection'
        with self.assertRaises(ValidationError):
            self.validator.validate(corrupt6)

    def test_schema_rejects_invalid_date_time_formats(self):
        rep = self._generate_real_static_report(attached=False)
        invalid_dates = [
            'yesterday',
            '2026/10/24 12:00:00',
            'invalid-date',
            '2026-10-24',
            'not-a-timestamp',
        ]
        for field in ['generated_at', 'completed_at']:
            for bad_val in invalid_dates:
                with self.subTest(field=field, bad_val=bad_val):
                    corrupt = copy.deepcopy(rep)
                    corrupt[field] = bad_val
                    with self.assertRaises(ValidationError):
                        self.validator.validate(corrupt)

    def test_enrich_report_requires_suite_version(self):
        library = os.environ.get('CESUITE_LUA_LIBRARY') or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        lib = ctypes.CDLL(str(library))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]

        state = lib.luaL_newstate()
        self.assertIsNotNone(state)
        try:
            lib.luaL_openlibs(state)
            lua_code = '''
            package.path = 'ce/modules/?.lua;' .. package.path
            local LuaStatic = require('luastatic')
            local ok, err = pcall(function()
                LuaStatic.enrichReport({}, nil, nil)
            end)
            assert(not ok, 'enrichReport should fail when suiteVersion is missing')
            assert(err:find('suite version required'), 'error message should match')
            '''
            status = lib.luaL_loadstring(state, lua_code.encode('utf-8'))
            if not status:
                status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
            if status:
                err = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
                self.fail(f"Harness failed: {err}")
        finally:
            lib.lua_close(state)


if __name__ == '__main__':
    unittest.main()
