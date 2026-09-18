-- Conservative lexical AA inventory. Never compiles AA or evaluates Lua/expressions.
local U=require('util')
local M={}
function M.arguments(s)
  local out, start, depth, quote=U.array(),1,0,nil
  for i=1,#s do
    local c=s:sub(i,i)
    if quote then if c==quote then quote=nil end
    elseif c=='"' or c=="'" then quote=c
    elseif c=='(' then depth=depth+1
    elseif c==')' then depth=depth-1
    elseif c==',' and depth==0 then out[#out+1]=U.trim(s:sub(start,i-1));start=i+1 end
  end
  out[#out+1]=U.trim(s:sub(start))
  return out
end
function M.lines(source)
  local out, lua, block, cblock=U.array(),false,false,false
  local n=0
  for raw in (source..'\n'):gmatch('(.-)\n') do
    n=n+1
    local trimmed=U.trim(raw):lower()
    if not block and not cblock and trimmed=='{$lua}' then lua=true;out[#out+1]={line=n,text='',directive='lua'}
    elseif lua and trimmed=='{$asm}' then lua=false;out[#out+1]={line=n,text='',directive='asm'}
    elseif lua then out[#out+1]={line=n,text='',lua=raw}
    else
      local clean,quote,i='',nil,1
      while i<=#raw do
        local c,pair=raw:sub(i,i),raw:sub(i,i+1)
        if block then if c=='}' then block=false end
        elseif cblock then if pair=='*/' then cblock=false;i=i+1 end
        elseif quote then clean=clean..c;if c==quote then quote=nil end
        elseif c=='"' or c=="'" then quote=c;clean=clean..c
        elseif pair=='//' then break
        elseif pair=='/*' then cblock=true;i=i+1
        elseif c=='{' then
          if raw:sub(i,i+1)=='{$' then clean=clean..raw:sub(i);break end
          block=true
        else clean=clean..c end
        i=i+1
      end
      out[#out+1]={line=n,text=U.trim(clean)}
    end
  end
  return out
end
local scopes={aobscan='process',aobscanmodule='module',aobscanregion='region'}
local counts={aobscan=2,aobscanmodule=3,aobscanregion=4}
function M.inspect(script, report)
  local section, disable, disableContent='common',false,false
  local lines=M.lines(script.text)
  script.labels=U.array();script.defines={};script.dynamic=false
  local luaText,luaLine={},nil
  local function flushLua()
    if luaLine then report.scripts[#report.scripts+1]={id=script.id..'-lua-'..luaLine,
      language='Lua',text=table.concat(luaText,'\n'),origin='embedded',parent_script_id=script.id,
      record_key=script.record_key,line=luaLine};luaText={};luaLine=nil end
  end
  for _,row in ipairs(lines) do
    local s=row.text
    if row.directive=='lua' then script.dynamic=true;luaLine=row.line+1;if section=='disable' then disableContent=true end
    elseif row.lua then luaText[#luaText+1]=row.lua
    elseif row.directive=='asm' then flushLua()
    elseif s:upper()=='[ENABLE]' then section='enable'
    elseif s:upper()=='[DISABLE]' then section='disable';disable=true
    elseif s~='' then
      if section=='disable' then disableContent=true end
      local cmd,raw=s:match('^([%w_]+)%s*%((.*)%)%s*$')
      cmd=cmd and cmd:lower()
      local args=raw and M.arguments(raw)
      if scopes[cmd] then
        local id='aob-'..(#report.aobs+1)
        report.aobs[#report.aobs+1]={id=id,script_id=script.id,line=row.line,section=section,
          command=cmd,arguments=args,symbol=args[1],scope=scopes[cmd],pattern=args[#args],
          syntax_supported=#args==counts[cmd],status='not_scanned',match_count=U.null,
          uniqueness='unverified',cross_build_robustness='unverified',matches=U.array(),
          matches_truncated=false,hook_candidates=U.array(),source_applicability='lexical_only'}
      elseif cmd=='define' and #args==2 and section~='disable' then
        local key=args[1]:lower()
        if script.defines[key]~=nil then script.defines[key]=false else script.defines[key]=args[2] end
      elseif cmd=='alloc' or cmd=='globalalloc' or cmd=='dealloc' or cmd=='registersymbol' or cmd=='unregistersymbol' then
        report.resources[#report.resources+1]={script_id=script.id,line=row.line,section=section,
          command=cmd,arguments=args,ownership='unverified',lifecycle='unverified'}
        if cmd=='dealloc' then U.warn(report,'RESTORE-BEFORE-FREE','Review full byte restoration and in-flight execution before free; lexical order is not proof.',script.id,row.line) end
        if (cmd=='dealloc' or cmd=='unregistersymbol') and (raw=='' or raw:find('*',1,true)) then
          U.warn(report,'RESOURCE-OWNERSHIP','Broad cleanup candidate; ownership is unverified.',script.id,row.line)
        end
      elseif cmd=='include' or cmd=='luacall' or s:find('{$',1,true) then script.dynamic=true end
      local label=s:match('^(.-):$')
      if label and section~='disable' then script.labels[#script.labels+1]={expression=U.trim(label),line=row.line} end
    end
  end
  flushLua()
  if disable and not disableContent then U.warn(report,'EMPTY-DISABLE','Empty DISABLE may intentionally keep a persistent library installed.',script.id) end
  if script.dynamic then U.warn(report,'DYNAMIC-SOURCE','Lua/includes/preprocessor may change AA. Literal scans are lexical observations, not compiled-script equivalence.',script.id) end
end
return M
