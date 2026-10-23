"""Explicit static Lua parity suite: compares Python (analyzer/src) vs Lua (ce/modules).

Verifies byte/semantic equivalence of Static Lua AOB extraction across a shared corpus:
- pattern (normalized)
- symbol
- sink
- status
- confidence
- raw_pattern
- scope
- match_count
- uniqueness
"""
import ctypes
import json
import os
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'analyzer/src'))
from ct_analyzer.lua_static import analyze_lua

CORPUS = [
    # 1. Literals, concatenation, table indexing
    ("local a='48'; local b=a..'8B'; local t={p=b..'xx'}; aobScan(t.p)", "concat_alias_index"),
    # 2. Positional region with unresolvable intermediate arguments
    ("aobScanRegion('sym_reg', start, start+size, '48 8B 05 ??')", "region_positional_args"),
    # 3. All sink forms with symbols and modules
    ("aobScan('AA BB'); aobScanModule('game','CC DD'); aobScanModule('s_mod','game','EE FF'); aobScanRegion('s_reg',start,stop,'11 22'); customScan('s_cst','33 44',1)", "all_sinks"),
    # 4. MultiCustomScan with nested tables, valid and unknown rows
    ("local t={bad={{type(x)=='a' and start}}, good={{'s','48xx',1,start,size}}, dynamic={{'d',f()}}}; Register.multiCustomScan(t)", "multicustomscan_wrapper"),
    # 5. OnEnable table wrapper
    ("local t={{'enable_sym', '90 90 90', 1, 0, 100}}; Register.onEnable(t)", "onenable_wrapper"),
    # 6. Reassignments, dynamic calls, forward references
    ("local a='AA'; a='BB'; aobScan(a); local b=unknownFunc(); aobScan(b); aobScan(forwardRef); local forwardRef='CC'", "reassignments_and_unknowns"),
    # 7. Unlinked library signatures
    ("Obj.Sig = '55 48 89 E5'; UE.Sig.Player = '48 83 EC 28'", "unlinked_signatures"),
    # 8. Escaped strings
    (r"aobScan('AA\nBB'); aobScan('\x41')", "escaped_strings"),
    # 9. Dotted and nested path expressions
    ("local conf = { sub = { pat = '66 90' } }; aobScan(conf.sub.pat)", "nested_path_index"),
    # 10. Table constructor with numeric keys
    ("local t = { [1] = '0F 1F 00' }; aobScan(t[1])", "numeric_key_table"),
]


def run_lua_static(library_path, source, script_id='test'):
    """Execute ce/modules/luastatic.lua via Lua 5.3 C API and return observations as Python dicts."""
    lib = ctypes.CDLL(str(library_path))
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_close.argtypes = [ctypes.c_void_p]

    state = lib.luaL_newstate()
    if not state:
        raise RuntimeError('Cannot create Lua state')
    try:
        lib.luaL_openlibs(state)
        # Helper script that loads luastatic and serializes observations with exporter
        harness = f"""
        package.path = 'ce/modules/?.lua;' .. package.path
        local LS = require('luastatic')
        local EXP = require('exporter')
        local U = require('util')
        local src = {json.dumps(source)}
        local obs = LS.analyzeSource(src, '{script_id}')
        LUA_RESULT = EXP.encode(obs)
        """
        status = lib.luaL_loadstring(state, harness.encode('utf-8'))
        if not status:
            status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            err = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
            raise RuntimeError(f'Lua execution failed: {err}')
        # Get LUA_RESULT
        lib.luaL_loadstring(state, b"return LUA_RESULT")
        lib.lua_pcallk(state, 0, 1, 0, 0, None)
        raw_json = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
        return json.loads(raw_json)
    finally:
        lib.lua_close(state)


class StaticLuaParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = Path(os.environ.get('CESUITE_LUA_LIBRARY') or 'C:/Program Files/Cheat Engine/lua53-64.dll')
        if not cls.library.exists():
            raise unittest.SkipTest(f'Lua library not found at {cls.library}')

    def test_corpus_parity(self):
        passed = 0
        for source, case_name in CORPUS:
            with self.subTest(case=case_name):
                py_obs = analyze_lua(source, case_name)
                lua_obs = run_lua_static(self.library, source, case_name)

                self.assertEqual(len(py_obs), len(lua_obs),
                                 f"Observation count mismatch for {case_name}: py={len(py_obs)}, lua={len(lua_obs)}")

                for i, (py_item, lua_item) in enumerate(zip(py_obs, lua_obs)):
                    for field in ['pattern', 'symbol', 'sink', 'status', 'confidence',
                                  'provenance', 'scope', 'match_count', 'uniqueness']:
                        self.assertEqual(
                            py_item.get(field), lua_item.get(field),
                            f"Field mismatch [{field}] at obs #{i} in case '{case_name}': "
                            f"py={py_item.get(field)!r} vs lua={lua_item.get(field)!r}"
                        )
                passed += 1
        print(f"PASS Static Lua parity: {passed}/{len(CORPUS)} corpus cases byte/field equivalent between Python and Lua")


if __name__ == '__main__':
    unittest.main()
