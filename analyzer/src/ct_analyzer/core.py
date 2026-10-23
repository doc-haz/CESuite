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


def source_rows(source):
    """Lexical boundaries only; opaque branches never enter inventories."""
    block = cblock = False
    mode, close, quote, depth = None, None, None, 0
    number = 0
    for number, raw in enumerate(source.split('\n'), 1):
        trimmed = raw.strip().lower()
        if mode:
            if not close and not quote and trimmed == '{$asm}':
                mode = None
                yield number, 'asm', '', None
                continue
            if mode == 'lua' and not close and not quote and trimmed in ('[enable]', '[disable]'):
                yield number, 'section', trimmed, None
                continue
            # Track Lua strings and long comments so a literal {$asm} cannot escape.
            i = 0
            while i < len(raw):
                if close:
                    if raw.startswith(close, i):
                        i += len(close); close = None
                    else:
                        i += 1
                elif quote:
                    if raw[i] == chr(92):
                        i += 2
                    else:
                        if raw[i] == quote: quote = None
                        i += 1
                elif raw.startswith('--', i):
                    match = re.match(r'\[(=*)\[', raw[i+2:])
                    if not match: break
                    close = ']' + match[1] + ']'; i += 2 + len(match[0])
                elif raw[i] in "\"'":
                    quote = raw[i]; i += 1
                else:
                    match = re.match(r'\[(=*)\[', raw[i:])
                    if match:
                        close = ']' + match[1] + ']'; i += len(match[0])
                    else: i += 1
            if mode == 'opaque' and not close and not quote and trimmed in ('[enable]', '[disable]'):
                yield number, 'section_unknown', '', 'SECTION-INDETERMINATE'
            yield number, mode, raw if mode == 'lua' else '', None
            continue
        if not block and not cblock and (trimmed == '{$lua}' or re.match(r'^\{\$luacode\b', trimmed)):
            mode = 'lua' if trimmed == '{$lua}' and depth == 0 else 'opaque'
            yield number, 'directive', '', 'OPAQUE-SOURCE' if mode == 'opaque' else None
            continue
        clean, aaquote, i = '', None, 0
        while i < len(raw):
            c, pair = raw[i], raw[i:i+2]
            if block:
                if c == '}': block = False
            elif cblock:
                if pair == '*/': cblock = False; i += 1
            elif aaquote:
                clean += c
                if c == aaquote: aaquote = None
            elif c in "\"'": aaquote = c; clean += c
            elif pair == '//': break
            elif pair == '/*': cblock = True; i += 1
            elif pair == '{$':
                end = raw.find('}', i+2)
                if end < 0: clean += raw[i:]; break
                clean += raw[i:end+1]; i = end
            elif c == '{': block = True
            else: clean += c
            i += 1
        directives = []
        aaquote, i = None, 0
        while i < len(clean):
            c = clean[i]
            if aaquote:
                if c == aaquote: aaquote = None
                i += 1
            elif c in "\"'": aaquote = c; i += 1
            elif clean.startswith('{$', i):
                match = re.match(r'\w+', clean[i+2:])
                if match: directives.append(match[0].lower())
                end = clean.find('}', i+2)
                if end < 0: break
                i = end + 1
            elif clean[i:i+8].lower() == '[enable]' or clean[i:i+9].lower() == '[disable]':
                directives.append('section_header'); i += 1
            else: i += 1
        handled = False
        for directive in directives:
            if directive in ('luacode', 'lua'):
                mode = 'lua' if clean.strip().lower() == '{$lua}' and depth == 0 else 'opaque'
                yield number, 'directive', '', 'OPAQUE-SOURCE' if mode == 'opaque' else None
                handled = True
                break
            if directive in ('ifdef', 'ifndef'):
                depth += 1; handled = True
                yield number, 'directive', '', 'CONDITIONAL-SOURCE'
            elif directive == 'section_header' and depth:
                yield number, 'section_unknown', '', 'SECTION-INDETERMINATE'
                handled = True
            elif directive == 'endif':
                yield number, 'directive', '', 'CONDITIONAL-SOURCE' if depth else 'CONDITIONAL-UNMATCHED'
                depth = max(0, depth - 1); handled = True
        if handled:
            continue
        if depth:
            if clean.strip().lower() in ('[enable]', '[disable]'):
                yield number, 'section_unknown', '', 'SECTION-INDETERMINATE'
            else:
                yield number, 'opaque', '', None
        elif re.match(r'^\s*(hook|unhook|hook5|aobscanfunction|aobscanregion)\s*\(', clean, re.I):
            yield number, 'opaque', '', 'OPAQUE-COMMAND'
        else:
            yield number, 'aa', clean, None
    if depth or mode == 'opaque':
        yield number, 'directive', '', 'OPAQUE-INCOMPLETE'


def aa_lines(source):
    for number, kind, text, note in source_rows(source):
        if kind in ('aa', 'section', 'section_unknown'):
            yield number, '[UNKNOWN]' if kind == 'section_unknown' else text


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

    lexical_text = {}

    def script(language, text, record, origin):
        sid = 'script-' + str(len(report['scripts']) + 1)
        report['scripts'].append(dict(id=sid, record_key=record, language=language,
                                      origin=origin, text=text))
        if language == 'AA':
            rows = list(source_rows(text))
            lexical_text[sid] = '\n'.join(row[2] for row in rows if row[1] in ('aa', 'lua'))
            for number, kind, content, note in rows:
                if note:
                    warn(note, 'Opaque source observed lexically; branches and post-source semantics are not evaluated.', sid, number)
            section, disable, disable_content = 'common', False, False
            for number, line in aa_lines(text):
                if line.strip().upper() in ('[ENABLE]', '[DISABLE]', '[UNKNOWN]'):
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
            # Executable/opaque content in DISABLE is not evidence of empty cleanup.
            in_disable = False
            for _, kind, content, note in rows:
                if kind in ('aa', 'section') and content.strip().lower() in ('[enable]', '[disable]'):
                    in_disable = content.strip().lower() == '[disable]'
                elif in_disable and (kind == 'lua' or note or content.strip()):
                    disable_content = True
            if disable and not disable_content:
                warn('EMPTY-DISABLE', 'Empty DISABLE may be intentional for a persistent library; review its lifecycle contract.', sid)
            if re.search(r'(?im)^\s*jmp\s+', '\n'.join(x[1] for x in aa_lines(text))):
                warn('HOOK-REVIEW', 'Review anchor versus hook, short5/far14 reach, whole-instruction overwrite, relocation, exact restore and restore-before-free.', sid)
            chunk = []
            for _, kind, content, _ in rows + [(0, 'asm', '', None)]:
                if kind == 'lua':
                    chunk.append(content)
                elif chunk:
                    script('Lua', '\n'.join(chunk), record, sid + ':embedded-lua')
                    chunk = []
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
        tokens = set(re.findall(r'[A-Za-z_][\w.]*', lexical_text.get(consumer['id'], consumer['text']).casefold()))
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
