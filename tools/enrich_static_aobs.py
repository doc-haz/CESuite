"""Add offline CT evidence to a runtime report without changing its observations.

Usage: python tools/enrich_static_aobs.py table.CT runtime.json output.json
No Cheat Engine or Lua interpreter is started. Originals are never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'analyzer/src'))
from ct_analyzer.core import MAX_BYTES, analyze
from build_ce import version


def enrich(table, runtime, output):
    table, runtime, output = map(Path, (table, runtime, output))
    if output.resolve() in (table.resolve(), runtime.resolve()):
        raise ValueError('Output must differ from both inputs')
    with runtime.open('rb') as stream:
        raw = stream.read(4 * MAX_BYTES + 1)
    if len(raw) > 4 * MAX_BYTES:
        raise ValueError('Runtime report exceeds 64 MiB')
    report = json.loads(raw)
    if not isinstance(report, dict):
        raise ValueError('Runtime report must be a JSON object')
    with table.open('rb') as stream:
        static = analyze(stream.read(MAX_BYTES+1), table.name)
    report['static_lua_analysis'] = dict(
        version='0.1', suite_version=version(), source=static['source'],
        runtime_report_sha256=hashlib.sha256(raw).hexdigest(),
        association='user-supplied pair; identical loaded table is not proven',
        observations=static['lua_aobs'],
        diagnostics=[x for x in static['warnings'] if x['rule'] in ('LUA-STATIC-LIMIT','EMBEDDED-LUA-UNKNOWN')],
        limitations=['Offline source candidates only; original runtime aobs and match counts are unchanged.',
                      'Library signature declarations remain unlinked when object initialization is unknown.',
                      'No target, Lua, cheats, wrappers or scan APIs were executed.'])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n',encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('table', type=Path)
    parser.add_argument('runtime', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        enrich(args.table, args.runtime, args.output)
    except (ValueError, OSError, RecursionError) as exc:
        parser.exit(2, str(exc)+'\n')
