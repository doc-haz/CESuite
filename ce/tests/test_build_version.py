import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from build_ce import version


class BuildVersionTests(unittest.TestCase):
    def test_extract_from_core_file(self):
        v = version()
        self.assertEqual(v, '0.3.2')

    def test_multiple_fields_anchoring(self):
        source = """
        local schema_version='0.1'
        local core_version='0.1.9'
        Core.version='0.2.0'
        """
        self.assertEqual(version(source), '0.2.0')

    def test_core_table_declaration(self):
        source = "local Core={identity='CESuiteCore',version='0.2.0',schema_version='0.1'}"
        self.assertEqual(version(source), '0.2.0')

    def test_semver_prerelease_and_build_metadata(self):
        prerelease = "Core.version='1.0.0-rc.1'"
        self.assertEqual(version(prerelease), '1.0.0-rc.1')
        build_meta = "Core.version='1.0.0-rc.1+build.123'"
        self.assertEqual(version(build_meta), '1.0.0-rc.1+build.123')

    def test_reject_multiple_version_declarations(self):
        dup_source = """
        Core.version='0.2.0'
        Core.version='0.2.1'
        """
        with self.assertRaises(ValueError) as ctx:
            version(dup_source)
        self.assertIn('Multiple Core.version declarations', str(ctx.exception))

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
