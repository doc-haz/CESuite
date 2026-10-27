"""Validate the v0.3.1 Address Evidence contract against the real Lua serializer.

The evidence is produced by the shipped bundle with synthetic CE mocks; the JSON
is validated with schemas/address-evidence.schema.json. No target is touched.
"""
import copy
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import tempfile
import unittest

from jsonschema import Draft202012Validator, ValidationError

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / 'schemas/address-evidence.schema.json'

HARNESS = r'''
local realDate=os.date
os.date=function(f,...)
  if f=='!%Y-%m-%dT%H:%M:%SZ' then return '2026-10-24T00:00:00Z' end
  return realDate(f,...)
end
package.path='ce/modules/?.lua;'..package.path
local Export=require('exporter')
local function mock(opts)
  opts=opts or {}
  local calls=0
  local api={
    process='game.exe',
    getOpenedProcessID=function()
      calls=calls+1
      if opts.pid_change and calls>1 then return 8 end
      return opts.pid or 7
    end,
    targetIs64Bit=function() return opts.x64~=false end,
    enumModules=function()
      return opts.modules or {
        {Name='game.exe',Address=0x140000000,PathToFile='C:/g/game.exe',Is64Bit=true},
        {Name='other.dll',Address=0x7FF800000000,PathToFile='C:/g/other.dll',Is64Bit=true}
      }
    end,
    getModuleSize=function(name)
      if name=='game.exe' then return 0x100000 end
      if name=='other.dll' then return 0x2000 end
      if name=='dup.dll' then return 0x1000 end
      return nil
    end,
    getMemoryRegionInfo=function(address)
      if opts.no_region then return nil end
      return {BaseAddress=0x140001000,RegionSize=opts.region_size or 0x1000,
        AllocationBase=0x140000000,State=0x1000,Type=0x1000000,
        Protect=opts.protect or 0x20,AllocationProtect=0x04}
    end,
    readBytes=function(address,count)
      if opts.read_fail then return nil end
      local pattern=opts.bytes or {0x48,0x8B,0x05,0x10,0x00,0x00,0x00}
      local limit=count
      if opts.short then limit=math.min(limit,opts.short) end
      local data={}
      for i=1,limit do data[i]=pattern[i] or 0 end
      return data
    end,
    getAddressSafe=function() error('getAddressSafe must not be called') end,
    getAddress=function() error('getAddress must not be called') end,
    disassemble=function() error('disassemble must not be called') end
  }
  return api
end
local function apply(opts)
  for k,v in pairs(mock(opts)) do _G[k]=v end
end
getMainForm=function() return {Menu={Items={Count=0,add=function() end}}} end
createMenuItem=function() return {add=function() end,destroy=function() end,children={}} end
apply({})
local Core=assert(loadfile('releases/CESuite_Core.lua','t',setmetatable({api=_G,require=require},{__index=_G})))()
assert(Core.version=='0.3.2','unexpected version '..tostring(Core.version))
local function write(name,evidence)
  Core.exportAddressEvidence(evidence,'__DIR__/'..name..'.json')
end
local function run(name,opts,input,options)
  apply(opts or {})
  write(name,Core.inspectAddress(input,options))
end
run('resolved',{},'game.exe+1000')
run('rip_relative',{},'0x140001000')
run('partial',{bytes={0x48,0x8B},short=2},'0x140001000',{bytes=8})
run('unsupported',{bytes={0xCC}},'0x140001000')
run('detached',{pid=0},'0x140001000')
run('invalid',{},'not-an-address')
run('ambiguous',{modules={
  {Name='dup.dll',Address=0x10000000,PathToFile='C:/a/dup.dll'},
  {Name='dup.dll',Address=0x20000000,PathToFile='C:/b/dup.dll'}}},'dup.dll+10')
run('invalidated',{pid_change=true},'0x140001000')
run('no_region',{no_region=true},'0x140001000')
local f=assert(io.open('__DIR__/done','w'));f:write('ok');f:close()
'''


class AddressEvidenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema = json.loads(SCHEMA.read_text(encoding='utf-8'))
        Draft202012Validator.check_schema(schema)
        cls.schema = schema
        cls.validator = Draft202012Validator(schema)
        cls.directory = tempfile.TemporaryDirectory(prefix='CESuite address ')
        cls.tmp = Path(cls.directory.name)
        library = os.environ.get('CESUITE_LUA_LIBRARY') or ctypes.util.find_library('lua5.3')
        library = library or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        lib = ctypes.CDLL(str(library))
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                      ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
        state = lib.luaL_newstate()
        cls.assertIsNotNone(cls, state)
        script = HARNESS.replace('__DIR__', str(cls.tmp).replace('\\', '/'))
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
        if not (cls.tmp / 'done').exists():
            raise AssertionError('harness did not complete')
        cls.docs = {}
        for path in cls.tmp.glob('*.json'):
            cls.docs[path.stem] = json.loads(path.read_text(encoding='utf-8'))

    def test_every_generated_document_conforms_to_schema(self):
        self.assertTrue(self.docs, 'no documents generated')
        for name, doc in self.docs.items():
            with self.subTest(document=name):
                self.validator.validate(doc)

    def test_expected_scenarios_are_present(self):
        for name in ('resolved', 'rip_relative', 'partial', 'unsupported', 'invalid',
                     'ambiguous', 'invalidated', 'no_region'):
            self.assertIn(name, self.docs)
        self.assertEqual(self.docs['resolved']['status'], 'observed')
        self.assertEqual(self.docs['resolved']['suite_version'], '0.3.2')
        self.assertEqual(self.docs['resolved']['core_version'], '0.1.9')
        self.assertEqual(self.docs['resolved']['query']['resolution_status'], 'resolved')
        self.assertEqual(self.docs['invalid']['query']['resolution_status'], 'invalid_input')
        self.assertIsNone(self.docs['invalid']['query']['resolved_address'])
        self.assertEqual(self.docs['partial']['bytes']['read_status'], 'short_read')
        self.assertEqual(self.docs['unsupported']['instruction']['decode_status'], 'unsupported')
        self.assertEqual(self.docs['ambiguous']['query']['resolution_status'], 'ambiguous_module')
        self.assertEqual(self.docs['invalidated']['status'], 'invalidated')
        self.assertEqual(self.docs['no_region']['region']['mapped'], False)

    def test_internal_invariants_hold(self):
        for name, doc in self.docs.items():
            with self.subTest(document=name):
                limits = doc['limits']
                self.assertEqual(limits['max_addresses'], 1)
                self.assertEqual(limits['max_bytes'], 64)
                self.assertEqual(limits['persistent_timers'], 0)
                self.assertEqual(limits['runtime_breakpoints'], 0)
                self.assertEqual(limits['memory_writes'], 0)
                self.assertLessEqual(limits['bytes_read'], limits['bytes_requested'])
                if doc['bytes']['read_status'] == 'read_ok':
                    self.assertEqual(doc['bytes']['read_length'],
                                     doc['bytes']['requested_length'])
                if doc['type_advisory']['status'] == 'candidate':
                    self.assertIn(doc['type_advisory']['suggested_type'], ('Float', 'Double'))
                if doc['module']['inside_module'] is True:
                    self.assertIsInstance(doc['module']['module_name'], str)
                    self.assertRegex(doc['module']['rva'], r'^0x[0-9A-F]+$')
                if doc['region']['mapped'] is True:
                    self.assertRegex(doc['region']['base_address'], r'^0x[0-9A-F]+$')
                    self.assertIsInstance(doc['region']['region_size'], int)

    def test_schema_rejects_malformed_evidence(self):
        base = self.docs['resolved']
        corruptions = []

        bad_status = copy.deepcopy(base)
        bad_status['status'] = 'verified'
        corruptions.append(('unknown top status', bad_status))

        bad_byte_status = copy.deepcopy(base)
        bad_byte_status['bytes']['read_status'] = 'read_ok'
        bad_byte_status['bytes']['status'] = 'unknown'
        corruptions.append(('read_ok with non-observed bytes', bad_byte_status))

        bad_type = copy.deepcopy(base)
        bad_type['type_advisory']['status'] = 'candidate'
        bad_type['type_advisory']['suggested_type'] = None
        corruptions.append(('candidate type without type', bad_type))

        bad_module = copy.deepcopy(base)
        bad_module['module']['inside_module'] = True
        bad_module['module']['module_name'] = None
        corruptions.append(('inside module without name', bad_module))

        bad_limits = copy.deepcopy(base)
        bad_limits['limits']['memory_writes'] = 1
        corruptions.append(('non-zero memory writes', bad_limits))

        bad_field = copy.deepcopy(base)
        bad_field['bytes']['verified'] = True
        corruptions.append(('unknown field', bad_field))

        bad_missing = copy.deepcopy(base)
        bad_missing['query'].pop('resolution_status')
        corruptions.append(('missing required field', bad_missing))

        bad_source = copy.deepcopy(base)
        bad_source['region']['region_source'] = 'guessed'
        corruptions.append(('invalid provenance value', bad_source))

        for label, doc in corruptions:
            with self.subTest(case=label):
                with self.assertRaises(ValidationError):
                    self.validator.validate(doc)

    def test_runtime_report_schema_is_unchanged(self):
        runtime_schema = json.loads(
            (ROOT / 'schemas/runtime-report.schema.json').read_text(encoding='utf-8'))
        runtime_validator = Draft202012Validator(runtime_schema)
        legacy = json.loads((ROOT / 'fixtures/runtime-v0.1.4.json').read_text(encoding='utf-8'))
        runtime_validator.validate(legacy)
        self.assertNotIn('address_evidence', runtime_schema['properties'])


if __name__ == '__main__':
    unittest.main()
