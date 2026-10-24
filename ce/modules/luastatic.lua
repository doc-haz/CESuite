-- Bounded static Lua AOB inventory in pure Lua 5.3.
-- Never executes inspected Lua, user functions or target memory.
local U = require('util')
local M = {}

local MAX_SOURCE = 2 * 1024 * 1024
local MAX_TOKENS = 150000
local MAX_DEPTH = 48
local MAX_VALUE = 65536

local function ror(x, n)
  x = x & 0xffffffff
  return ((x >> n) | (x << (32 - n))) & 0xffffffff
end

local function sha256(msg)
  msg = tostring(msg or '')
  local h0, h1, h2, h3, h4, h5, h6, h7 =
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local k = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  }
  local len = #msg * 8
  local padded = msg .. string.char(0x80)
  local rem = (#padded + 8) % 64
  if rem > 0 then padded = padded .. string.rep(string.char(0), 64 - rem) end
  padded = padded .. string.pack('>I8', len)
  for chunk_start = 1, #padded, 64 do
    local w = {}
    for i = 0, 15 do
      w[i] = string.unpack('>I4', padded, chunk_start + i * 4)
    end
    for i = 16, 63 do
      local s0 = (ror(w[i-15], 7) ~ ror(w[i-15], 18) ~ (w[i-15] >> 3)) & 0xffffffff
      local s1 = (ror(w[i-2], 17) ~ ror(w[i-2], 19) ~ (w[i-2] >> 10)) & 0xffffffff
      w[i] = (w[i-16] + s0 + w[i-7] + s1) & 0xffffffff
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 0, 63 do
      local S1 = (ror(e, 6) ~ ror(e, 11) ~ ror(e, 25)) & 0xffffffff
      local ch = ((e & f) ~ ((~e) & g)) & 0xffffffff
      local temp1 = (h + S1 + ch + k[i+1] + w[i]) & 0xffffffff
      local S0 = (ror(a, 2) ~ ror(a, 13) ~ ror(a, 22)) & 0xffffffff
      local maj = ((a & b) ~ (a & c) ~ (b & c)) & 0xffffffff
      local temp2 = (S0 + maj) & 0xffffffff
      h = g
      g = f
      f = e
      e = (d + temp1) & 0xffffffff
      d = c
      c = b
      b = a
      a = (temp1 + temp2) & 0xffffffff
    end
    h0 = (h0 + a) & 0xffffffff
    h1 = (h1 + b) & 0xffffffff
    h2 = (h2 + c) & 0xffffffff
    h3 = (h3 + d) & 0xffffffff
    h4 = (h4 + e) & 0xffffffff
    h5 = (h5 + f) & 0xffffffff
    h6 = (h6 + g) & 0xffffffff
    h7 = (h7 + h) & 0xffffffff
  end
  return string.format('%08x%08x%08x%08x%08x%08x%08x%08x', h0, h1, h2, h3, h4, h5, h6, h7)
end

function M.normalize(pattern)
  if type(pattern) ~= 'string' then return nil end
  local compact = pattern:gsub('%s+', '')
  if #compact == 0 or #compact > MAX_VALUE or #compact % 2 ~= 0 or not compact:match('^[0-9a-fA-F?xX*]+$') then
    return nil
  end
  local parts = {}
  for i = 1, #compact, 2 do
    local pair = compact:sub(i, i+1):gsub('[xX*]', '?'):upper()
    parts[#parts+1] = pair
  end
  return table.concat(parts, ' ')
end

local function tokenize(source)
  if #source > MAX_SOURCE then
    error('Lua source size limit')
  end
  local tokens, i, line = {}, 1, 1
  while i <= #source do
    local c = source:sub(i, i)
    if c:match('%s') then
      if c == '\n' then line = line + 1 end
      i = i + 1
    elseif source:sub(i, i+1) == '--' then
      local level = source:sub(i+2):match('^%[(=*)%[')
      if level then
        local close = ']' .. level .. ']'
        local s_start = i + 4 + #level
        local s_end = source:find(close, s_start, true)
        if not s_end then error('unterminated long string/comment') end
        local sub = source:sub(i, s_end + #close - 1)
        for _ in sub:gmatch('\n') do line = line + 1 end
        i = s_end + #close
      else
        local nl = source:find('\n', i + 2, true)
        i = nl or (#source + 1)
      end
    elseif c == '[' and source:sub(i):match('^%[(=*)%[') then
      local level = source:sub(i):match('^%[(=*)%[')
      local close = ']' .. level .. ']'
      local s_start = i + 2 + #level
      local s_end = source:find(close, s_start, true)
      if not s_end then error('unterminated long string/comment') end
      local val = source:sub(s_start, s_end - 1)
      if val:sub(1, 1) == '\n' then val = val:sub(2) end
      tokens[#tokens+1] = { value = val, line = line, kind = 'string' }
      local sub = source:sub(i, s_end + #close - 1)
      for _ in sub:gmatch('\n') do line = line + 1 end
      i = s_end + #close
    elseif c == '"' or c == "'" then
      local q = c
      local s_start = i + 1
      local j = s_start
      local parts = {}
      local valid = true
      while j <= #source do
        local ch = source:sub(j, j)
        if ch == '\\' then
          local esc = source:sub(j+1, j+1)
          if esc == 'n' then parts[#parts+1] = '\n'
          elseif esc == 'r' then parts[#parts+1] = '\r'
          elseif esc == 't' then parts[#parts+1] = '\t'
          elseif esc == '\\' or esc == '"' or esc == "'" then parts[#parts+1] = esc
          else
            valid = false
          end
          j = j + 2
        elseif ch == q then
          break
        elseif ch == '\n' or ch == '\r' then
          valid = false
          break
        else
          parts[#parts+1] = ch
          j = j + 1
        end
      end
      if j > #source or source:sub(j, j) ~= q then error('unterminated string') end
      if valid then
        tokens[#tokens+1] = { value = table.concat(parts), line = line, kind = 'string' }
      else
        tokens[#tokens+1] = { value = 'unknown', line = line, kind = 'unknown' }
      end
      i = j + 1
    elseif c:match('[0-9]') or (c == '.' and source:sub(i+1, i+1):match('[0-9]')) then
      local s_start = i
      while i <= #source and source:sub(i, i):match('[0-9a-fA-FxX%.]') do i = i + 1 end
      tokens[#tokens+1] = { value = source:sub(s_start, i-1), line = line, kind = 'number' }
    elseif c:match('[A-Za-z_]') then
      local s_start = i
      while i <= #source and source:sub(i, i):match('[A-Za-z0-9_]') do i = i + 1 end
      tokens[#tokens+1] = { value = source:sub(s_start, i-1), line = line, kind = 'name' }
    elseif source:sub(i, i+1) == '..' then
      tokens[#tokens+1] = { value = '..', line = line, kind = 'op' }
      i = i + 2
    elseif source:sub(i, i+1):match('^[~=<>]=') then
      tokens[#tokens+1] = { value = source:sub(i, i+1), line = line, kind = 'op' }
      i = i + 2
    else
      tokens[#tokens+1] = { value = c, line = line, kind = 'punct' }
      i = i + 1
    end
    if #tokens > MAX_TOKENS then error('Lua token limit') end
  end
  return tokens
end

local function createInventory(tokens)
  local inv = { tokens = tokens, definitions = {}, assignments = {}, active = {}, trace = {}, steps = 0 }

  function inv.at(idx)
    return inv.tokens[idx] and inv.tokens[idx].value or ''
  end

  function inv.path(idx)
    local parts = { inv.at(idx) }
    local cur = idx + 1
    while inv.at(cur) == '.' and inv.tokens[cur+1] and inv.tokens[cur+1].kind == 'name' do
      parts[#parts+1] = inv.tokens[cur+1].value
      cur = cur + 2
    end
    return table.concat(parts, '.'), cur
  end

  function inv.boundary(idx)
    local stack = {}
    local pairs_map = { ['('] = ')', ['['] = ']', ['{'] = '}' }
    local cur = idx
    while cur <= #inv.tokens do
      local val = inv.at(cur)
      if #stack == 0 and (val == ',' or val == ';' or val == '}' or val == ')') then
        return cur
      end
      if pairs_map[val] then
        stack[#stack+1] = pairs_map[val]
      elseif #stack > 0 and val == stack[#stack] then
        stack[#stack] = nil
      end
      cur = cur + 1
    end
    return cur
  end

  for i, token in ipairs(tokens) do
    if token.kind == 'name' then
      local name, endIdx = inv.path(i)
      if inv.at(endIdx) == '=' and (i == 1 or (inv.at(i-1) ~= '.' and inv.at(i-1) ~= ':')) then
        inv.definitions[name] = inv.definitions[name] or {}
        inv.definitions[name][#inv.definitions[name]+1] = endIdx + 1
        inv.assignments[name] = (inv.assignments[name] or 0) + 1
      end
    end
  end

  function inv.expr(idx, depth)
    depth = depth or 0
    inv.steps = inv.steps + 1
    if depth > MAX_DEPTH or inv.steps > 300000 then
      error('Lua expression resource limit')
    end
    if idx > #inv.tokens then return nil, idx end
    local token = inv.tokens[idx]
    if not token then return nil, idx end
    local value, cur = nil, idx + 1

    if token.kind == 'string' then
      value = token.value
    elseif token.kind == 'number' and token.value:match('^%d+$') then
      if #token.value < 12 then value = tonumber(token.value) else value = nil end
    elseif token.value == '{' then
      value = {}
      local key_order = {}
      local index = 1
      while inv.at(cur) ~= '' and inv.at(cur) ~= '}' do
        local before = cur
        local key = nil
        if inv.at(cur) == '[' then
          local kVal, nxt = inv.expr(cur + 1, depth + 1)
          if inv.at(nxt) ~= ']' or inv.at(nxt + 1) ~= '=' then
            return nil, nxt
          end
          key = kVal
          cur = nxt + 2
        elseif cur + 1 <= #inv.tokens and inv.tokens[cur].kind == 'name' and inv.at(cur + 1) == '=' then
          key = inv.at(cur)
          cur = cur + 2
        else
          key = index
          index = index + 1
        end
        local item_start = cur
        local item, nxt = inv.expr(cur, depth + 1)
        cur = nxt
        if inv.at(cur) ~= ',' and inv.at(cur) ~= ';' and inv.at(cur) ~= '}' then
          item = nil
          cur = inv.boundary(item_start)
        end
        if type(key) == 'string' or type(key) == 'number' then
          if value[key] == nil and rawget(value, key) == nil then
            key_order[#key_order+1] = key
          end
          value[key] = (item ~= nil) and item or U.null
        end
        if inv.at(cur) == ',' or inv.at(cur) == ';' then
          cur = cur + 1
        elseif inv.at(cur) ~= '}' then
          return nil, math.max(cur, before + 1)
        end
      end
      rawset(value, '__order', key_order)
      cur = cur + 1
    elseif token.kind == 'name' and token.value ~= 'nil' and token.value ~= 'true' and token.value ~= 'false' then
      local name, nxt = inv.path(idx)
      cur = nxt
      local fields = {}
      while not inv.definitions[name] and name:find('%.') do
        local base, fld = name:match('^(.*)%.([^.]+)$')
        if not base then break end
        name = base
        table.insert(fields, 1, fld)
      end
      local positions = inv.definitions[name]
      if positions and #positions == 1 and not inv.active[name] and positions[1] < idx then
        local defLine = inv.tokens[positions[1]] and inv.tokens[positions[1]].line or token.line
        inv.trace[#inv.trace+1] = { expression = name, line = defLine }
        inv.active[name] = true
        local ok, resolved = pcall(inv.expr, positions[1], depth + 1)
        inv.active[name] = nil
        if ok and resolved ~= nil then
          value = resolved
          for _, fld in ipairs(fields) do
            if type(value) == 'table' then
              local v = value[fld]
              value = (v ~= U.null) and v or nil
            else
              value = nil
              break
            end
          end
        end
      end
    elseif token.value == '(' then
      local innerVal, nxt = inv.expr(idx + 1, depth + 1)
      if inv.at(nxt) ~= ')' then
        return nil, nxt
      end
      value = innerVal
      cur = nxt + 1
    end

    while cur <= #inv.tokens and (inv.at(cur) == '[' or inv.at(cur) == '.') do
      local key = nil
      if inv.at(cur) == '.' then
        key = inv.at(cur + 1)
        cur = cur + 2
      else
        local kVal, nxt = inv.expr(cur + 1, depth + 1)
        if inv.at(nxt) ~= ']' then
          return nil, nxt
        end
        key = kVal
        cur = nxt + 1
      end
      if type(value) == 'table' and (type(key) == 'string' or type(key) == 'number') then
        local v = value[key]
        value = (v ~= U.null) and v or nil
      else
        value = nil
      end
    end

    if inv.at(cur) == '(' then
      local level, p = 1, cur + 1
      while p <= #inv.tokens and level > 0 do
        if inv.at(p) == '(' then level = level + 1
        elseif inv.at(p) == ')' then level = level - 1 end
        p = p + 1
      end
      cur = p
      value = nil
    end

    if inv.at(cur) == '..' then
      local rhs, nxt = inv.expr(cur + 1, depth + 1)
      cur = nxt
      if type(value) == 'string' and type(rhs) == 'string' and #value + #rhs <= MAX_VALUE then
        value = value .. rhs
      else
        value = nil
      end
    end

    local op = inv.at(cur)
    if op == '+' or op == '-' or op == '*' or op == '/' or op == '%' or op == 'and' or op == 'or'
      or op == '==' or op == '~=' or op == '<' or op == '>' or op == '<=' or op == '>=' then
      return nil, cur
    end

    return value, cur
  end

  return inv
end

local sinks = {
  aobscan = 1,
  aobscanmodule = 3,
  aobscanregion = 4,
  customscan = 2
}

local function rows(value, path, depth)
  depth = depth or 0
  if depth > MAX_DEPTH or type(value) ~= 'table' then return end
  local has1 = type(value[1]) == 'string'
  local has2 = (value[2] ~= nil) or (rawget(value, 2) ~= nil)
  if has1 and has2 then
    coroutine.yield(value, path)
  else
    local keys = rawget(value, '__order')
    if not keys then
      keys = {}
      for k in pairs(value) do if k ~= '__order' then keys[#keys+1] = k end end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    end
    for _, k in ipairs(keys) do
      if k ~= '__order' then
        local item = value[k]
        if type(item) == 'table' then
          local nextPath = {}
          for _, p in ipairs(path) do nextPath[#nextPath+1] = p end
          nextPath[#nextPath+1] = tostring(k)
          rows(item, nextPath, depth + 1)
        end
      end
    end
  end
end

function M.analyzeSource(source, scriptId)
  local tokens = tokenize(source)
  local inv = createInventory(tokens)
  local observations = U.array()
  local source_hash = sha256(source)

  local function emit(idx, sink, value, evidence, symbol, scope)
    local pattern = M.normalize(value)
    local obs = {
      script_id = scriptId or 'unknown',
      line = inv.tokens[idx] and inv.tokens[idx].line or 1,
      sink = sink,
      symbol = type(symbol) == 'string' and symbol or U.null,
      pattern = pattern or U.null,
      raw_pattern = type(value) == 'string' and value or U.null,
      status = pattern and 'source-candidate' or 'unknown',
      confidence = 'lexical',
      provenance = 'static-lua',
      evidence = evidence or U.array(),
      scope = type(scope) == 'string' and scope or U.null,
      unknowns = U.array({
        'runtime control flow, lexical scope, aliases and mutations are not proven',
        'scan scope and wrapper runtime behavior are not evaluated'
      }),
      match_count = U.null,
      uniqueness = 'unverified'
    }
    observations[#observations+1] = obs
  end

  for i, token in ipairs(inv.tokens) do
    if token.kind == 'name' and (i == 1 or (inv.at(i-1) ~= '.' and inv.at(i-1) ~= ':' and inv.at(i-1) ~= 'function')) then
      local name, cur = inv.path(i)
      local lower = name:lower()
      local isSink = sinks[lower] or lower == 'register.multicustomscan' or lower == 'register.onenable'
      if isSink and inv.at(cur) == '(' then
        inv.trace = {}
        local args, arg_count, pos = {}, 0, cur + 1
        while inv.at(pos) ~= '' and inv.at(pos) ~= ')' do
          local val, nxt = inv.expr(pos)
          if inv.at(nxt) ~= ',' and inv.at(nxt) ~= ')' then
            val = nil
            nxt = inv.boundary(pos)
          end
          arg_count = arg_count + 1
          args[arg_count] = (val ~= nil) and val or U.null
          if inv.at(nxt) ~= ',' or nxt <= pos then
            break
          end
          pos = nxt + 1
        end

        local evidence = U.array()
        evidence[#evidence+1] = { line = token.line, expression = name, sha256 = source_hash }
        table.sort(inv.trace, function(a, b)
          if a.expression ~= b.expression then return a.expression < b.expression end
          return a.line < b.line
        end)
        local seenTrace = {}
        for _, t in ipairs(inv.trace) do
          local k = t.expression .. ':' .. t.line
          if not seenTrace[k] then
            seenTrace[k] = true
            evidence[#evidence+1] = { expression = t.expression, line = t.line }
          end
        end

        if sinks[lower] then
          local n = sinks[lower]
          local sym = nil
          if lower == 'aobscanmodule' then
            if arg_count == 2 then
              n = 2
            elseif arg_count >= 3 and args[1] ~= U.null and type(args[1]) == 'string' then
              sym = args[1]
            end
          elseif lower == 'aobscanregion' then
            if arg_count >= 4 and args[1] ~= U.null and type(args[1]) == 'string' then
              sym = args[1]
            end
          elseif lower == 'customscan' then
            if arg_count >= 2 and args[1] ~= U.null and type(args[1]) == 'string' then
              sym = args[1]
            end
          end
          local sc = lower == 'aobscanmodule' and 'module' or (lower == 'aobscanregion' and 'region' or 'unknown')
          local rawVal = (n <= arg_count) and args[n] or nil
          local val = (rawVal ~= U.null) and rawVal or nil
          emit(i, name, val, evidence, sym, sc)
        else
          local count = 0
          for _, arg in ipairs(args) do
            if type(arg) == 'table' then
              local co = coroutine.create(function() rows(arg, {}) end)
              while coroutine.status(co) ~= 'dead' do
                local _, row, path = coroutine.resume(co)
                if row then
                  local rowEvidence = U.array()
                  for _, ev in ipairs(evidence) do rowEvidence[#rowEvidence+1] = ev end
                  rowEvidence[#rowEvidence+1] = { table_path = U.array(path) }
                  local rowSym = (row[1] ~= U.null and type(row[1]) == 'string') and row[1] or nil
                  local rowPat = (row[2] ~= U.null) and row[2] or nil
                  emit(i, name, rowPat, rowEvidence, rowSym, 'wrapper-unknown')
                  count = count + 1
                end
              end
            end
          end
          if count == 0 then
            emit(i, name, nil, evidence)
          end
        end
      end
    end
  end

  local function declarations(val, path, pos)
    if type(val) == 'table' then
      local keys = {}
      for k in pairs(val) do keys[#keys+1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local item = val[k]
        local np = {}
        for _, p in ipairs(path) do np[#np+1] = p end
        np[#np+1] = tostring(k)
        declarations((item ~= U.null) and item or nil, np, pos)
      end
    elseif type(val) == 'string' and M.normalize(val) then
      local ev = U.array({ { line = inv.tokens[pos] and inv.tokens[pos].line or 1, expression = table.concat(path, '.'), sha256 = source_hash } })
      emit(pos, 'unlinked-library-declaration', val, ev, nil, U.null)
    end
  end

  local defNames = {}
  for name in pairs(inv.definitions) do defNames[#defNames+1] = name end
  table.sort(defNames)
  for _, name in ipairs(defNames) do
    local positions = inv.definitions[name]
    if #positions == 1 and (name:match('%.Sig$') or name:match('%.Sig%.')) then
      local val, _ = inv.expr(positions[1])
      declarations(val, { name }, positions[1])
    end
  end

  return observations
end

function M.analyze(scripts, report)
  local observations = U.array()
  local diagnostics = U.array()
  local limitations = U.array({
    'Offline source candidates only; original runtime aobs and match counts are unchanged.',
    'Library signature declarations remain unlinked when object initialization is unknown.',
    'No target, Lua, cheats, wrappers or scan APIs were executed.',
    'Static source observations are separate from memory-verified AOB matches.'
  })

  for _, s in ipairs(scripts or {}) do
    if s.language == 'Lua' and type(s.text) == 'string' and s.text ~= '' then
      local ok, obsOrErr = pcall(M.analyzeSource, s.text, s.id)
      if ok and obsOrErr then
        for _, o in ipairs(obsOrErr) do
          observations[#observations+1] = o
        end
      else
        local errMsg = tostring(obsOrErr):gsub('^.-:%d+:%s*', '')
        diagnostics[#diagnostics+1] = {
          rule = 'LUA-STATIC-LIMIT',
          severity = 'warning',
          message = errMsg,
          script_id = s.id or U.null
        }
      end
    end
  end

  return observations, diagnostics, limitations
end

function M.enrichReport(report, sourceName, suiteVersion)
  assert(type(suiteVersion) == 'string' and suiteVersion ~= '', 'suite version required')
  local observations, diagnostics, limitations = M.analyze(report.scripts)
  local rawJson = U.call(require('exporter'), 'encode', report) or ''
  local reportSha = sha256(rawJson)

  local sourceSha = '0000000000000000000000000000000000000000000000000000000000000000'
  if report.scripts and #report.scripts > 0 then
    local combined = ''
    for _, s in ipairs(report.scripts) do
      if s.language == 'Lua' and type(s.text) == 'string' then
        combined = combined .. s.text
      end
    end
    if #combined > 0 then
      sourceSha = sha256(combined)
    end
  end

  local srcName = 'loaded-table'
  if type(sourceName) == 'string' and #sourceName > 0 then
    srcName = sourceName
  elseif report.target and type(report.target.name) == 'string' and #report.target.name > 0 and report.target.name ~= U.null then
    srcName = report.target.name
  elseif report.target and report.target.attached == false then
    srcName = 'unattached'
  end

  report.static_lua_analysis = {
    version = '0.1',
    suite_version = suiteVersion,
    source = {
      name = srcName,
      sha256 = sourceSha
    },
    runtime_report_sha256 = reportSha,
    association = 'in-memory table analysis; Cheat Engine runtime capture',
    observations = observations,
    diagnostics = diagnostics,
    limitations = limitations
  }

  return report
end

return M
