"""End-to-end static report export with the public conditional representation."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from run_lua_tests import run

LUA = r'''
local function read(path)
  local f=assert(io.open(path,'rb'));local t=f:read('*a');f:close();return t
end
local script=read([[__SCRIPT__]])
local ue=read([[__UE__]])
local api={
  getOpenedProcessID=function() return 0 end,
  getCEVersion=function() return 7.72 end,
  targetIs64Bit=function() return true end,
  vtAutoAssembler=11,
  getMainForm=function() return {Menu={Items={Count=0,add=function() end}}} end,
  createMenuItem=function() return {add=function() end,destroy=function() end,children={}} end,
  showMessage=function() end,
  getAddressList=function()
    return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
      return {ID=1,Description='script95',Type=11,OffsetCount=0,Script=script}
    end}
  end
}
getMainForm=api.getMainForm
createMenuItem=api.createMenuItem
showMessage=api.showMessage
getOpenedProcessID=api.getOpenedProcessID
getCEVersion=api.getCEVersion
targetIs64Bit=api.targetIs64Bit
vtAutoAssembler=api.vtAutoAssembler
getAddressList=api.getAddressList
local Core,err=loadfile('releases/CESuite_Core.lua','t',
  setmetatable({api=api,require=require},{__index=_G}))()
assert(Core,tostring(err))
Core.exportStaticLuaReport([[__OUT__]],{helpers={{name='UE',alias='Obj',text=ue,file='ue.lua'}}})
'''


class DynamicStaticSchemaTests(unittest.TestCase):
    def test_script95_static_export_serializes_and_validates(self):
        schema = json.loads((ROOT / 'schemas/static-lua-report.schema.json').read_text(encoding='utf-8'))
        validator = Draft202012Validator(schema)
        library = os.environ.get('CESUITE_LUA_LIBRARY') or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        with tempfile.TemporaryDirectory(prefix='CESuite dynamic ') as directory:
            output = Path(directory) / 'static.json'
            lua = Path(directory) / 'driver.lua'
            lua.write_text(LUA.replace('__SCRIPT__', str(ROOT / 'ce/tests/fixtures/dynamic/script95.lua'))
                             .replace('__OUT__', str(output))
                             .replace('__UE__', str(ROOT / 'ce/tests/fixtures/dynamic/ue.lua')), encoding='utf-8')
            run(Path(library), str(lua))
            doc = json.loads(output.read_text(encoding='utf-8'))
            validator.validate(doc)
            dynamic = doc['dynamic_analysis']
            self.assertEqual(dynamic['status'], 'complete')
            self.assertEqual(dynamic['counts']['entries'], 47)
            self.assertEqual(dynamic['counts']['specs'], 52)
            self.assertEqual(dynamic['counts']['literal'], 28)
            self.assertEqual(dynamic['counts']['conditional'], 1)
            self.assertEqual(dynamic['counts']['runtime_validated'], 0)
            conditions = [p for p in dynamic['patterns']
                          if p.get('kind') == 'conditional_pattern']
            self.assertEqual(len(conditions), 1)
            condition = conditions[0]['condition']
            self.assertEqual(condition['kind'], 'conditional_expression')
            self.assertEqual(condition['resolution'], 'unknown')
            self.assertEqual(condition['dependencies'], ['LaunchUEInfoScanner'])
            self.assertEqual(condition['fallback'], 'start')
            self.assertFalse(conditions[0]['runtime_validated'])
            coverage = doc['coverage']
            self.assertTrue(coverage['collection']['complete'])
            self.assertEqual(coverage['discovery']['candidates'], 31)
            self.assertEqual(coverage['validation']['candidates'], 31)
            self.assertEqual(coverage['validation']['runtime_attempted'], 0)
            self.assertEqual(coverage['validation']['runtime_validated'], 0)
            self.assertEqual(coverage['validation']['status'], 'unavailable')
            self.assertFalse(coverage['validation']['complete'])
            self.assertIsNone(coverage['validation']['percentage'])
            self.assertIsNone(coverage['discovery']['percentage'])


if __name__ == '__main__':
    unittest.main()
