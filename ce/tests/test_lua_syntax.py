"""Compile every shipped Lua source before packaging/regression (031C)."""
import ctypes
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = Path('C:/Program Files/Cheat Engine/lua53-64.dll')
FILES = [ROOT / 'ce/CESuite_Core.lua', ROOT / 'ce/bootstrap.lua',
         ROOT / 'ce/CESuite_Autorun.lua'] + sorted((ROOT / 'ce/modules').glob('*.lua'))


class LuaSyntaxTests(unittest.TestCase):
    def test_all_lua_sources_compile(self):
        lib = ctypes.CDLL(str(LIBRARY))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
        for path in FILES:
            with self.subTest(path=path.name):
                state = lib.luaL_newstate()
                lib.luaL_openlibs(state)
                status = lib.luaL_loadfilex(state, str(path).encode('utf-8'), None)
                if status:
                    message = lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace')
                    lib.lua_close(state)
                    self.fail(f'{path}: {message}')
                lib.lua_close(state)


if __name__ == '__main__':
    unittest.main()
