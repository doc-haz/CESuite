import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from build_ce import version


class BuildVersionTests(unittest.TestCase):
    def test_extract_from_core_file(self):
        v = version()
        self.assertEqual(v, '0.2.0-beta1')

    def test_multiple_fields_anchoring(self):
        source = """
        local schema_version='0.1'
        local core_version='0.1.9'
        Core.version='0.2.0-beta1'
        """
        self.assertEqual(version(source), '0.2.0-beta1')

    def test_core_table_declaration(self):
        source = "local Core={identity='CESuiteCore',version='0.2.0-beta1',schema_version='0.1'}"
        self.assertEqual(version(source), '0.2.0-beta1')

    def test_negative_missing_or_other_fields(self):
        negative_cases = [
            "schema_version='0.1'",
            "core_version='0.1.9'",
            "other_module.version='0.2.0'",
            "Core.version=''",
            "local Core={identity='CESuiteCore',schema_version='0.1'}",
            ""
        ]
        for src in negative_cases:
            with self.subTest(source=src):
                with self.assertRaises(ValueError):
                    version(src)


if __name__ == '__main__':
    unittest.main()
