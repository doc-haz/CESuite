import json
from pathlib import Path
import unittest
from ct_analyzer.core import analyze

try:
    from jsonschema import Draft202012Validator, ValidationError
except ImportError:
    Draft202012Validator = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(Draft202012Validator is None, 'Install analyzer/requirements-dev.txt for schema tests')
class SchemaTests(unittest.TestCase):
    def test_schema_definitions_and_report(self):
        for path in (ROOT / 'schemas').glob('*.schema.json'):
            Draft202012Validator.check_schema(json.loads(path.read_text()))
        schema = json.loads((ROOT / 'schemas/ct-report.schema.json').read_text())
        report = analyze((ROOT / 'fixtures/synthetic.CT').read_bytes())
        validator = Draft202012Validator(schema)
        validator.validate(report)
        report['aobs'][0]['uniqueness'] = 'verified'
        with self.assertRaises(ValidationError):
            validator.validate(report)

    def test_injection_schema_rejects_executable_claim(self):
        schema = json.loads((ROOT / 'schemas/injection.schema.json').read_text())
        example = dict(schema_version='0.1', status='draft', architecture='unknown', target_build_sha256=None,
            aob=dict(scope='process',module=None,region_start=None,region_end=None,pattern='AA ??',match_count=None),
            signature_anchor=None,hook_address=None,hook_offset_expression=None,jump_form='unknown',overwrite_length=None,
            original_bytes=None,restore_bytes=None,relocation_notes=[],owned_allocations=[],owned_symbols=[],teardown_steps=[],
            validation={key:'unverified' for key in schema['properties']['validation']['properties']})
        validator = Draft202012Validator(schema)
        validator.validate(example)
        example['status'] = 'safe-to-execute'
        with self.assertRaises(ValidationError):
            validator.validate(example)
