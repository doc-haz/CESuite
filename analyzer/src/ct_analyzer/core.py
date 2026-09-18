"""Bounded XML reader and conservative, line-oriented AA/Lua observations."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

MAX_BYTES = 16 * 1024 * 1024
COMMAND = re.compile(r'^\s*(aobscanmodule|aobscanregion|aobscan|globalalloc|alloc|dealloc|registersymbol|unregistersymbol|define|label)\s*\((.*)\)\s*$', re.I)


def arguments(text):
    """Split top-level comma arguments without losing quoted module names."""
    result, start, depth, quote = [], 0, 0, None
    for i, char in enumerate(text):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
        elif char == ',' and depth == 0:
            result.append(text[start:i].strip())
            start = i + 1
    result.append(text[start:].strip())
    return result


def aa_lines(source):
    """Mask AA comments and embedded Lua, preserving line numbers.

    This is not an AA compiler. Lua includes/preprocessor-generated AA are opaque.
    """
    block, lua = False, False
    for number, line in enumerate(source.splitlines(), 1):
        if line.strip().lower() == '{$lua}':
            lua = True
            continue
        if line.strip().lower() == '{$asm}':
            lua = False
            continue
        if lua:
            continue
        clean, quote, i = '', None, 0
        while i < len(line):
            c = line[i]
            if block:
                if c == '}':
                    block = False
            elif quote:
                clean += c
                if c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
                clean += c
            elif line[i:i+2] == '//':
                break
            elif c == '{':
                block = True
            else:
                clean += c
            i += 1
        yield number, clean


def analyze(data, source_name='<memory>'):
    if len(data) > MAX_BYTES:
        raise ValueError('CT exceeds the 16 MiB input limit')
    # Also detects UTF-16/32 declarations before ElementTree can expand entities.
    guard = data.replace(b'\x00', b'').upper()
    if b'<!DOCTYPE' in guard or b'<!ENTITY' in guard:
        raise ValueError('DTD and entity declarations are not supported')
    root = ET.fromstring(data)
    if root.tag != 'CheatTable':
        raise ValueError('Expected a CheatTable XML root (namespaces unsupported)')
    report = dict(schema_version='0.1', analyzer_version='0.1.0',
                  source=dict(name=source_name, sha256=hashlib.sha256(data).hexdigest()),
                  records=[], scripts=[], aobs=[], symbols=[], allocations=[],
                  dependencies=[], warnings=[],
                  limitations=['Static lexical analysis only; no execution, disassembly, process access or AOB uniqueness testing.',
                               'Computed Lua, includes, macros and complex AA syntax may not be resolved.',
                               'Dependency candidates are textual hints, not execution-order proof.'])

    def warn(rule, message, script=None, line=None):
        report['warnings'].append(dict(rule=rule, severity='review', message=message,
                                       script_id=script, line=line))

    def script(language, text, record, origin):
        sid = 'script-' + str(len(report['scripts']) + 1)
        report['scripts'].append(dict(id=sid, record_key=record, language=language,
                                      origin=origin, text=text))
        if language == 'AA':
            section, disable, disable_content = 'common', False, False
            for number, line in aa_lines(text):
                if line.strip().upper() in ('[ENABLE]', '[DISABLE]'):
                    section = line.strip()[1:-1].lower()
                    disable |= section == 'disable'
                    continue
                if section == 'disable' and line.strip():
                    disable_content = True
                match = COMMAND.match(line)
                if not match:
                    continue
                command, raw = match.group(1).lower(), match.group(2)
                args = arguments(raw)
                item = dict(script_id=sid, line=number, section=section, command=command,
                            arguments=args)
                if command.startswith('aobscan'):
                    needed = {'aobscan': 2, 'aobscanmodule': 3, 'aobscanregion': 4}[command]
                    if len(args) != needed:
                        warn('AA-SYNTAX', 'Unexpected AOB argument count; retained as raw observation.', sid, number)
                    item.update(symbol=args[0], scope={'aobscan':'process','aobscanmodule':'module','aobscanregion':'region'}[command],
                                pattern=args[-1], uniqueness='unverified')
                    report['aobs'].append(item)
                    warn('AOB-UNIQUENESS', 'Confirm exactly one match in the original scope on the current build; cross-build robustness is separate.', sid, number)
                elif command in ('alloc', 'globalalloc', 'dealloc'):
                    report['allocations'].append(item)
                else:
                    report['symbols'].append(item)
                if command in ('dealloc', 'unregistersymbol') and (not raw.strip() or '*' in raw):
                    warn('RESOURCE-OWNERSHIP', 'Broad cleanup may affect resources owned by other scripts.', sid, number)
            # Lua in DISABLE is executable content even though the AA pass masks it.
            disable_tail = re.split(r'(?im)^\s*\[DISABLE\]\s*$', text)
            if len(disable_tail) > 1 and re.search(r'(?im)^\s*\{\$lua\}', disable_tail[-1]):
                disable_content = True
            if disable and not disable_content:
                warn('EMPTY-DISABLE', 'Empty DISABLE may be intentional for a persistent library; review its lifecycle contract.', sid)
            if re.search(r'(?im)^\s*jmp\s+', '\n'.join(x[1] for x in aa_lines(text))):
                warn('HOOK-REVIEW', 'Review anchor versus hook, short5/far14 reach, whole-instruction overwrite, relocation, exact restore and restore-before-free.', sid)
            for match in re.finditer(r'(?ims)^\s*\{\$lua\}\s*\n(.*?)(?=^\s*\{\$asm\}|\Z)', text):
                script('Lua', match.group(1), record, sid + ':embedded-lua')
        else:
            for token, rule, message in [
                ('createTimer', 'TIMER-LIFECYCLE', 'Review timer ownership, disable/destroy and callbacks after teardown.'),
                ('debug_setBreakpoint', 'BREAKPOINT-OWNERSHIP', 'Track breakpoint ownership; remove only breakpoints created here.'),
                ('debugger_onBreakpoint', 'HANDLER-CHAIN', 'Preserve, chain and restore the previous handler.'),
                ('On', 'EVENT-LIFECYCLE', 'Review event handler lifetime, chaining and UI model overwrite risk.')]:
                if re.search(r'\b' + token + (r'\w*\s*=' if token == 'On' else r'\b'), text):
                    warn(rule, message + ' Lexical candidate; comments/strings may match.', sid)
        return sid

    def walk(entries, parent=None, depth=0):
        if depth > 128:
            raise ValueError('MemoryRecord nesting exceeds 128 levels')
        keys = []
        for entry in entries:
            key = 'record-' + str(len(report['records']) + 1)
            keys.append(key)
            row = dict(key=key, id=entry.findtext('ID'), parent_key=parent, children=[],
                       description=entry.findtext('Description', ''),
                       variable_type=entry.findtext('VariableType', ''),
                       address=entry.findtext('Address'),
                       offsets=[x.text or '' for x in entry.findall('./Offsets/Offset')], scripts=[])
            report['records'].append(row)
            for tag, lang in [('AssemblerScript', 'AA'), ('LuaScript', 'Lua')]:
                node = entry.find(tag)
                if node is not None:
                    row['scripts'].append(script(lang, node.text or '', key, tag))
            row['children'] = walk(entry.findall('./CheatEntries/CheatEntry'), key, depth + 1)
        return keys

    walk(root.findall('./CheatEntries/CheatEntry'))
    for node in root.findall('./LuaScript'):
        script('Lua', node.text or '', None, 'CheatTable/LuaScript')
    providers = {}
    for item in report['symbols'] + report['aobs'] + report['allocations']:
        if item['command'] in ('registersymbol', 'define', 'label', 'alloc', 'globalalloc', 'aobscan', 'aobscanmodule', 'aobscanregion'):
            for name in (item['arguments'] if item['command'] in ('registersymbol', 'label') else item['arguments'][:1]):
                providers.setdefault(name.strip().casefold(), set()).add(item['script_id'])
    for record in report['records']:
        expr = record['address'] or ''
        for token in set(re.findall(r'[A-Za-z_][\w.]*', expr)):
            if token.casefold() in providers:
                report['dependencies'].append(dict(consumer=record['key'], symbol=token,
                    providers=sorted(providers[token.casefold()]), kind='address-symbol-candidate'))
    for consumer in report['scripts']:
        tokens = set(re.findall(r'[A-Za-z_][\w.]*', consumer['text'].casefold()))
        for name in sorted(tokens & providers.keys()):
            others = sorted(providers[name] - {consumer['id']})
            if others:
                report['dependencies'].append(dict(consumer=consumer['id'], symbol=name,
                    providers=others, kind='script-text-candidate'))
    return report


def markdown(report):
    # JSON fences preserve arbitrary descriptions and scripts without allowing
    # table content to introduce Markdown links, HTML or broken code fences.
    def block(value):
        text = json.dumps(value, indent=2, ensure_ascii=False)
        fence = '`' * max(3, 1 + max((len(m[0]) for m in re.finditer(r'`+', text)), default=0))
        return fence + 'json\n' + text + '\n' + fence
    parts = ['# CT Analyzer 0.1 report', 'Static observations only. No scripts were executed.',
             'MemoryRecord tree is represented by parent_key and children links.']
    for key, value in report.items():
        parts.extend(['## ' + key.replace('_', ' ').title(), block(value)])
    return '\n\n'.join(parts) + '\n'


def main(argv=None):
    parser = argparse.ArgumentParser(description='Analyze a Cheat Engine CT offline; never execute it.')
    parser.add_argument('table', type=Path)
    parser.add_argument('--output', type=Path, default=Path('reports'))
    args = parser.parse_args(argv)
    try:
        with args.table.open('rb') as handle:
            data = handle.read(MAX_BYTES + 1)
        report = analyze(data, args.table.name)
        if args.table.resolve() in [(args.output / name).resolve() for name in ('report.json', 'report.md')]:
            raise ValueError('Output would overwrite input')
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        (args.output / 'report.md').write_text(markdown(report), encoding='utf-8')
    except (OSError, ValueError, ET.ParseError, RecursionError) as exc:
        print('CT Analyzer: ' + str(exc), file=sys.stderr)
        return 2
    print('Wrote report.json and report.md to ' + str(args.output))
    return 0
