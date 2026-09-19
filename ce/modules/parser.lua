-- Conservative lexical AA/Lua inventory.
-- Never compiles AA or evaluates Lua/expressions.
local U=require('util')
local LuaNames=require('luanames')
local M={}

function M.arguments(s)
  local out,start,depth,quote=U.array(),1,0,nil

  for i=1,#s do
    local c=s:sub(i,i)

    if quote then
      if c==quote then
        quote=nil
      end
    elseif c=='"' or c=="'" then
      quote=c
    elseif c=='(' then
      depth=depth+1
    elseif c==')' then
      depth=depth-1
    elseif c==',' and depth==0 then
      out[#out+1]=U.trim(s:sub(start,i-1))
      start=i+1
    end
  end

  out[#out+1]=U.trim(s:sub(start))
  return out
end

-- Mask Lua comments/literals without evaluating them, retaining columns/newlines.
-- State spans lines, including escaped newlines and arbitrary long-bracket levels.
local function maskLua(raw,state)
  local out,i={},1
  while i<=#raw do
    local c,pair=raw:sub(i,i),raw:sub(i,i+1)
    if state.close then
      if raw:sub(i,i+#state.close-1)==state.close then
        out[#out+1]=string.rep(' ',#state.close);i=i+#state.close;state.close=nil
      else out[#out+1]=' ';i=i+1 end
    elseif state.quote then
      out[#out+1]=' '
      if c=='\\' then out[#out+1]=' ';i=i+2
      else if c==state.quote then state.quote=nil end;i=i+1 end
    elseif pair=='--' then
      local level=raw:sub(i+2):match('^%[(=*)%[')
      if level then
        state.close=']'..level..']';out[#out+1]=string.rep(' ',4+#level);i=i+4+#level
      else out[#out+1]=string.rep(' ',#raw-i+1);break end
    elseif c=='"' or c=="'" then
      state.quote=c;out[#out+1]='@';i=i+1
    else
      local level=raw:sub(i):match('^%[(=*)%[')
      if level then
        state.close=']'..level..']';out[#out+1]='@'..string.rep(' ',1+#level);i=i+2+#level
      else out[#out+1]=c;i=i+1 end
    end
  end
  return table.concat(out)
end

local function luaDependencies(text,script,report,startLine,section)
  local tokens,state,line={}, {},startLine
  for raw in (text..'\n'):gmatch('(.-)\n') do
    local clean=maskLua(raw,state)
    local i=1
    while i<=#clean do
      local rest=clean:sub(i)
      local word=rest:match('^[A-Za-z_][A-Za-z0-9_]*')
      -- Consume numerals as whole tokens, not fragments such as xFF or e10.
      local number=rest:match('^0[xX]%x+%.?%x*[pP][+-]?%d+')
        or rest:match('^0[xX]%x*%.%x+[pP][+-]?%d+')
        or rest:match('^0[xX]%x+%.?%x*')
        or rest:match('^0[xX]%x*%.%x+')
        or rest:match('^%d+%.?%d*[eE][+-]?%d+')
        or rest:match('^%.%d+[eE][+-]?%d+')
        or rest:match('^%d+%.?%d*') or rest:match('^%.%d+')
      local pair=clean:sub(i,i+1)
      local value=word or number or (rest:sub(1,3)=='...' and '...')
        or ((pair=='==' or pair=='~=' or pair=='<=' or pair=='>=' or pair=='..' or pair=='::') and pair)
        or clean:sub(i,i)
      if not value:match('^%s$') then tokens[#tokens+1]={value=value,line=line} end
      i=i+#value
    end
    line=line+1
  end
  local function value(i) return tokens[i] and tokens[i].value or '' end
  local function identifier(v)
    return v:match('^[A-Za-z_][A-Za-z0-9_]*$') and not LuaNames.keywords[v]
  end
  -- Suppress explicit local/parameter/loop names throughout this chunk. This
  -- deliberately under-reports shadowed names instead of guessing Lua scope.
  local locals={}
  for i,t in ipairs(tokens) do
    if t.value=='local' or t.value=='for' then
      local j=i+1
      if value(j)=='function' then j=j+1 end
      while identifier(value(j)) do
        locals[value(j)]=true;j=j+1
        if value(j)~=',' then break end
        j=j+1
      end
    elseif t.value=='function' then
      local j=i+1
      while j<=#tokens and value(j)~='(' do
        if value(j)==':' then locals.self=true end
        j=j+1
      end
      j=j+1
      while j<=#tokens and value(j)~=')' do
        if identifier(value(j)) then locals[value(j)]=true end
        j=j+1
      end
    end
  end
  local tableDepth=0
  for i,t in ipairs(tokens) do
    local name,prev,nextValue=t.value,value(i-1),value(i+1)
    if name=='{' then tableDepth=tableDepth+1 end
    if name=='}' then tableDepth=math.max(0,tableDepth-1) end
    if identifier(name) and not locals[name] and not LuaNames.excluded(name)
      and prev~='.' and prev~=':' and prev~='::' and nextValue~='::'
      and prev~='goto' then
      local key=nextValue=='=' and (tableDepth>0 or prev==',')
      local attribute=prev=='<' and nextValue=='>' and (name=='const' or name=='close')
      if not key and not attribute then
        local provides=(nextValue=='=' and value(i+2)~='nil')
          or (prev=='function' and nextValue=='(')
        report.dependencies[#report.dependencies+1]={
          script_id=script.id,line=t.line,section=section,name=name,kind='lua_global',
          command=provides and 'lua_global_assignment' or 'lua_global_reference',
          relation=provides and 'provides' or 'requires',
          source='lua_lexical',status='unverified'
        }
      end
    end
  end
end


function M.lines(source)
  local out,lua,block,cblock=U.array(),false,false,false
  local n=0
  local luaState={}

  for raw in (source..'\n'):gmatch('(.-)\n') do
    n=n+1
    local trimmed=U.trim(raw):lower()

    if not block and not cblock and not luaState.close and not luaState.quote and trimmed=='{$lua}' then
      lua=true
      out[#out+1]={line=n,text='',directive='lua'}

    elseif lua and not luaState.close and not luaState.quote and trimmed=='{$asm}' then
      lua=false
      out[#out+1]={line=n,text='',directive='asm'}

    elseif lua and not luaState.close and not luaState.quote
      and (trimmed=='[enable]' or trimmed=='[disable]') then
      out[#out+1]={line=n,text=trimmed:upper(),luaSection=true}

    elseif lua then
      maskLua(raw,luaState)
      out[#out+1]={line=n,text='',lua=raw}

    else
      local clean,quote,i='',nil,1

      while i<=#raw do
        local c=raw:sub(i,i)
        local pair=raw:sub(i,i+1)

        if block then
          if c=='}' then
            block=false
          end

        elseif cblock then
          if pair=='*/' then
            cblock=false
            i=i+1
          end

        elseif quote then
          clean=clean..c
          if c==quote then
            quote=nil
          end

        elseif c=='"' or c=="'" then
          quote=c
          clean=clean..c

        elseif pair=='//' then
          break

        elseif pair=='/*' then
          cblock=true
          i=i+1

        elseif c=='{' then
          if raw:sub(i,i+1)=='{$' then
            clean=clean..raw:sub(i)
            break
          end
          block=true

        else
          clean=clean..c
        end

        i=i+1
      end

      out[#out+1]={line=n,text=U.trim(clean)}
    end
  end

  return out
end

local function parseByteArray(text)
  if type(text)~='string' then
    return nil
  end

  local body=text:match('^%s*{%s*(.-)%s*}%s*$')

  if not body then
    return nil
  end

  local bytes=U.array()

  for token in body:gmatch('[^,]+') do
    token=U.trim(token)

    local hex=token:match('^0[xX]([%x]+)$')
    local dec=token:match('^(%d+)$')
    local value

    if hex then
      value=tonumber(hex,16)
    elseif dec then
      value=tonumber(dec,10)
    else
      return nil
    end

    if not value or value<0 or value>255 then
      return nil
    end

    bytes[#bytes+1]=value
  end

  if #bytes==0 then
    return nil
  end

  return bytes
end

local function inspectLuaHook(text,script,report,line)
  if type(text)~='string' then
    return
  end

  local module=text:match(
    "local%s+base%s*=%s*getAddress%s*%(%s*['\"]([^'\"]+)['\"]%s*%)"
  )

  local rvaHex=text:match(
    'local%s+source%s*=%s*base%s*%+%s*0[xX]([%x]+)'
  )

  local rvaDec=text:match(
    'local%s+source%s*=%s*base%s*%+%s*(%d+)'
  )

  if not module or not rvaHex and not rvaDec then
    return
  end

  local rva

  if rvaHex then
    rva=tonumber(rvaHex,16)
  else
    rva=tonumber(rvaDec,10)
  end

  if not rva then
    return
  end

  local expectedText=text:match(
    'local%s+expected%s*=%s*({.-})'
  )

  local originalText=text:match(
    'local%s+original%s*=%s*({.-})'
  )

  local expected=parseByteArray(expectedText)
  local original=parseByteArray(originalText)

  report.resources[#report.resources+1]={
    script_id=script.id,
    line=line,
    section='enable',
    command='lua_rva_hook',
    arguments=U.array({
      module,
      string.format('0x%X',rva)
    }),
    ownership='unverified',
    lifecycle='unverified',
    hook={
      kind='lua_rva_hook',
      module=module,
      rva=string.format('0x%X',rva),
      expected_bytes=expected and #expected or U.null,
      original_bytes=original and #original or U.null,
      expected=expected or U.null,
      original=original or U.null,
      dynamic_aa=text:find('autoAssemble',1,true)~=nil,
      allocation=text:find('allocateMemory',1,true)~=nil
    }
  }

  U.warn(
    report,
    'LUA-RVA-HOOK',
    'Static module+RVA hook candidate detected lexically; runtime Lua was not executed.',
    script.id,
    line
  )
end

local scopes={
  aobscan='process',
  aobscanmodule='module',
  aobscanregion='region'
}

local counts={
  aobscan=2,
  aobscanmodule=3,
  aobscanregion=4
}

-- Deliberately narrow: no quoted names, expressions, macros or numeric addresses.
local function dependency(report,script,row,section,command,name,kind,relation)
  if not name or not name:match('^[A-Za-z_][A-Za-z0-9_]*$') or name:match('^%x+$') then
    return
  end
  report.dependencies[#report.dependencies+1]={
    script_id=script.id,line=row.line,section=section,command=command,
    name=name,kind=kind,relation=relation,source='lexical',status='unverified'
  }
end

local function commandDependencies(report,script,row,section,cmd,args)
  local function add(name,kind,relation)
    dependency(report,script,row,section,cmd,name,kind,relation)
  end
  if scopes[cmd] and #args==counts[cmd] then
    add(args[1],'symbol','provides')
  elseif cmd=='define' and #args==2 then
    add(args[1],'symbol','provides')
    add(args[2],'symbol','requires')
  elseif cmd=='label' and #args==1 then
    add(args[1],'symbol','provides')
  elseif (cmd=='alloc' and (#args==2 or #args==3))
    or (cmd=='globalalloc' and #args==2) then
    add(args[1],'resource','provides')
    add(args[1],'symbol','provides')
    if args[3] then add(args[3],'symbol','requires') end
  elseif cmd=='registersymbol' or cmd=='unregistersymbol' then
    for _,name in ipairs(args) do
      add(name,'symbol','requires')
      if cmd=='registersymbol' then add(name,'registered_symbol','provides') end
    end
  elseif cmd=='dealloc' and #args==1 then
    add(args[1],'resource','requires')
  end
end

function M.inspect(script,report)
  report.dependencies=report.dependencies or U.array()
  local section,disable,disableContent='common',false,false
  local lines=M.lines(script.text)

  script.labels=U.array()
  script.defines={}
  script.dynamic=false

  local luaText,luaLine={},nil
  local luaSection=section

  local function flushLua()
    if luaLine then
      local text=table.concat(luaText,'\n')
      luaDependencies(text,script,report,luaLine,luaSection)

      local embedded={
        id=script.id..'-lua-'..luaLine,
        language='Lua',
        text=text,
        origin='embedded',
        parent_script_id=script.id,
        record_key=script.record_key,
        line=luaLine
      }

      report.scripts[#report.scripts+1]=embedded

      inspectLuaHook(
        text,
        script,
        report,
        luaLine
      )

      luaText={}
      luaLine=nil
    end
  end

  for _,row in ipairs(lines) do
    local s=row.text

    if row.luaSection then
      flushLua()
      section=s:lower():sub(2,-2)
      if section=='disable' then disable=true end
      luaSection=section
      luaLine=row.line+1

    elseif row.directive=='lua' then
      flushLua()
      luaSection=section
      script.dynamic=true
      luaLine=row.line+1

      if section=='disable' then
        disableContent=true
      end

    elseif row.lua then
      if section=='disable' and U.trim(row.lua)~='' then disableContent=true end
      luaText[#luaText+1]=row.lua

    elseif row.directive=='asm' then
      flushLua()

    elseif s:upper()=='[ENABLE]' then
      section='enable'

    elseif s:upper()=='[DISABLE]' then
      section='disable'
      disable=true

    elseif s~='' then
      if section=='disable' then
        disableContent=true
      end

      local cmd,raw=s:match('^([%w_]+)%s*%((.*)%)%s*$')
      cmd=cmd and cmd:lower()
      local args=raw and M.arguments(raw)
      if cmd then commandDependencies(report,script,row,section,cmd,args) end

      if scopes[cmd] then
        local id='aob-'..(#report.aobs+1)

        report.aobs[#report.aobs+1]={
          id=id,
          script_id=script.id,
          line=row.line,
          section=section,
          command=cmd,
          arguments=args,
          symbol=args[1],
          scope=scopes[cmd],
          pattern=args[#args],
          syntax_supported=#args==counts[cmd],
          status='not_scanned',
          match_count=U.null,
          uniqueness='unverified',
          cross_build_robustness='unverified',
          matches=U.array(),
          matches_truncated=false,
          hook_candidates=U.array(),
          source_applicability='lexical_only'
        }

      elseif cmd=='define' and #args==2 and section~='disable' then
        local key=args[1]:lower()

        if script.defines[key]~=nil then
          script.defines[key]=false
        else
          script.defines[key]=args[2]
        end

      elseif cmd=='alloc'
        or cmd=='globalalloc'
        or cmd=='dealloc'
        or cmd=='registersymbol'
        or cmd=='unregistersymbol'
      then
        report.resources[#report.resources+1]={
          script_id=script.id,
          line=row.line,
          section=section,
          command=cmd,
          arguments=args,
          ownership='unverified',
          lifecycle='unverified'
        }

        if cmd=='dealloc' then
          U.warn(
            report,
            'RESTORE-BEFORE-FREE',
            'Review full byte restoration and in-flight execution before free; lexical order is not proof.',
            script.id,
            row.line
          )
        end

        if (cmd=='dealloc' or cmd=='unregistersymbol')
          and (raw=='' or raw:find('*',1,true))
        then
          U.warn(
            report,
            'RESOURCE-OWNERSHIP',
            'Broad cleanup candidate; ownership is unverified.',
            script.id,
            row.line
          )
        end

      elseif cmd=='include'
        or cmd=='luacall'
        or s:find('{$',1,true)
      then
        script.dynamic=true
      end

      local label=s:match('^(.-):$')

      if label then
        dependency(report,script,row,section,'address_label',U.trim(label),'symbol','requires')
      end

      if label and section~='disable' then
        script.labels[#script.labels+1]={
          expression=U.trim(label),
          line=row.line
        }
      end
    end
  end

  flushLua()

  if disable and not disableContent then
    U.warn(
      report,
      'EMPTY-DISABLE',
      'Empty DISABLE may intentionally keep a persistent library installed.',
      script.id
    )
  end

  if script.dynamic then
    U.warn(
      report,
      'DYNAMIC-SOURCE',
      'Lua/includes/preprocessor may change AA. Literal scans are lexical observations, not compiled-script equivalence.',
      script.id
    )
  end
end

return M
