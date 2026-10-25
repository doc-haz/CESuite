-- Static Lua/dataflow analysis for CESuite v0.3.0-dev (030B).
-- Text only: this module never calls load/loadstring/dofile/require, never
-- executes table source and never touches CE process state.
local U = require('util')
local M = {}

M.DEFAULT_LIMITS = {
  max_tokens = 200000,
  max_depth = 12,
  max_entries = 2000,
  max_edges = 5000,
  max_candidates = 5000,
  max_symbols = 2000,
  max_wrapper_depth = 4
}

local CALLBACK_CALLEES = {
  ['registercallback'] = true,
  ['registercallbacks'] = true,
  ['setcallback'] = true,
  ['setoncallback'] = true
}

local CONTRACTS = {
  ['register.onenable'] = {
    kind = 'table_sets',
    forwards_to = 'register.multicustomscan',
    consumer_role = 'scan_spec_table',
    constructs = 'aobScanRegion'
  },
  ['register.multicustomscan'] = {
    kind = 'spec_rows',
    consumer_role = 'scan_spec_table',
    constructs = 'aobScanRegion'
  }
}

local function trim(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end

local function tokenize(source, limits)
  local tokens, i, line, n = {}, 1, 1, #source
  local function push(value, kind, ln)
    tokens[#tokens+1] = {value=value, kind=kind, line=ln}
    if #tokens > limits.max_tokens then error('dynamic_token_limit') end
  end
  while i <= n do
    local c = source:sub(i,i)
    if c == '\n' then line=line+1; i=i+1
    elseif c == ' ' or c == '\t' or c == '\r' then i=i+1
    elseif c == '-' and source:sub(i+1,i+1) == '-' then
      local long = source:match('^%-%-%[(=*)%[', i)
      if long then
        local close = ']'..long..']'
        local finish = source:find(close, i+4, true)
        if not finish then i=n+1 else
          local chunk = source:sub(i,finish)
          local _,count = chunk:gsub('\n','\n')
          line = line + count
          i = finish + #close
        end
      else
        i = source:find('\n', i, true) or (n+1)
      end
    elseif c == '"' or c == "'" then
      local quote = c
      local startLine = line
      local parts = {}
      i = i + 1
      while i <= n do
        local ch = source:sub(i,i)
        if ch == '\\' then
          local nxt = source:sub(i+1,i+1)
          local map = {n='\n', r='\r', t='\t', ['\\']='\\', ["'"]="'", ['"']='"'}
          if map[nxt] then parts[#parts+1]=map[nxt]; i=i+2
          elseif nxt == 'x' then
            local hex = source:sub(i+2,i+3)
            if hex:match('^%x%x$') then parts[#parts+1]=string.char(tonumber(hex,16)); i=i+4
            else parts[#parts+1]='\\x'; i=i+2 end
          else parts[#parts+1]=nxt; i=i+2 end
        elseif ch == quote then
          i=i+1; break
        else
          if ch == '\n' then line=line+1 end
          parts[#parts+1]=ch; i=i+1
        end
      end
      push(table.concat(parts), 'string', startLine)
    elseif c:match('%d') then
      local startLine=line
      local num
      if source:sub(i,i+2):lower() == '0x' then
        local raw = source:match('^0[xX](%x+)', i)
        num = tonumber(raw,16)
        i = i + 2 + #raw
      else
        local raw = source:match('^%d+%.?%d*[eE]?[+-]?%d*', i)
        num = tonumber(raw)
        i = i + #raw
      end
      push(tostring(num or 0), 'number', startLine)
    elseif c:match('[%a_]') then
      local startLine=line
      local name = source:match('^[%a_][%w_]*', i)
      push(name, 'name', startLine)
      i = i + #name
    elseif c == '.' and source:sub(i,i+1) == '..' then
      push('..','op',line); i=i+2
    elseif c == '=' and source:sub(i,i+1) == '==' then
      push('==','op',line); i=i+2
    elseif c == '~' and source:sub(i,i+1) == '~=' then
      push('~=','op',line); i=i+2
    elseif c == '<' and source:sub(i,i+1) == '<=' then
      push('<=','op',line); i=i+2
    elseif c == '>' and source:sub(i,i+1) == '>=' then
      push('>=','op',line); i=i+2
    elseif c:match('[%+%-%*/%%%^#<>=]') then
      push(c,'op',line); i=i+1
    else
      push(c,'punct',line); i=i+1
    end
  end
  return tokens
end

local function new_scope(parent)
  return {parent=parent, names={}}
end

local function scope_find(scope,name)
  local cur=scope
  while cur do
    local hit=cur.names[name]
    if hit then return hit end
    cur=cur.parent
  end
  return nil
end

local function table_set(tbl,key,value,line)
  if type(key)~='string' and type(key)~='number' then return end
  for _,entry in ipairs(tbl.entries) do
    if entry.key==key then entry.value=value; entry.line=line or entry.line; return end
  end
  tbl.entries[#tbl.entries+1]={key=key,value=value,line=line}
end

local function table_get(tbl,key)
  for _,entry in ipairs(tbl.entries) do
    if entry.key==key then return entry.value,entry end
  end
end

local function normalize_pattern(value)
  if type(value)~='string' then return nil end
  local s = value:gsub('%s+',''):lower():gsub('[%?%*]','x')
  if #s < 4 or #s % 2 ~= 0 then return nil end
  if not s:match('^[0-9a-fx]+$') then return nil end
  local parts={}
  for i=1,#s,2 do
    parts[#parts+1]=s:sub(i,i+1)
  end
  return table.concat(parts,' ')
end

local Parser = {}
Parser.__index = Parser

local function new_parser(source, source_id, limits, helper_file)
  local token_ok, tokens = pcall(tokenize, source, limits)
  local p = setmetatable({
    source=source, source_id=source_id, limits=limits, helper_file=helper_file,
    tokens=token_ok and tokens or {}, token_error=not token_ok, pos=1,
    root=new_scope(nil), scope=nil,
    calls={}, refs={}, globals={}, unresolved={},
    candidates={}, edges={}, entries=0, specs=0
  }, Parser)
  p.scope=p.root
  return p
end

function Parser:peek(offset)
  local tok=self.tokens[self.pos+(offset or 0)]
  if not tok then return nil end
  return tok.value, tok.kind, tok.line
end

function Parser:advance()
  local tok=self.tokens[self.pos]
  self.pos=self.pos+1
  return tok
end

function Parser:at(value,offset)
  return self:peek(offset)==value
end

function Parser:node(kind,data)
  data=data or {}
  data.kind=kind
  if not data.line then
    local tok=self.tokens[self.pos-1]
    data.line=tok and tok.line or 1
  end
  data.source_script=self.source_id
  return data
end

function Parser:ref(name,line)
  local binding=scope_find(self.scope,name)
  self.refs[#self.refs+1]={name=name,line=line,
    scope=binding and 'local' or 'global', binding=binding}
  return binding
end

function Parser:resolve(node,depth)
  depth=depth or 0
  if not node or depth>self.limits.max_depth then return nil end
  if node.kind=='name' then
    if node.binding then return self:resolve(node.binding.value,depth+1) end
    local helper=self.globals[node.name]
    if helper then return helper end
    return node
  elseif node.kind=='member' then
    local base=self:resolve(node.base,depth+1)
    if base and base.kind=='table' then
      local value,entry=table_get(base,node.key)
      if value then
        local resolved=self:resolve(value,depth+1)
        if resolved then
          resolved.source_line=entry.line
          resolved.source_file=base.__helper_file or node.source_file
          if resolved.kind=='table' then
            resolved.__helper_file=resolved.__helper_file or base.__helper_file
          end
        end
        return resolved
      end
    end
    return node
  elseif node.kind=='index' then
    local base=self:resolve(node.base,depth+1)
    local key=self:resolve(node.key,depth+1)
    if base and base.kind=='table' and key and (key.kind=='string' or key.kind=='number') then
      local value,entry=table_get(base,key.value)
      if value then
        local resolved=self:resolve(value,depth+1)
        if resolved then
          resolved.source_line=entry.line
          resolved.source_file=base.__helper_file or node.source_file
          if resolved.kind=='table' then
            resolved.__helper_file=resolved.__helper_file or base.__helper_file
          end
        end
        return resolved
      end
    end
    return node
  elseif node.kind=='binary' then
    local left=self:resolve(node.left,depth+1)
    local right=self:resolve(node.right,depth+1)
    if node.op=='..' and left and right and left.kind=='string' and right.kind=='string' then
      return self:node('string',{value=left.value..right.value,line=node.line})
    end
    if node.op=='and' then
      return self:node('conditional',{condition=left,fallback=right,fallback_raw=node.right,
        line=node.line,deps=self:names_of(left)})
    end
    return node
  end
  return node
end

function Parser:names_of(node,out)
  out=out or {}
  if type(node)~='table' then return out end
  if node.kind=='name' then out[#out+1]=node.name
  elseif node.kind=='member' then self:names_of(node.base,out)
  elseif node.kind=='index' then self:names_of(node.base,out);self:names_of(node.key,out)
  elseif node.kind=='call' then
    for _,arg in ipairs(node.args or {}) do self:names_of(arg,out) end
  elseif node.kind=='binary' then self:names_of(node.left,out);self:names_of(node.right,out)
  elseif node.kind=='conditional' then self:names_of(node.condition,out);self:names_of(node.fallback,out)
  end
  return out
end

function Parser:render(node)
  if type(node)~='table' then return 'unknown' end
  if node.kind=='string' then return '"'..tostring(node.value):gsub('"','\\"')..'"' end
  if node.kind=='number' then return tostring(node.value) end
  if node.kind=='boolean' then return node.value and 'true' or 'false' end
  if node.kind=='nil' then return 'nil' end
  if node.kind=='name' then return tostring(node.name) end
  if node.kind=='member' then return self:render(node.base)..'.'..tostring(node.key) end
  if node.kind=='index' then return self:render(node.base)..'['..self:render(node.key)..']' end
  if node.kind=='call' then
    local args={}
    for _,arg in ipairs(node.args or {}) do args[#args+1]=self:render(arg) end
    return self:render(node.callee)..'('..table.concat(args,', ')..')'
  end
  if node.kind=='unary' then return tostring(node.op)..self:render(node.operand) end
  if node.kind=='binary' then
    local left,right=self:render(node.left),self:render(node.right)
    if node.op=='and' or node.op=='or' then
      return left..' '..node.op..' '..right
    end
    return '('..left..' '..tostring(node.op)..' '..right..')'
  end
  if node.kind=='conditional' then
    return self:render(node.condition)..' and '..self:render(node.fallback)
  end
  return 'unknown'
end

function Parser:parse_table()
  local line=self.tokens[self.pos].line
  self.pos=self.pos+1
  local tbl=self:node('table',{entries={},line=line})
  local array_index=1
  while self:peek() and self:peek()~='}' do
    if #tbl.entries>=self.limits.max_entries then
      self.unresolved[#self.unresolved+1]={code='TABLE_LIMIT',line=line,source_script=self.source_id}
      break
    end
    local key
    if self:at('[') then
      self.pos=self.pos+1
      local k=self:parse_expr()
      if not self:at(']') then break end
      self.pos=self.pos+1
      if not self:at('=') then break end
      self.pos=self.pos+1
      key=self:resolve(k)
    elseif self.tokens[self.pos] and self.tokens[self.pos].kind=='name'
        and self.tokens[self.pos+1] and self.tokens[self.pos+1].value=='=' then
      local name=self:advance().value
      self.pos=self.pos+1
      key=self:node('string',{value=name,line=line})
    else
      key=self:node('number',{value=array_index,line=line})
      array_index=array_index+1
    end
    local value=self:parse_expr()
    if key and (key.kind=='string' or key.kind=='number') then
      table_set(tbl,key.value,value,value and value.line or line)
    end
    if self:at(',') or self:at(';') then self.pos=self.pos+1
    elseif not self:at('}') then
      while self:peek() and self:peek()~='}' and self:peek()~=',' do self.pos=self.pos+1 end
      if self:at(',') then self.pos=self.pos+1 end
    end
  end
  if self:at('}') then self.pos=self.pos+1 end
  return tbl
end

function Parser:parse_primary()
  local value,kind,ln=self:peek()
  if not value then return self:node('unknown',{line=1}) end
  local line=ln
  if kind=='string' then self.pos=self.pos+1; return self:node('string',{value=value,line=line}) end
  if kind=='number' then self.pos=self.pos+1; return self:node('number',{value=tonumber(value) or value,line=line}) end
  if kind=='name' then
    if value=='true' then self.pos=self.pos+1; return self:node('boolean',{value=true,line=line}) end
    if value=='false' then self.pos=self.pos+1; return self:node('boolean',{value=false,line=line}) end
    if value=='nil' then self.pos=self.pos+1; return self:node('nil',{line=line}) end
    if value=='function' then
      self.pos=self.pos+1
      self:skip_function_body()
      return self:node('unknown',{line=line})
    end
    self.pos=self.pos+1
    local binding=self:ref(value,ln)
    local node=self:node('name',{name=value,binding=binding,line=line})
    while self:at('.') do
      self.pos=self.pos+1
      local field=self:peek()
      if not field then break end
      self.pos=self.pos+1
      node=self:node('member',{base=node,key=field,line=line,source_file=self.helper_file})
    end
    while self:at('[') do
      self.pos=self.pos+1
      local key=self:parse_expr()
      if not self:at(']') then break end
      self.pos=self.pos+1
      node=self:node('index',{base=node,key=key,line=line,source_file=self.helper_file})
    end
    return node
  end
  if value=='{' then return self:parse_table() end
  if value=='(' then
    self.pos=self.pos+1
    local inner=self:parse_expr()
    if self:at(')') then self.pos=self.pos+1 end
    return inner
  end
  if value=='not' or value=='-' or value=='#' then
    self.pos=self.pos+1
    local operand=self:parse_expr(9)
    return self:node('unary',{op=value,operand=operand,line=line})
  end
  self.pos=self.pos+1
  return self:node('unknown',{line=line})
end

function Parser:path_of(node)
  if node.kind=='name' then return node.name end
  if node.kind=='member' then
    local base=self:path_of(node.base)
    return base and (base..'.'..tostring(node.key)) or nil
  end
  if node.kind=='index' then
    local base=self:path_of(node.base)
    local key=self:resolve(node.key)
    if base and key and (key.kind=='string' or key.kind=='number') then
      return base..'['..tostring(key.value)..']'
    end
  end
  return nil
end

function Parser:parse_postfix(node)
  while self:at('(') do
    self.pos=self.pos+1
    local args={}
    while self:peek() and self:peek()~=')' do
      args[#args+1]=self:parse_expr()
      if self:at(',') then self.pos=self.pos+1 else break end
    end
    if self:at(')') then self.pos=self.pos+1 end
    local callee=self:path_of(node)
    node=self:node('call',{callee=node,callee_path=callee,args=args,line=node.line})
    self.calls[#self.calls+1]=node
  end
  return node
end

local PRECEDENCE={['or']=1,['and']=2,['==']=3,['~=']=3,['<']=3,['>']=3,['<=']=3,['>=']=3,
  ['..']=4,['+']=5,['-']=5,['*']=6,['/']=6,['%']=6,['^']=7}

function Parser:parse_expr(min_prec)
  min_prec=min_prec or 0
  local left=self:parse_primary()
  left=self:parse_postfix(left)
  while true do
    local op=self:peek()
    local prec=op and PRECEDENCE[op]
    if not prec or prec<min_prec then break end
    local op_line=self.tokens[self.pos].line
    self.pos=self.pos+1
    local right=self:parse_expr(prec+1)
    left=self:node('binary',{op=op,left=left,right=right,line=op_line})
  end
  return left
end

function Parser:skip_function_body()
  if self:at('(') then
    self.pos=self.pos+1
    while self:peek() and self:peek()~=')' do self.pos=self.pos+1 end
    if self:at(')') then self.pos=self.pos+1 end
  end
  local depth=1
  while self:peek() do
    local v=self:advance().value
    if v=='function' or v=='if' or v=='for' or v=='while' or v=='do' then depth=depth+1
    elseif v=='end' then depth=depth-1; if depth==0 then return end end
  end
end

function Parser:assign(target,value)
  if target.kind=='name' then
    if target.binding then target.binding.value=value
    else self.globals[target.name]=value end
  elseif target.kind=='member' then
    local base=self:resolve(target.base)
    if base and base.kind=='table' then table_set(base,target.key,value,target.line) end
  elseif target.kind=='index' then
    local base=self:resolve(target.base)
    local key=self:resolve(target.key)
    if base and base.kind=='table' and key and (key.kind=='string' or key.kind=='number') then
      table_set(base,key.value,value,target.line)
    end
  end
end

function Parser:parse_statement()
  local v=self:peek()
  if not v then return end
  if v==';' then self.pos=self.pos+1; return end
  if v=='local' then
    self.pos=self.pos+1
    if self:at('function') then
      self.pos=self.pos+1
      local name=self:advance().value
      if self:at('(') then
        self.pos=self.pos+1
        while self:peek() and self:peek()~=')' do self.pos=self.pos+1 end
        if self:at(')') then self.pos=self.pos+1 end
      end
      local outer=self.scope
      self.scope=new_scope(outer)
      self:parse_block('end')
      self.scope=outer
      if self:at('end') then self.pos=self.pos+1 end
      outer.names[name]={value=self:node('unknown',{line=1})}
      return
    end
    local names={}
    while self:peek() and self:peek()~='=' do
      local name=self:advance().value
      names[#names+1]=name
      if self:at(',') then self.pos=self.pos+1 else break end
    end
    local values={}
    if self:at('=') then
      self.pos=self.pos+1
      values[#values+1]=self:parse_expr()
      while self:at(',') do self.pos=self.pos+1; values[#values+1]=self:parse_expr() end
    end
    for i,name in ipairs(names) do
      local value=values[i] or self:node('nil',{})
      self.scope.names[name]={value=value,line=value.line}
    end
    return
  elseif v=='function' then
    self.pos=self.pos+1
    while self:peek() and not self:at('(') do self.pos=self.pos+1 end
    self:skip_function_body()
    return
  elseif v=='return' then
    self.pos=self.pos+1
    if self:peek() and not self:at('end') then self:parse_expr() end
    while self:peek() and not self:at('end') and not self:at(';') do self.pos=self.pos+1 end
    return
  elseif v=='if' then
    self.pos=self.pos+1; self:parse_expr()
    if self:at('then') then self.pos=self.pos+1 end
    local outer=self.scope; self.scope=new_scope(outer)
    self:parse_block('end')
    self.scope=outer
    if self:at('end') then self.pos=self.pos+1 end
    return
  elseif v=='do' then
    self.pos=self.pos+1
    local outer=self.scope; self.scope=new_scope(outer)
    self:parse_block('end')
    self.scope=outer
    if self:at('end') then self.pos=self.pos+1 end
    return
  elseif v=='for' or v=='while' then
    while self:peek() and not self:at('do') do self.pos=self.pos+1 end
    if self:at('do') then self.pos=self.pos+1 end
    local outer=self.scope; self.scope=new_scope(outer)
    self:parse_block('end')
    self.scope=outer
    if self:at('end') then self.pos=self.pos+1 end
    return
  end
  if v=='end' or v=='else' or v=='elseif' then return end

  local first=self:parse_expr()
  if self:at('=') or self:at(',') then
    local targets={first}
    while self:at(',') do self.pos=self.pos+1; targets[#targets+1]=self:parse_expr() end
    if self:at('=') then self.pos=self.pos+1 end
    local values={}
    values[#values+1]=self:parse_expr()
    while self:at(',') do self.pos=self.pos+1; values[#values+1]=self:parse_expr() end
    for i,target in ipairs(targets) do self:assign(target,values[i] or self:node('nil',{})) end
  end
end

function Parser:parse_block(stop)
  while self:peek() and self:peek()~=stop do
    local before=self.pos
    self:parse_statement()
    if self.pos==before then
      self.pos=self.pos+1
      if self.pos>#self.tokens then break end
    end
  end
end

-- Strip AA markers while preserving line numbers.
local function prepare_text(text)
  local out={}
  for line in ((text or '')..'\n'):gmatch('(.-)\n') do
    local s=trim(line)
    if s=='{$lua}' or s=='{$asm}' or s=='[ENABLE]' or s=='[DISABLE]' then
      out[#out+1]=''
    else
      out[#out+1]=line
    end
  end
  return table.concat(out,'\n')
end

local function helper_globals(options, limits)
  local globals={}
  local helpers=options.helpers or {}
  local function add(helper)
    if type(helper)~='table' or type(helper.text)~='string' then return end
    local p=new_parser(helper.text,helper.name or 'helper',limits,helper.file)
    local ok=pcall(function() p:parse_block(nil) end)
    if not ok then return end
    local alias=helper.alias
    local value
    if alias then
      local hit=p.root.names[alias]
      value=hit and p:resolve(hit.value)
    end
    if not value or value.kind~='table' then
      for _,binding in pairs(p.root.names) do
        local candidate=p:resolve(binding.value)
        if candidate and candidate.kind=='table' then value=candidate;break end
      end
    end
    if value and value.kind=='table' then
      value.__helper_file=helper.file or (helper.name and (helper.name..'.lua')) or nil
      globals[helper.name]=value
    end
  end
  if #helpers>0 then
    for _,helper in ipairs(helpers) do add(helper) end
  else
    for name,helper in pairs(helpers) do
      if type(helper)=='string' then add({name=name,text=helper})
      elseif type(helper)=='table' then helper.name=helper.name or name;add(helper) end
    end
  end
  return globals
end

local function edge(ctx,relation,from,to,provenance,line,script,extra)
  if #ctx.edges>=ctx.limits.max_edges then
    if not ctx.edge_limit_reported then
      ctx.edge_limit_reported=true
      ctx.unresolved[#ctx.unresolved+1]={code='EDGE_LIMIT',line=line,
        source_script=script or ctx.source_id}
    end
    ctx.limit=true
    return
  end
  local f,t=tostring(from),tostring(to)
  local key=table.concat({relation,f,t,script or ctx.source_id or '',
    tostring(line or ''),provenance or 'unknown'},'|')
  ctx.edge_keys=ctx.edge_keys or {}
  if ctx.edge_keys[key] then return end
  ctx.edge_keys[key]=true
  local e={relation=relation,from=f,to=t,
    provenance=provenance or 'unknown',source_script=script or ctx.source_id,
    source_line=line,status='linked',confidence='high'}
  if extra then for k,v in pairs(extra) do e[k]=v end end
  ctx.edges[#ctx.edges+1]=e
end

local function add_candidate(ctx,row,consumer,key)
  if #ctx.candidates>=ctx.limits.max_candidates then
    ctx.limit=true
    if not ctx.candidate_limit_reported then
      ctx.candidate_limit_reported=true
      ctx.unresolved[#ctx.unresolved+1]={code='CANDIDATE_LIMIT',
        line=row.line,source_script=ctx.source_id}
    end
    return
  end
  local entries=row.entries or {}
  local first=entries[1] and ctx.parser:resolve(entries[1].value) or nil
  local second_raw=entries[2] and entries[2].value or nil
  local second=second_raw and ctx.parser:resolve(second_raw) or nil
  local symbol=nil
  local kind='unknown'
  local pattern=nil
  local derived=nil
  local conditional=nil
  local status='unresolved'
  if first and first.kind=='string' then symbol=first.value end
  if first and first.kind=='conditional' then
    kind='conditional_pattern'
    conditional=first
    for _,name in ipairs(first.deps or {}) do
      ctx.unresolved[#ctx.unresolved+1]={code='CONDITIONAL_DEPENDENCY',name=name,
        line=first.line,source_script=ctx.source_id}
    end
  elseif symbol and second and second.kind=='string' and
      not (second_raw and (second_raw.kind=='member' or second_raw.kind=='index')) then
    kind='literal_pattern'
    pattern=second.value
    status='candidate'
  elseif symbol and second_raw and (second_raw.kind=='member' or second_raw.kind=='index') then
    kind='derived_pattern'
    local resolved=ctx.parser:resolve(second_raw)
    if resolved and resolved.kind=='string' then
      pattern=resolved.value
      status='candidate'
      derived={path=ctx.parser:path_of(second_raw),source_file=resolved.source_file,
        source_line=resolved.source_line}
      edge(ctx,'derives_from','candidate',ctx.parser:path_of(second_raw) or 'helper',
        'lua_dynamic',second.line,ctx.source_id)
    else
      ctx.unresolved[#ctx.unresolved+1]={code='UNRESOLVED_DERIVED',
        name=ctx.parser:path_of(second_raw) or '?',line=second_raw.line,source_script=ctx.source_id}
    end
  elseif symbol then
    kind='symbol_only'
    status='not_applicable'
  else
    status='unresolved'
  end
  local normalized=normalize_pattern(pattern)
  local id=string.format('dyn-%s-%d-%03d',ctx.source_id,row.line or 0,#ctx.candidates+1)
  local candidate={id=id,pattern=pattern,kind=kind,symbol=symbol or U.null,
    source_script=ctx.source_id,source_line=row.line,consumer=consumer,
    key=key or U.null,status=status,runtime_validated=false,
    provenance=U.array({
      {kind='lua_literal',source_script=ctx.source_id,line=first and first.line or row.line},
      {kind='wrapper',source_script=ctx.source_id,line=row.line,detail=consumer}
    })}
  if normalized then
    candidate.pattern_length=#normalized:gsub('%s','')/2
  end
  if derived then candidate.derivation=derived end
  if conditional then
    local deps,seen=U.array(),{}
    for _,name in ipairs(conditional.deps or {}) do
      if not seen[name] then seen[name]=true;deps[#deps+1]=name end
    end
    candidate.condition={
      kind='conditional_expression',
      text=ctx.parser:render(conditional.condition)..' and '..
        ctx.parser:render(conditional.fallback_raw or conditional.fallback),
      dependencies=deps,
      resolution='unknown',
      fallback=ctx.parser:render(conditional.fallback_raw or conditional.fallback)
    }
    candidate.dependencies=deps
  end
  ctx.candidates[#ctx.candidates+1]=candidate
  if kind=='literal_pattern' then
    ctx.counts.literal=ctx.counts.literal+1
    ctx.counts.candidates=ctx.counts.candidates+1
  elseif kind=='derived_pattern' then
    ctx.counts.derived=ctx.counts.derived+1
    ctx.counts.candidates=ctx.counts.candidates+1
  elseif kind=='conditional_pattern' then
    ctx.counts.conditional=ctx.counts.conditional+1
  end
  if kind=='symbol_only' or kind=='conditional_pattern' then
    ctx.counts.symbol_only=ctx.counts.symbol_only+1
  end
  if symbol then
    ctx.symbols[symbol]=(ctx.symbols[symbol] or 0)+1
    edge(ctx,'provides',consumer,symbol,'wrapper',row.line,ctx.source_id)
  end
  if normalized then
    ctx.patterns[normalized]=true
    if kind=='literal_pattern' then ctx.literal_patterns[normalized]=true end
    edge(ctx,'constructs',consumer,'aobScanRegion','wrapper',row.line,ctx.source_id)
  end
end

local function spec_rows(ctx,table_node,consumer,key,depth)
  if depth>ctx.limits.max_wrapper_depth then
    ctx.unresolved[#ctx.unresolved+1]={code='WRAPPER_DEPTH_LIMIT',
      line=table_node.line,source_script=ctx.source_id}
    return
  end
  for _,entry in ipairs(table_node.entries or {}) do
    local row=ctx.parser:resolve(entry.value)
    if row and row.kind=='table' then
      add_candidate(ctx,row,consumer,key)
    else
      ctx.unresolved[#ctx.unresolved+1]={code='UNRESOLVED_SPEC',
        line=entry.line,source_script=ctx.source_id}
    end
  end
end

local function process_call(ctx,call)
  local path=call.callee_path and call.callee_path:lower() or ''
  if CALLBACK_CALLEES[path] then
    for _,arg in ipairs(call.args or {}) do
      local name
      if arg.kind=='name' then name=arg.name
      elseif arg.kind=='member' or arg.kind=='index' then name=ctx.parser:path_of(arg) end
      edge(ctx,'registers',name or 'anonymous_callback',call.callee_path,
        'callback',call.line,ctx.source_id,{callback=true})
    end
    return
  end
  local contract=CONTRACTS[path]
  if not contract then return end
  local consumer=call.callee_path
  if contract.kind=='table_sets' then
    for _,arg in ipairs(call.args or {}) do
      local value=ctx.parser:resolve(arg)
      if value and value.kind=='table' then
        ctx.entries=ctx.entries+#value.entries
        edge(ctx,'passes_to',arg.kind=='name' and arg.name or 'table',consumer,
          'wrapper',call.line,ctx.source_id)
        for _,entry in ipairs(value.entries) do
          local list=ctx.parser:resolve(entry.value)
          if list and list.kind=='table' then
            spec_rows(ctx,list,consumer,tostring(entry.key),1)
          else
            ctx.unresolved[#ctx.unresolved+1]={code='UNRESOLVED_TABLE_SET',
              line=entry.line,source_script=ctx.source_id}
          end
        end
      else
        ctx.unresolved[#ctx.unresolved+1]={code='UNRESOLVED_WRAPPER_ARGUMENT',
          line=call.line,source_script=ctx.source_id}
      end
    end
    if contract.forwards_to then
      edge(ctx,'calls',consumer,contract.forwards_to,'wrapper',call.line,ctx.source_id)
      edge(ctx,'constructs',contract.forwards_to,contract.constructs or 'aobScanRegion',
        'wrapper',call.line,ctx.source_id)
    end
  else
    for _,arg in ipairs(call.args or {}) do
      local row=ctx.parser:resolve(arg)
      if row and row.kind=='table' then add_candidate(ctx,row,consumer,nil)
      else ctx.unresolved[#ctx.unresolved+1]={code='UNRESOLVED_SPEC',
        line=call.line,source_script=ctx.source_id} end
    end
  end
end

local function loader_edges(ctx,text,script_id)
  if type(text)~='string' then return end
  for name in text:gmatch("findTableFile%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
    edge(ctx,'includes',script_id,name,'include',nil,script_id)
  end
  for name in text:gmatch("include%s*%(%s*['\"]([%a_][%w_]*)['\"]%s*%)") do
    edge(ctx,'includes',script_id,name..'.lua','include',nil,script_id)
  end
  for name in text:gmatch('_G%s*%.%s*([%a_][%w_]*)%s*=') do
    ctx.providers[name]=true
    edge(ctx,'provides',script_id,name,'external_helper',nil,script_id)
  end
  for name in text:gmatch("_G%s*%[%s*['\"]([%a_][%w_]*)['\"]%s*%]%s*=") do
    ctx.providers[name]=true
    edge(ctx,'provides',script_id,name,'external_helper',nil,script_id)
  end
end

function M.analyze(sources, options)
  options=options or {}
  local limits={}
  for k,v in pairs(M.DEFAULT_LIMITS) do limits[k]=v end
  for k,v in pairs(options.limits or {}) do limits[k]=v end
  local ctx={limits=limits,source_id='dynamic',edges={},candidates={},entries=0,
    unresolved={},deps={},counts={entries=0,specs=0,literal=0,derived=0,
      conditional=0,symbol_only=0,candidates=0},symbols={},patterns={},providers={},
    literal_patterns={},limit=false}
  local globals=helper_globals(options,limits)

  for _,source in ipairs(sources or {}) do
    local text=prepare_text(source.text or '')
    local p=new_parser(text,source.script_id or 'source',limits)
    p.globals=globals
    if p.token_error then
      ctx.unresolved[#ctx.unresolved+1]={code='PARSE_LIMIT',message='token limit',
        line=nil,source_script=source.script_id}
      ctx.limit=true
    end
    local ok,err=pcall(function() p:parse_block(nil) end)
    if not ok then
      ctx.unresolved[#ctx.unresolved+1]={code='PARSE_LIMIT',message=tostring(err),
        line=nil,source_script=source.script_id}
      ctx.limit=true
    end
    for _,entry in ipairs(p.unresolved or {}) do
      ctx.unresolved[#ctx.unresolved+1]=entry
      if type(entry.code)=='string' and entry.code:match('_LIMIT$') then ctx.limit=true end
    end
    for name,binding in pairs(p.root.names) do
      local value=p:resolve(binding.value)
      if value and value.kind=='table' and not globals[name] then globals[name]=value end
    end
    ctx.source_id=source.script_id or 'source'
    ctx.parser=p
    for _,call in ipairs(p.calls) do process_call(ctx,call) end
    for _,ref in ipairs(p.refs) do
      local provenance
      if ref.scope=='local' then provenance='lua_local'
      elseif globals[ref.name] then provenance='external_helper'
      elseif ref.name=='md5memory' or ref.name=='process' or ref.name=='memrec' then provenance='runtime'
      else provenance='unknown' end
      ctx.deps[#ctx.deps+1]={name=ref.name,line=ref.line,scope=ref.scope,
        provenance=provenance,source_script=ctx.source_id,
        status=ref.scope=='local' and 'local' or 'unresolved'}
      if ref.scope=='global' then
        edge(ctx,'requires',ctx.source_id,ref.name,provenance,ref.line,ctx.source_id)
      end
    end
  end
  if options.loader then loader_edges(ctx,options.loader,options.loader_script_id or 'loader') end

  local counts=ctx.counts
  counts.entries=ctx.entries
  counts.literal_unique=0
  for _ in pairs(ctx.literal_patterns) do counts.literal_unique=counts.literal_unique+1 end
  counts.unique_symbols=0
  for _ in pairs(ctx.symbols) do counts.unique_symbols=counts.unique_symbols+1 end
  counts.symbol_only_pure=counts.symbol_only-counts.conditional
  counts.specs=#ctx.candidates
  counts.runtime_validated=0

  table.sort(ctx.candidates,function(a,b)
    if a.source_script~=b.source_script then return a.source_script<b.source_script end
    if a.source_line~=b.source_line then return a.source_line<b.source_line end
    return a.id<b.id
  end)
  table.sort(ctx.edges,function(a,b)
    if a.source_script~=b.source_script then return a.source_script<b.source_script end
    if (a.source_line or 0)~=(b.source_line or 0) then return (a.source_line or 0)<(b.source_line or 0) end
    if a.relation~=b.relation then return a.relation<b.relation end
    if a.from~=b.from then return tostring(a.from)<tostring(b.from) end
    return tostring(a.to)<tostring(b.to)
  end)
  table.sort(ctx.unresolved,function(a,b)
    if (a.source_script or '')~=(b.source_script or '') then return (a.source_script or '')<(b.source_script or '') end
    return (a.line or 0)<(b.line or 0)
  end)
  table.sort(ctx.deps,function(a,b)
    if a.source_script~=b.source_script then return a.source_script<b.source_script end
    if a.line~=b.line then return a.line<b.line end
    return a.name<b.name
  end)

  local patterns=U.array()
  for _,candidate in ipairs(ctx.candidates) do patterns[#patterns+1]=candidate end
  local edges=U.array()
  for _,e in ipairs(ctx.edges) do edges[#edges+1]=e end
  local unresolved=U.array()
  for _,u in ipairs(ctx.unresolved) do unresolved[#unresolved+1]=u end
  local deps=U.array()
  for _,d in ipairs(ctx.deps) do deps[#deps+1]=d end
  local providers=U.array()
  for name in pairs(ctx.providers) do providers[#providers+1]=name end
  table.sort(providers)
  local nodes=U.array()
  for name in pairs(ctx.providers) do
    nodes[#nodes+1]={id='provider:'..name,kind='helper',name=name,status='linked'}
  end
  for symbol in pairs(ctx.symbols) do
    nodes[#nodes+1]={id='symbol:'..symbol,kind='symbol',name=symbol,status='discovered'}
  end
  table.sort(nodes,function(a,b) return a.id<b.id end)

  return {
    version='0.1',
    limits=limits,
    patterns=patterns,
    edges=edges,
    nodes=nodes,
    dependencies=deps,
    providers=providers,
    counts=counts,
    unresolved=unresolved,
    status=ctx.limit and 'limit_reached' or 'complete'
  }
end

-- Merge embedded Lua blocks of the same parent script into a line-preserving
-- source unit. AA scripts are ignored; only captured Lua text is analyzed.
function M.sources_from_scripts(scripts)
  local groups = {}
  for _,script in ipairs(scripts or {}) do
    if script.language == 'Lua' and type(script.text) == 'string' then
      local key = script.parent_script_id or script.id
      local group = groups[key]
      if not group then
        group = {script_id=key, blocks={}}
        groups[key] = group
      end
      group.blocks[#group.blocks+1] = {text=script.text, line=script.line or 1}
    end
  end
  local sources = {}
  for key,group in pairs(groups) do
    table.sort(group.blocks, function(a,b) return a.line < b.line end)
    local maxline = 1
    local split = {}
    for _,block in ipairs(group.blocks) do
      local lines = {}
      for line in (block.text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
      split[#split+1] = {start=block.line, lines=lines}
      maxline = math.max(maxline, block.line + #lines - 1)
    end
    local out = {}
    for i=1,maxline do out[i] = '' end
    for _,block in ipairs(split) do
      for offset,line in ipairs(block.lines) do
        local index = block.start + offset - 1
        if index <= maxline then out[index] = line end
      end
    end
    sources[#sources+1] = {script_id=key, text=table.concat(out, '\n')}
  end
  table.sort(sources, function(a,b) return a.script_id < b.script_id end)
  return sources
end


return M
