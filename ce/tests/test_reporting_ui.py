"""Reporting and UI integration tests (030E).

Validates that Simple and Extensive reports present dynamic analysis,
provenance, coverage, and limitations without confusing discovered with validated.
"""
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import tempfile
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_SCHEMA = ROOT / 'schemas/runtime-report.schema.json'
STATIC_SCHEMA = ROOT / 'schemas/static-lua-report.schema.json'

SCRIPT95_PATH = (ROOT / 'ce/tests/fixtures/dynamic/script95.lua').resolve()
UE_PATH = (ROOT / 'ce/tests/fixtures/dynamic/ue.lua').resolve()
LOADER_PATH = (ROOT / 'ce/tests/fixtures/dynamic/loader.lua').resolve()

HARNESS = r'''
local realDate=os.date
os.date=function(f,...)
  if f=='!%Y-%m-%dT%H:%M:%SZ' then return '2026-10-25T12:00:00Z' end
  return realDate(f,...)
end
package.path='ce/modules/?.lua;'..package.path
getMainForm=function() return {Menu={Items={Count=0,add=function() end}}} end
createMenuItem=function()
  return {add=function() end,destroy=function() end,children={}}
end

local function read(p)
  local f=assert(io.open(p,'rb'))
  local t=f:read('*a')
  f:close()
  return t
end

local s95=read('__SCRIPT95__')
local ue=read('__UE__')
local loader=read('__LOADER__')

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
      return {ID=95,Description='FFRS Script 95',Type=11,OffsetCount=0,Active=false,
        Script='{$lua}\n'..s95..'\n{$asm}'}
    end}
  end,
  createMemScan=function()
    return {ErrorString='',firstScan=function() end,waitTillDone=function() end,destroy=function() end}
  end,
  createFoundList=function()
    return {Count=0,Address={},initialize=function() end,destroy=function() end}
  end
}
for k,v in pairs(api) do _G[k]=v end
local Core=assert(loadfile('releases/CESuite_Core.lua','t',setmetatable({api=api,require=require},{__index=_G})))()
local exportRes=Core.exportReports('__BASE_EXPORT__',{confirmOverwrite=function() return true end})
assert(exportRes.status=='complete','exportReports failed: '..tostring(exportRes.error))
assert(Core.state.busy==false,'busy guard not cleared')
'''


class ReportingIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema_data = json.loads(RUNTIME_SCHEMA.read_text(encoding='utf-8'))
        cls.runtime_validator = Draft202012Validator(schema_data)
        static_data = json.loads(STATIC_SCHEMA.read_text(encoding='utf-8'))
        cls.static_validator = Draft202012Validator(static_data)

        cls.directory = tempfile.TemporaryDirectory(prefix='CESuite 030E test ')
        cls.tmp = Path(cls.directory.name)
        base_export = str(cls.tmp / 'report_s95').replace('\\', '/')

        script = (HARNESS.replace('__SCRIPT95__', str(SCRIPT95_PATH).replace('\\', '/'))
                         .replace('__UE__', str(UE_PATH).replace('\\', '/'))
                         .replace('__LOADER__', str(LOADER_PATH).replace('\\', '/'))
                         .replace('__BASE_EXPORT__', base_export))

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

        cls.simple_text = (cls.tmp / 'report_s95_Simple.md').read_text(encoding='utf-8')
        cls.extensive_json = json.loads((cls.tmp / 'report_s95_Extensive.json').read_text(encoding='utf-8'))

    def test_extensive_conforms_to_schema_with_coverage_and_dynamic(self):
        self.runtime_validator.validate(self.extensive_json)
        self.assertIn('coverage', self.extensive_json)
        self.assertIn('dynamic_analysis', self.extensive_json)
        dyn = self.extensive_json['dynamic_analysis']
        self.assertIn('counts', dyn)
        self.assertIn('patterns', dyn)
        self.assertIn('edges', dyn)

    def test_coverage_summary_in_simple_report(self):
        text = self.simple_text
        self.assertIn('## Coverage Summary', text)
        self.assertIn('### Collection', text)
        self.assertIn('### Discovery', text)
        self.assertIn('### Validation', text)
        self.assertIn('Candidates: 31 from 52 entities', text)
        self.assertIn('Attempted: 0 of 31 candidate(s)', text)
        self.assertIn('Validated: 0', text)

    def test_dynamic_provenance_and_candidates_in_simple_report(self):
        text = self.simple_text
        self.assertIn('## Dynamic Analysis & Provenance', text)
        self.assertIn('### Discovered Candidates', text)
        self.assertIn('Showing top 10 of', text)
        self.assertIn('### Unresolved Dependencies', text)
        self.assertIn('LaunchUEInfoScanner', text)
        self.assertIn('### Provenance Relationships', text)
        self.assertIn('### Providers & Consumers', text)

    def test_terminology_safety_no_dangerous_claims(self):
        text = self.simple_text
        self.assertNotIn('working signature', text.lower())
        self.assertNotIn('31 working', text.lower())
        self.assertNotIn('100% validated', text.lower())
        self.assertNotIn('auto-repaired', text.lower())


if __name__ == '__main__':
    unittest.main()
