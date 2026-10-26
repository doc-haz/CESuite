-- Bounded JSON data decoder. No code execution: snapshots are data only.
local U=require('util')
local M={}

local function fail(code,pos,message)
  error({json=true,code=code,pos=pos,message=message},0)
end

function M.decode(text,options)
  options=options or {}
  if type(text)~='string' then return nil,{code='invalid_json',message='JSON text required'} end
  local max=options.max_bytes or (8*1024*1024)
  if #text>max then return nil,{code='snapshot_too_large',message='JSON exceeds size limit'} end
  local max_depth=options.max_depth or 64
  local i=1
  local n=#text

  local function skip()
    while i<=n do
      local c=text:sub(i,i)
      if c==' ' or c=='\t' or c=='\n' or c=='\r' then i=i+1 else break end
    end
  end
  local function need()
    if i>n then fail('truncated_file',i,'unexpected end of JSON') end
  end
  local function expect(c)
    need()
    if text:sub(i,i)~=c then fail('invalid_json',i,'expected '..c) end
    i=i+1
  end
  local function hex4()
    need()
    local h=text:sub(i,i+3)
    if #h<4 or not h:match('^[0-9a-fA-F]+$') then fail('invalid_json',i,'invalid unicode escape') end
    i=i+4
    return tonumber(h,16)
  end
  local function utf8_char(cp)
    local ok,s=pcall(utf8.char,cp)
    if not ok then fail('invalid_json',i,'invalid unicode codepoint') end
    return s
  end
  local function parse_string()
    expect('"')
    local parts={}
    while true do
      need()
      local c=text:sub(i,i)
      if c=='"' then i=i+1;return table.concat(parts) end
      if c=='\\' then
        i=i+1;need()
        local e=text:sub(i,i)
        if e=='"' or e=='\\' or e=='/' then parts[#parts+1]=e;i=i+1
        elseif e=='b' then parts[#parts+1]='\b';i=i+1
        elseif e=='f' then parts[#parts+1]='\f';i=i+1
        elseif e=='n' then parts[#parts+1]='\n';i=i+1
        elseif e=='r' then parts[#parts+1]='\r';i=i+1
        elseif e=='t' then parts[#parts+1]='\t';i=i+1
        elseif e=='u' then
          i=i+1
          local cp=hex4()
          if cp>=0xD800 and cp<=0xDBFF then
            if text:sub(i,i)~='\\' or text:sub(i+1,i+1)~='u' then fail('invalid_json',i,'unpaired surrogate') end
            i=i+2
            local low=hex4()
            if low<0xDC00 or low>0xDFFF then fail('invalid_json',i,'invalid low surrogate') end
            cp=0x10000+((cp-0xD800)<<10)+(low-0xDC00)
          elseif cp>=0xDC00 and cp<=0xDFFF then
            fail('invalid_json',i,'unpaired surrogate')
          end
          parts[#parts+1]=utf8_char(cp)
        else fail('invalid_json',i,'invalid escape') end
      elseif c:byte()<0x20 then
        fail('invalid_json',i,'control character in string')
      else
        parts[#parts+1]=c;i=i+1
      end
    end
  end
  local function parse_number()
    need()
    local start=i
    if text:sub(i,i)=='-' then i=i+1 end
    need()
    if text:sub(i,i)=='0' then i=i+1
    elseif text:sub(i,i):match('[1-9]') then
      while i<=n and text:sub(i,i):match('%d') do i=i+1 end
    else fail('invalid_json',i,'invalid number') end
    if text:sub(i,i)=='.' then
      i=i+1;need()
      if not text:sub(i,i):match('%d') then fail('invalid_json',i,'invalid fraction') end
      while i<=n and text:sub(i,i):match('%d') do i=i+1 end
    end
    local e=text:sub(i,i)
    if e=='e' or e=='E' then
      i=i+1;need()
      local sign=text:sub(i,i)
      if sign=='+' or sign=='-' then i=i+1;need() end
      if not text:sub(i,i):match('%d') then fail('invalid_json',i,'invalid exponent') end
      while i<=n and text:sub(i,i):match('%d') do i=i+1 end
    end
    local value=tonumber(text:sub(start,i-1))
    if value==nil or value~=value or math.abs(value)==math.huge then fail('invalid_json',start,'non-finite number') end
    return value
  end
  local parse_value
  local function parse_array(depth)
    expect('[');skip()
    local out=U.array()
    if text:sub(i,i)==']' then i=i+1;return out end
    while true do
      out[#out+1]=parse_value(depth+1)
      skip();need()
      local c=text:sub(i,i)
      if c==']' then i=i+1;return out end
      if c~=',' then fail('invalid_json',i,'expected , or ]') end
      i=i+1;skip()
    end
  end
  local function parse_object(depth)
    expect('{');skip()
    local out={}
    if text:sub(i,i)=='}' then i=i+1;return out end
    while true do
      if text:sub(i,i)~='"' then fail('invalid_json',i,'object key must be a string') end
      local key=parse_string();skip();expect(':');skip()
      out[key]=parse_value(depth+1);skip();need()
      local c=text:sub(i,i)
      if c=='}' then i=i+1;return out end
      if c~=',' then fail('invalid_json',i,'expected , or }') end
      i=i+1;skip()
    end
  end
  function parse_value(depth)
    if depth>max_depth then fail('invalid_json',i,'depth limit') end
    skip();need()
    local c=text:sub(i,i)
    if c=='{' then return parse_object(depth) end
    if c=='[' then return parse_array(depth) end
    if c=='"' then return parse_string() end
    if c=='-' or c:match('%d') then return parse_number() end
    if text:sub(i,i+3)=='true' then i=i+4;return true end
    if text:sub(i,i+4)=='false' then i=i+5;return false end
    if text:sub(i,i+3)=='null' then i=i+4;return U.null end
    fail('invalid_json',i,'unexpected token')
  end
  local ok,value=pcall(function()
    skip()
    local v=parse_value(0)
    skip()
    if i<=n then fail('invalid_json',i,'trailing data') end
    return v
  end)
  if ok then return value end
  return nil,value
end

return M
