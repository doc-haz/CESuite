"""Run synthetic Lua tests with a Lua 5.3 shared library, without launching CE.

Example: python tools/run_lua_tests.py --library 'C:/Program Files/Cheat Engine/lua53-64.dll'
On Linux: --library /usr/lib/x86_64-linux-gnu/liblua5.3.so.0
The library architecture must match Python. No CE APIs or target access are used.
"""
import argparse
import ctypes
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(library):
    lib = ctypes.CDLL(str(library))
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_close.argtypes = [ctypes.c_void_p]
    state = lib.luaL_newstate()
    if not state:
        raise RuntimeError('Cannot create Lua state')
    previous = Path.cwd()
    try:
        os.chdir(ROOT)
        lib.luaL_openlibs(state)
        status = lib.luaL_loadfilex(state, b'ce/tests/runtime_spec.lua', None)
        if not status:
            status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise RuntimeError(lib.lua_tolstring(state, -1, None).decode('utf-8', errors='replace'))
    finally:
        lib.lua_close(state)
        os.chdir(previous)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    run(parser.parse_args().library)
