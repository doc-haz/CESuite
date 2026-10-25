"""Run synthetic Lua tests with a Lua 5.3 shared library, without launching CE.

Example: python tools/run_lua_tests.py --library 'C:/Program Files/Cheat Engine/lua53-64.dll'
On Linux: --library /usr/lib/x86_64-linux-gnu/liblua5.3.so.0
The library architecture must match Python. No CE APIs or target access are used.
"""
import argparse
import ctypes
import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path
from build_ce import build, version

ROOT = Path(__file__).resolve().parents[1]


def run(library, script='ce/tests/runtime_spec.lua', package_path=None, output_path=None):
    lib = ctypes.CDLL(str(library))
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_close.argtypes = [ctypes.c_void_p]
    lib.lua_pushstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.lua_setglobal.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    state = lib.luaL_newstate()
    if not state:
        raise RuntimeError('Cannot create Lua state')
    previous = Path.cwd()
    try:
        os.chdir(ROOT)
        lib.luaL_openlibs(state)
        if package_path is not None:
            lib.lua_pushstring(state, str(package_path).encode('utf-8'))
            lib.lua_setglobal(state, b'CESUITE_TEST_PACKAGE')
        if output_path is not None:
            lib.lua_pushstring(state, str(output_path).encode('utf-8'))
            lib.lua_setglobal(state, b'CESUITE_TEST_OUTPUT')
        status = lib.luaL_loadfilex(state, script.encode('utf-8'), None)
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
    library = parser.parse_args().library.resolve()
    run(library)
    run(library, 'ce/tests/module_dump_spec.lua')
    run(library, 'ce/tests/luastatic_spec.lua')
    run(library, 'ce/tests/operations_spec.lua')
    run(library, 'ce/tests/diagnose_spec.lua')
    run(library, 'ce/tests/address_spec.lua')
    with tempfile.TemporaryDirectory(prefix='CESuite test ') as directory:
        output = Path(directory)
        build(output)
        with zipfile.ZipFile(output / f'CESuite_Autorun_v{version()}.zip') as archive:
            archive.extractall(output / 'autorun')
        (output / 'portable.lua').write_text(ET.parse(output / f'CESuite_Core_v{version()}.CT').getroot().findtext('LuaScript'), encoding='utf-8')
        run(library, 'ce/tests/distribution_spec.lua', output)
        # Regression for replay-harness quoting: source and IDs are inert data,
        # including strings that would close long-bracket Lua literals.
        from replay_dependencies import replay
        source = output / 'cached-input.json'
        script_id = 'quoted-"-\\-]===]-\u00e9'
        script_text = '''{$lua}
error('INSPECTED SOURCE MUST NOT EXECUTE')
local text="]===] \\" \\n"
TEST_GLOBAL=TEST_GLOBAL or {}
{$asm}'''
        source.write_text(json.dumps({'scripts': [
            {'id': script_id, 'language': 'AA', 'text': script_text}
        ]}), encoding='utf-8')
        result = replay(source, output / 'replay.json', library)
        assert [(d['name'], d['relation'], d['script_id']) for d in result['dependencies']] == [
            ('TEST_GLOBAL', 'provides', script_id), ('TEST_GLOBAL', 'requires', script_id)]
        assert len(result['dependency_summary']) == 2
        print('1 replay harness test passed (escaped input stays inert; no source execution)')
