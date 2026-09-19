"""Replay cached report scripts as inert text; never execute inspected AA/Lua.

This emits a lexical inventory, not a fresh CE runtime/process observation.
Requires a compatible Lua 5.3 library, as used by run_lua_tests.py.
"""
import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from run_lua_tests import run


def literal(value):
    # Fixed-width decimal byte escapes cannot close a Lua string or inject code.
    return '"' + ''.join('\\%03d' % b for b in value.encode('utf-8')) + '"'


def replay(source, output, library, modules=None):
    raw = source.read_bytes()
    report = json.loads(raw.decode('utf-8-sig'))
    scripts = [s for s in report['scripts'] if s['language'] == 'AA']
    modules = modules or Path(__file__).resolve().parents[1] / 'ce/modules'
    code = ['package.path=' + literal(modules.resolve().as_posix() + '/?.lua;') + '..package.path',
            "local P=require('parser');local U=require('util');local E=require('exporter')",
            "local r={scripts=U.array(),aobs=U.array(),resources=U.array(),diagnostics=U.array(),dependencies=U.array()}"]
    for s in scripts:
        code.append('P.inspect({id=' + literal(s['id']) + ',text=' + literal(s['text']) + '},r)')
    code.extend(["r.dependency_summary=require('dependencies').summarize(r.dependencies)",
                 "r.replay_input_sha256=" + literal(hashlib.sha256(raw).hexdigest()),
                 "r.observation='offline_source_replay'",
                 'local f=assert(io.open(' + literal(output.resolve().as_posix()) + ",'w'))",
                 'f:write(E.encode(r));f:close()'])
    with tempfile.TemporaryDirectory(prefix='CESuite replay ') as directory:
        harness = Path(directory) / 'replay.lua'
        harness.write_text('\n'.join(code), encoding='utf-8')
        run(library.resolve(), str(harness))
    return json.loads(output.read_text(encoding='utf-8'))


def counts(report):
    return {'occurrences': len(report['dependencies']),
            'provides': sum(d['relation'] == 'provides' for d in report['dependencies']),
            'requires': sum(d['relation'] == 'requires' for d in report['dependencies']),
            'symbols': len({d['name'] for d in report['dependencies']}),
            'resources': len(report['resources']),
            'groups': len(report['dependency_summary']),
            'locations': sum(g['location_count'] for g in report['dependency_summary'])}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Cached JSON report containing scripts')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--expect', type=Path, help='Optional validation manifest with input hash and counts')
    parser.add_argument('--modules', type=Path, help='Trusted CESuite module directory for baseline comparisons')
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error('Output must not overwrite the source report')
    if args.expect:
        expected = json.loads(args.expect.read_text(encoding='utf-8'))
        if hashlib.sha256(args.source.read_bytes()).hexdigest() != expected['input_sha256']:
            parser.error('Input hash differs from the validation manifest')
    result = replay(args.source, args.output, args.library, args.modules)
    observed = counts(result)
    print(json.dumps(observed, indent=2))
    if args.expect and observed != expected['counts']:
        parser.exit(1, 'Replay counts differ from the validation manifest\n')
