"""Fresh synthetic serialization without preexisting ignored fixture files."""
import ctypes.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from run_lua_tests import run

class FixtureSetupTests(unittest.TestCase):
    def test_generate_runtime_fixtures_in_empty_directory(self):
        library=os.environ.get('CESUITE_LUA_LIBRARY') or ctypes.util.find_library('lua5.3')
        with tempfile.TemporaryDirectory(prefix='CESuite fresh fixtures ') as directory:
            output=Path(directory)
            self.assertEqual(list(output.iterdir()),[])
            run(Path(library or 'C:/Program Files/Cheat Engine/lua53-64.dll'),output_path=output.as_posix())
            names={'generated-report.json','generated-observed.json','generated-dependencies.json'}
            self.assertEqual({p.name for p in output.iterdir()},names)
            for name in names:
                report=json.loads((output/name).read_text(encoding='utf-8'))
                self.assertEqual(report['core_version'],'0.1.9')
                self.assertIn('dependency_summary',report)
            first={name:(output/name).read_bytes() for name in names}
            run(Path(library or 'C:/Program Files/Cheat Engine/lua53-64.dll'),output_path=output.as_posix())
            self.assertEqual(first,{name:(output/name).read_bytes() for name in names})
