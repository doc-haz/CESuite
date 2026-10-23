"""Inert, bounded Lua source inventory. This is deliberately not a Lua VM.

Values describe source expressions, never runtime values or memory matches.
No eval, Lua loader, process API, filesystem include or user function is called.
"""
import hashlib
import re
import zlib
from dataclasses import dataclass

MAX_SOURCE = 2 * 1024 * 1024
MAX_TOKENS = 150000
MAX_DEPTH = 48
MAX_VALUE = 65536
ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%()*+,-./:;=?@[]^_{}'
LEXEME = re.compile(r'[A-Za-z_][A-Za-z_0-9]*|0[xX][0-9a-fA-F]+|[0-9]+|\.\.|==|~=|<=|>=|.')
LONG = re.compile(r'\[(=*)\[')


def embedded_lua(root):
    """Decode CE Base85/raw DEFLATE containing a size-prefixed file."""
    total = 0
    for node in root.findall('./Files/*'):
        if not node.tag.lower().endswith('.lua'):
            continue
        try:
            text = node.text or ''
            if node.get('Encoding') != 'Ascii85' or len(text) > MAX_SOURCE:
                raise ValueError('unsupported encoding or encoded size limit')
            if len(text) % 5 == 1:
                raise ValueError('invalid Base85 length')
            raw = bytearray()
            for i in range(0, len(text), 5):
                group = text[i:i+5]
                n = 0
                for c in group + ALPHABET[-1] * (5-len(group)):
                    n = n * 85 + ALPHABET.index(c)
                if n > 0xffffffff:
                    raise ValueError('Base85 overflow')
                raw.extend(n.to_bytes(4, 'big')[:len(group)-1])
            if len(raw) < 6:
                raise ValueError('short size-prefixed stream')
            decoder = zlib.decompressobj(-15)
            decoded = decoder.decompress(bytes(raw), MAX_SOURCE + 5)
            if len(decoded) > MAX_SOURCE + 4 or total + len(decoded) > 8 * MAX_SOURCE:
                raise ValueError('decompressed size limit')
            size = int.from_bytes(decoded[:4], 'little')
            data = decoded[4:]
            if len(data) != size or not decoder.eof or decoder.unused_data:
                raise ValueError('invalid compressed size or trailing data')
            total += size
            yield node.tag, data.decode('utf-8-sig'), None
        except (ValueError, UnicodeError, zlib.error) as exc:
            yield node.tag, None, str(exc)


@dataclass
class Token:
    value: str
    line: int
    kind: str = 'symbol'


def tokenize(source):
    if len(source.encode('utf-8')) > MAX_SOURCE:
        raise ValueError('Lua source size limit')
    tokens, i, line = [], 0, 1
    while i < len(source):
        c = source[i]
        if c.isspace():
            line += c == '\n'
            i += 1
            continue
        comment = source.startswith('--', i)
        start = i + 2 if comment else i
        long = LONG.match(source, start) if source[start:start+1] == '[' else None
        if long:
            close = ']' + long[1] + ']'
            end = source.find(close, start + len(long[0]))
            if end < 0:
                raise ValueError('unterminated long string/comment')
            value = source[start+len(long[0]):end]
            if not comment:
                tokens.append(Token(value[1:] if value.startswith('\n') else value, line, 'string'))
            end += len(close)
        elif comment:
            end = source.find('\n', i)
            end = len(source) if end < 0 else end
        elif c in "\"'":
            end, value, valid = i+1, '', True
            escapes = {'n':'\n', 'r':'\r', 't':'\t', '\\':'\\', '"':'"', "'":"'"}
            while end < len(source) and source[end] != c:
                if source[end] == '\\':
                    end += 1
                    if end >= len(source):
                        break
                    valid &= source[end] in escapes
                    value += escapes.get(source[end], '')
                else:
                    value += source[end]
                end += 1
            if end >= len(source):
                raise ValueError('unterminated string')
            end += 1
            tokens.append(Token(value, line, 'string' if valid else 'unknown'))
        else:
            m = LEXEME.match(source, i)
            value = m[0]
            end = i + len(value)
            tokens.append(Token(value, line, 'name' if re.fullmatch(r'[A-Za-z_]\w*', value) else 'symbol'))
        line += source[i:end].count('\n')
        i = end
        if len(tokens) > MAX_TOKENS:
            raise ValueError('Lua token limit')
    return tokens


def normalize(pattern):
    if not isinstance(pattern, str):
        return None
    compact = re.sub(r'\s+', '', pattern)
    if not compact or len(compact) > MAX_VALUE or len(compact) % 2 or not re.fullmatch(r'[0-9a-fA-F?xX*]+', compact):
        return None
    return ' '.join(re.sub('[xX*]', '?', compact[i:i+2]).upper() for i in range(0, len(compact), 2))


class Inventory:
    def __init__(self, source):
        self.tokens = tokenize(source)
        self.definitions = {}
        self.active = set()
        self.trace = set()
        self.steps = 0
        t = self.tokens
        # Single source definition only. Reassignments are never guessed.
        for i, token in enumerate(t):
            if token.kind == 'name':
                name, end = self.path(i)
                if self.at(end) == '=' and (i == 0 or self.at(i-1) not in ('.', ':')):
                    self.definitions.setdefault(name, []).append(end+1)

    def at(self, i):
        return self.tokens[i].value if i < len(self.tokens) else ''

    def path(self, i):
        name, i = self.at(i), i+1
        while self.at(i) == '.' and i+1 < len(self.tokens) and self.tokens[i+1].kind == 'name':
            name += '.' + self.at(i+1)
            i += 2
        return name, i

    def boundary(self, i):
        stack = []
        pairs = {'(':')', '[':']', '{':'}'}
        while i < len(self.tokens):
            value = self.at(i)
            if not stack and value in (',', ';', '}', ')'):
                return i
            if value in pairs:
                stack.append(pairs[value])
            elif stack and value == stack[-1]:
                stack.pop()
            i += 1
        return i

    def expr(self, i, depth=0):
        self.steps += 1
        if depth > MAX_DEPTH or self.steps > 300000:
            raise ValueError('Lua expression resource limit')
        if i >= len(self.tokens):
            return None, i
        token = self.tokens[i]
        value, end = None, i+1
        if token.kind == 'string':
            value = token.value
        elif token.value.isdigit():
            value = int(token.value) if len(token.value) < 12 else None
        elif token.value == '{':
            value, index = {}, 1
            while self.at(end) and self.at(end) != '}':
                before = end
                if self.at(end) == '[':
                    key, end = self.expr(end+1, depth+1)
                    if self.at(end) != ']' or self.at(end+1) != '=':
                        return None, end
                    end += 2
                elif end+1 < len(self.tokens) and self.tokens[end].kind == 'name' and self.at(end+1) == '=':
                    key, end = self.at(end), end+2
                else:
                    key, index = index, index+1
                item_start = end
                item, end = self.expr(end, depth+1)
                if self.at(end) not in (',', ';', '}'):
                    item, end = None, self.boundary(item_start)
                if isinstance(key, (str, int)):
                    value[key] = item
                if self.at(end) in (',', ';'):
                    end += 1
                elif self.at(end) != '}':
                    return None, max(end, before+1)
            end += 1
        elif token.kind == 'name':
            name, end = self.path(i)
            fields = []
            while name not in self.definitions and '.' in name:
                name, field = name.rsplit('.', 1)
                fields.insert(0, field)
            positions = self.definitions.get(name, [])
            if len(positions) == 1 and name not in self.active and positions[0] < i:
                self.trace.add((name, self.tokens[positions[0]].line))
                self.active.add(name)
                try:
                    value, _ = self.expr(positions[0], depth+1)
                finally:
                    self.active.remove(name)
                for field in fields:
                    value = value.get(field) if isinstance(value, dict) else None
        elif token.value == '(':
            value, end = self.expr(i+1, depth+1)
            if self.at(end) != ')':
                return None, end
            end += 1
        while self.at(end) in ('[', '.'):
            if self.at(end) == '.':
                key, end = self.at(end+1), end+2
            else:
                key, end = self.expr(end+1, depth+1)
                if self.at(end) != ']':
                    return None, end
                end += 1
            value = value.get(key) if isinstance(value, dict) and isinstance(key, (int, str)) else None
        if self.at(end) == '(':
            # Calls are opaque, including calls after an apparently literal value.
            level, end = 1, end+1
            while end < len(self.tokens) and level:
                level += (self.at(end) == '(') - (self.at(end) == ')')
                end += 1
            value = None
        if self.at(end) == '..':
            rhs, end = self.expr(end+1, depth+1)
            value = value + rhs if isinstance(value, str) and isinstance(rhs, str) and len(value)+len(rhs) <= MAX_VALUE else None
        if self.at(end) in ('+', '-', '*', '/', '%', 'and', 'or', '==', '~=', '<', '>', '<=', '>='):
            return None, end
        return value, end


def analyze_lua(source, script_id):
    """Return source candidates. Control flow, scope and mutation remain unknown."""
    inv = Inventory(source)
    observations = []
    source_hash = hashlib.sha256(source.encode()).hexdigest()
    sinks = {'aobscan':0, 'aobscanmodule':2, 'aobscanregion':3, 'customscan':1}
    def emit(index, sink, value, evidence, symbol=None, scope=None):
        pattern = normalize(value)
        observations.append(dict(script_id=script_id, line=inv.tokens[index].line,
            sink=sink, symbol=symbol if isinstance(symbol, str) else None,
            pattern=pattern, raw_pattern=value if isinstance(value, str) else None,
            status='source-candidate' if pattern else 'unknown', confidence='lexical',
            provenance='static-lua', evidence=evidence, scope=scope,
            unknowns=['runtime control flow, lexical scope, aliases and mutations are not proven',
                      'scan scope and wrapper runtime behavior are not evaluated'],
            match_count=None, uniqueness='unverified'))
    def rows(value, path, depth=0):
        if depth > MAX_DEPTH or not isinstance(value, dict):
            return
        if isinstance(value.get(1), str) and 2 in value:
            yield value, path
        else:
            for key, item in value.items():
                yield from rows(item, path + [str(key)], depth+1)
    for i, token in enumerate(inv.tokens):
        if token.kind != 'name' or (i and inv.at(i-1) in ('.', ':', 'function')):
            continue
        name, end = inv.path(i)
        lower = name.lower()
        if inv.at(end) != '(' or lower not in {*sinks, 'register.multicustomscan', 'register.onenable'}:
            continue
        inv.trace.clear()
        args, pos = [], end+1
        while inv.at(pos) and inv.at(pos) != ')':
            value, nxt = inv.expr(pos)
            if inv.at(nxt) not in (',', ')'):
                value, nxt = None, inv.boundary(pos)
            args.append(value)
            if inv.at(nxt) != ',' or nxt <= pos:
                break
            pos = nxt+1
        evidence = [dict(line=token.line, expression=name, sha256=source_hash)]
        evidence += [dict(expression=n, line=line) for n, line in sorted(inv.trace)]
        if lower in sinks:
            n = sinks[lower]
            sym = None
            if lower == 'aobscanmodule':
                if len(args) == 2:
                    n = 1
                elif len(args) >= 3 and isinstance(args[0], str):
                    sym = args[0]
            elif lower == 'aobscanregion':
                if len(args) >= 4 and isinstance(args[0], str):
                    sym = args[0]
            elif lower == 'customscan':
                if len(args) >= 2 and isinstance(args[0], str):
                    sym = args[0]
            emit(i, name, args[n] if len(args)>n else None, evidence, symbol=sym,
                 scope=('module' if lower=='aobscanmodule' else 'region' if lower=='aobscanregion' else 'unknown'))
        else:
            count = 0
            for arg in args:
                for row, path in rows(arg, []):
                    emit(i, name, row.get(2), evidence + [dict(table_path=path)], row.get(1), 'wrapper-unknown')
                    count += 1
            if not count:
                emit(i, name, None, evidence)
    # Library signature declarations are retained independently; never silently
    # bind Obj.Sig to UE.Sig or assume any library initialization took place.
    def declarations(value, path):
        if isinstance(value, dict):
            for key, item in value.items():
                yield from declarations(item, path + [str(key)])
        elif normalize(value):
            yield value, path
    for name, positions in inv.definitions.items():
        if len(positions) == 1 and (name.endswith('.Sig') or '.Sig.' in name):
            value, _ = inv.expr(positions[0])
            for pattern, path in declarations(value, [name]):
                emit(positions[0], 'unlinked-library-declaration', pattern,
                     [dict(line=inv.tokens[positions[0]].line, expression='.'.join(path), sha256=source_hash)])
    return observations
