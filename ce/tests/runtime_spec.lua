package.path='ce/modules/?.lua;'..package.path

local U=require('util')
local P=require('parser')
local A=require('aob')
local D=require('disassembly')
local E=require('exporter')
local CT=require('ct')
local Env=require('environment')

local tests=0

local function test(name,fn)
  fn()
  tests=tests+1
  print('PASS '..name)
end

local function eq(actual,expected)
  assert(actual==expected,tostring(actual)..' ~= '..tostring(expected))
end

local function report(source)
  local r={
    aobs=U.array(),
    scripts=U.array(),
    resources=U.array(),
    diagnostics=U.array(),
    records=U.array(),
    modules=U.array({
      {
        name='test.exe',
        base='0x1000',
        size=0x100
      }
    }),
    target={
      attached=true,
      pid=7,
      architecture='x64'
    }
  }

  if source then
    local s={
      id='s',
      text=source,
      record_key='r',
      language='AA'
    }

    r.scripts[1]=s
    P.inspect(s,r)
  end

  return r
end

local function mock(addresses,options)
  options=options or {}

  local calls,freed={},{}

  local api={
    soExactValue=0,
    vtByteArray=8,
    rtRounded=0,
    fsmNotAligned=0,
    getOpenedProcessID=function()
      return 7
    end
  }

  api.createMemScan=function()
    local ms={
      ErrorString=options.scanError or ''
    }

    if options.noErrorProperty then
      ms.ErrorString=nil
    end

    ms.firstScan=function(...)
      calls[#calls+1]={...}

      if options.firstError then
        error('firstScan failed')
      end
    end

    ms.waitTillDone=function()
      if options.changePid then
        api.getOpenedProcessID=function()
          return 8
        end
      end
    end

    ms.destroy=function()
      freed[#freed+1]='scan'
    end

    return ms
  end

  api.createFoundList=function()
    local a={}

    for i,v in ipairs(addresses) do
      a[i-1]=v
    end

    return {
      Count=#addresses,
      Address=a,
      initialize=function()
        if options.initError then
          error('initialize failed')
        end
      end,
      destroy=function()
        freed[#freed+1]='list'
      end
    }
  end

  return api,calls,freed
end

local function context()
  return {
    synthetic=true
  }
end

test('dependency occurrences retain provenance and unresolved lifecycle',function()
  local r=report('define(alias,external)\n[ENABLE]\nalloc(buffer,1024,anchor)\nregistersymbol(buffer,shared)\nlabel(returnhere)\nreturnhere:\n[DISABLE]\nunregistersymbol(buffer)\ndealloc(buffer)')
  local d=r.dependencies
  eq(#d,13)
  eq(d[1].name,'alias');eq(d[1].relation,'provides');eq(d[1].section,'common')
  eq(d[2].name,'external');eq(d[2].relation,'requires')
  eq(d[3].kind,'resource');eq(d[3].line,3);eq(d[3].section,'enable')
  eq(d[5].name,'anchor');eq(d[5].relation,'requires')
  eq(d[6].kind,'symbol');eq(d[7].kind,'registered_symbol')
  eq(d[10].command,'label');eq(d[10].relation,'provides')
  eq(d[11].command,'address_label');eq(d[11].relation,'requires')
  eq(d[12].section,'disable');eq(d[12].line,8)
  eq(d[13].kind,'resource');eq(d[13].relation,'requires')
  eq(#r.resources,4);eq(#r.scripts[1].labels,1)
  for _,v in ipairs(d) do
    eq(v.source,'lexical');eq(v.status,'unverified');eq(v.script_id,'s')
  end
end)

test('dependencies never execute source or interpret Lua comments and expressions',function()
  local r=report([[// alloc(fake,1)
{ registersymbol(fake) }
/* label(fake) */
{$lua}
error('INSPECTED LUA MUST NOT RUN')
alloc(fake,1)
{$asm}
alloc(buffer+10,1)
registersymbol(*)
unregistersymbol(*)
dealloc()
label("quoted")
DEADBEEF:
buffer+10:
define(alias,external+10)
alloc(buffer)
aobscan(anchor)
]])
  eq(#r.dependencies,1);eq(r.dependencies[1].name,'alias')
  eq(r.scripts[1].dynamic,true)
end)

test('AOB global resources and duplicate names stay lexical in every section',function()
  local r=report('aobscan(anchor,90)\naobscanmodule(modanchor,test.exe,90)\naobscanregion(regionanchor,1000,2000,90)\nglobalalloc(shared,16)\n[DISABLE]\nalloc(buffer,16)\nlabel(shared)')
  eq(#r.dependencies,8)
  eq(r.dependencies[1].name,'anchor');eq(r.dependencies[3].name,'regionanchor')
  eq(r.dependencies[4].kind,'resource');eq(r.dependencies[6].section,'disable')
  P.inspect({id='second',text='registersymbol(shared)\nregistersymbol(shared)'},r)
  eq(#r.dependencies,12)
  eq(r.dependencies[9].script_id,'second');eq(r.dependencies[11].line,2)
  eq(r.dependencies[9].status,'unverified')
end)

test('Lua globals produce lexical occurrences with parent lines and sections',function()
  local r=report('[ENABLE]\n{$lua}\nlocal s=DWG_HC_PLAYER\nassert(DWG_HC_PLAYER.enabled)\nDWG_HC_GODMODE={enabled=true}\nDWG_HC_GODMODE.enabled=false\n[DISABLE]\nDWG_HC_GODMODE=nil\n{$asm}')
  local d=r.dependencies
  eq(#d,5);eq(d[1].line,3);eq(d[1].name,'DWG_HC_PLAYER')
  eq(d[1].relation,'requires');eq(d[3].relation,'provides')
  eq(d[4].relation,'requires');eq(d[5].relation,'requires')
  eq(d[5].section,'disable');eq(d[5].line,8)
  for _,v in ipairs(d) do
    eq(v.kind,'lua_global');eq(v.source,'lua_lexical');eq(v.status,'unverified');eq(v.script_id,'s')
  end
end)

test('Lua strings comments fields and locals do not create global dependencies',function()
  local r=report([==[{$lua}
-- DWG_COMMENT={}
--[=[ DWG_COMMENT2={}
{$asm}
[DISABLE]
]=]
local text="escaped \" DWG_STRING"
local long=[===[DWG_LONG
{$asm}
[DISABLE]
]===]
local DWG_LOCAL, DWG_LOCAL2={},{}
print(DWG_LOCAL,DWG_LOCAL2)
local f=function(DWG_PARAM) return DWG_PARAM end
for DWG_LOOP in pairs({}) do print(DWG_LOOP) end
local t={DWG_KEY=true, DWG_KEY2=false; DWG_KEY3=true}
t.DWG_FIELD=true
t:DWG_METHOD()
local s=DWG_REAL -- DWG_FAKE
{$asm}
]==])
  eq(#r.dependencies,1);eq(r.dependencies[1].name,'DWG_REAL')
  eq(r.dependencies[1].section,'common');eq(r.dependencies[1].line,19)
end)

test('Lua comparisons and self reads stay requirements and never execute',function()
  local r=report([=[{$lua}
error('MUST NOT EXECUTE')
DWG_STATE=DWG_STATE or {}
assert(DWG_STATE==nil or DWG_OTHER~=nil)
{$asm}
]=])
  eq(#r.dependencies,4);eq(r.dependencies[1].relation,'provides')
  for i=2,4 do eq(r.dependencies[i].relation,'requires') end
  eq(_G.DWG_STATE,nil)
end)

test('Lua long literals unfinished comments and chunk boundaries stay conservative',function()
  local r=report('{$lua}\nlocal x="DWG_FAKE"; DWG_FIRST={}\n{$asm}\n[DISABLE]\n{$lua}\nlocal s=DWG_FIRST\n--[==[ DWG_NEVER={}\nDWG_NEVER2={}\n')
  eq(#r.dependencies,2);eq(r.dependencies[1].relation,'provides')
  eq(r.dependencies[2].section,'disable');eq(r.dependencies[2].line,6)
end)

test('Lua named global functions and AA-looking literals remain lexical',function()
  local r=report('[ENABLE]\n{$lua}\nfunction DWG_HELPER() return DWG_PLAYER end\nlocal s=[=[\n{$lua}\n[DISABLE]\n]=]\nDWG_LAST={}\n{$asm}')
  eq(#r.dependencies,3);eq(r.dependencies[1].relation,'provides')
  eq(r.dependencies[2].relation,'requires');eq(r.dependencies[3].name,'DWG_LAST')
  eq(r.dependencies[3].section,'enable');eq(r.dependencies[3].line,8)
end)

test('AA numbers are hex, Lua is decimal',function()
  eq(U.number('17'),23)
  eq(U.number('#17'),17)
  eq(U.number('0x17'),23)
  eq(17,17)
end)

test('quoted commas and nested arguments',function()
  local a=P.arguments('s,"a,b.exe",f(1,2),AA ??')

  eq(#a,4)
  eq(a[2],'"a,b.exe"')
end)

test('comments and embedded Lua never become scans',function()
  local r=report([=[
{ aobscan(fake,90) }
/* aobscan(fake,91) */
{$lua}
error('MUST NEVER EXECUTE')
aobscan(fake,92)
{$asm}
[ENABLE]
aobscan(real,AA ??) // comment
[DISABLE]
]=])

  eq(#r.aobs,1)
  eq(r.aobs[1].symbol,'real')
  eq(r.scripts[2].language,'Lua')

  local empty=false

  for _,w in ipairs(r.diagnostics) do
    if w.rule=='EMPTY-DISABLE' then
      empty=true
    end
  end

  assert(empty)
end)

test('all three scopes retain their exact scan bounds',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'aobscanmodule(m,"test.exe",AA BB)\n'..
    'aobscanregion(r,test.exe+10,test.exe+30,AA BB)'
  )

  local api,calls,freed=mock({'1017'})

  A.validate(api,r,context)

  eq(#calls,3)
  eq(calls[1][6],0)
  eq(calls[1][7],-1)

  eq(calls[2][6],0x1000)
  eq(calls[2][7],0x1100)

  eq(calls[3][6],0x1010)
  eq(calls[3][7],0x1030)

  eq(calls[1][8],'*X*C*W')
  eq(calls[1][9],0)

  eq(r.aobs[1].uniqueness,'unique_current_scan')
  eq(#freed,6)
  eq(freed[1],'list')
  eq(freed[2],'scan')
end)

test('zero and multiple counts are explicit',function()
  for _,values in ipairs({
    {},
    {'1000','1010'}
  }) do
    local r=report('aobscan(p,AA BB)')

    A.validate(mock(values),r,context)

    eq(r.aobs[1].match_count,#values)
    eq(
      r.aobs[1].uniqueness,
      #values==0 and 'no_match' or 'multiple_matches'
    )
  end
end)

test('unresolved scope never broadens and arbitrary expressions never execute',function()
  local r=report(
    'aobscanmodule(p,missing.exe,AA BB)\n'..
    'aobscanregion(r,os.execute("bad"),2000,AA BB)'
  )

  local api,calls=mock({'1000'})

  A.validate(api,r,context)

  eq(#calls,0)
  eq(r.aobs[1].status,'unresolved')
  eq(r.aobs[2].status,'unresolved')
end)

test('hook candidate offset is AA hexadecimal, anchor remains separate',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'define(h,p+17)\n'..
    'h:\n'..
    'jmp allocated'
  )

  A.validate(mock({'1000'}),r,context)

  eq(r.aobs[1].matches[1].signature_anchor,'0x1000')
  eq(r.aobs[1].hook_candidates[1].hook_address,'0x1017')
  eq(r.aobs[1].hook_candidates[1].evidence,'static_candidate')
end)

test('multiple matches do not resolve one hook address',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'p+10:\n'..
    'jmp x'
  )

  A.validate(mock({'1000','2000'}),r,context)

  eq(
    r.aobs[1].hook_candidates[1].hook_address,
    U.null
  )
end)

test('scan failures remain unknown and release owned resources',function()
  for _,opt in ipairs({
    {firstError=true},
    {initError=true},
    {scanError='access failure'}
  }) do
    local r=report('aobscan(p,AA BB)')
    local api,_,freed=mock({},opt)

    A.validate(api,r,context)

    eq(r.aobs[1].status,'error')
    eq(r.aobs[1].match_count,U.null)
    eq(r.aobs[1].uniqueness,'unverified')
    eq(freed[#freed],'scan')
  end
end)

test('missing error API does not certify uniqueness',function()
  local r=report('aobscan(p,AA BB)')

  A.validate(
    mock(
      {'1000'},
      {noErrorProperty=true}
    ),
    r,
    context
  )

  eq(r.aobs[1].uniqueness,'unverified')
  eq(r.aobs[1].match_count,1)
end)

test('process change invalidates scan',function()
  local r=report('aobscan(p,AA BB)')

  A.validate(
    mock(
      {'1000'},
      {changePid=true}
    ),
    r,
    context
  )

  eq(r.aobs[1].status,'invalidated')
  eq(r.aobs[1].match_count,U.null)
  eq(#r.aobs[1].matches,0)
end)

test('export truncation preserves full count',function()
  local r=report('aobscan(p,AA BB)')
  local addresses={}

  for i=1,300 do
    addresses[i]=string.format(
      '%X',
      0x1000+i
    )
  end

  A.validate(
    mock(addresses),
    r,
    context
  )

  eq(r.aobs[1].match_count,300)
  eq(#r.aobs[1].matches,256)
  eq(r.aobs[1].matches_truncated,true)
end)

test('unsupported patterns stay unverified',function()
  local r=report(
    'aobscan(p,?? ??)\n'..
    'aobscan(q,pattern_macro)\n'..
    'aobscanmodule(broken,AA)'
  )

  local api,calls=mock({})

  A.validate(api,r,context)

  eq(#calls,0)

  for _,a in ipairs(r.aobs) do
    eq(a.status,'unsupported')
  end

  eq(A.pattern('4? ?F **'),'4? ?f ??')
end)

test('define cycles cannot loop',function()
  eq(
    A.resolve(
      'a',
      {},
      {
        a='b',
        b='a'
      }
    ),
    nil
  )
end)

test('RIP-relative subset and unknown coverage',function()
  eq(
    D.rip(
      {0x48,0x8B,0x05,1,2,3,4},
      'x64'
    ),
    'rip_relative'
  )

  eq(
    D.rip(
      {0x67,0x48,0x8B,0x05,1,2,3,4},
      'x64'
    ),
    'not_rip_relative'
  )

  eq(
    D.rip(
      {0x48,0x8B,0x45,0x08},
      'x64'
    ),
    'not_rip_relative'
  )

  eq(
    D.rip(
      {0xC5,0xFA},
      'x64'
    ),
    'unknown'
  )

  eq(
    D.rip(
      {0x8B,0x05},
      'x86'
    ),
    'not_applicable'
  )
end)

test('disassembly metadata, forward alignment and cleanup',function()
  local destroyed=false

  local api={
    readBytes=function()
      return {
        0x90
      }
    end,

    createDisassembler=function()
      return {
        disassemble=function()
          return 'call 2000'
        end,

        getLastDisassembleData=function()
          return {
            bytes={
              0xE8,
              0,
              0,
              0,
              0
            },
            opcode='call',
            isCall=true,
            parameterValueType=1,
            parameterValue=0x2000
          }
        end,

        destroy=function()
          destroyed=true
        end
      }
    end
  }

  local c=D.capture(
    api,
    0x1000,
    'x64'
  )

  eq(c.status,'partial')
  eq(#c.instructions,8)
  eq(c.instructions[2].address,'0x1005')
  eq(c.instructions[1].branch,'call')
  eq(c.instructions[1].parameter_address,'0x2000')
  assert(destroyed)
end)

test('JSON empty arrays, null, Unicode, escaping and cycles',function()
  eq(
    E.encode({
      a=U.array(),
      b={},
      c=U.null
    }),
    '{'..
    '"a":[],'..
    '"b":{},'..
    '"c":null}'
  )

  eq(
    E.encode('ñ\n"\\'),
    '"ñ\\n\\"\\\\"'
  )

  local t={}
  t.self=t

  assert(not pcall(E.encode,t))
  assert(not pcall(E.encode,0/0))
end)

test('CT hierarchy, repeated IDs, selection and no activation',function()
  local parent={
    ID=1,
    Description='group',
    Type=0,
    OffsetCount=0
  }

  local child={
    ID=1,
    Description='script',
    Type=11,
    Script='[ENABLE]\naobscan(p,AA BB)\n[DISABLE]',
    Parent=parent,
    Active=false,
    OffsetCount=0
  }

  local al={
    Count=2,
    SelectedRecord=child,

    getMemoryRecord=function(i)
      return ({
        parent,
        child
      })[i+1]
    end
  }

  local api={
    vtAutoAssembler=11,

    getAddressList=function()
      return al
    end,

    getLuaEngine=function()
      return {
        mScript={
          Lines={
            Text='error("never execute")'
          }
        }
      }
    end
  }

  local r=report()

  CT.capture(
    api,
    r,
    false
  )

  eq(#r.records,2)
  eq(r.records[2].parent_key,'record-1')
  eq(child.Active,false)
  eq(r.ct.table_lua_status,'editor_snapshot')
  eq(#r.scripts,2)

  r=report()

  CT.capture(
    api,
    r,
    true
  )

  eq(#r.records,1)
  eq(r.records[1].key,'record-2')
end)

test('no process is not x86',function()
  local r=report()

  Env.capture(
    {
      getOpenedProcessID=function()
        return 0
      end
    },
    r
  )

  eq(r.target.architecture,'unknown')
  eq(r.target.attached,false)
end)

test('CE wrapper identity does not break hierarchy or selection',function()
  local api={
    vtAutoAssembler=11,

    getAddressList=function()
      return {
        Count=2,
        SelectedRecord={
          Index=1
        },

        getMemoryRecord=function(i)
          return {
            ID=1,
            Index=i,
            Type=0,
            Parent=i==1 and {
              Index=0
            } or nil
          }
        end
      }
    end
  }

  local r=report()

  CT.capture(
    api,
    r,
    true
  )

  eq(#r.records,1)
  eq(r.records[1].parent_key,'record-1')
end)

test('repeated symbols and defines do not invent a hook',function()
  local r=report(
    'aobscan(p,AA BB)\n'..
    'aobscan(p,CC DD)\n'..
    'p+10:\n'..
    'jmp x\n'..
    'define(a,10)\n'..
    'define(a,20)\n'..
    'define(a,30)'
  )

  A.validate(
    mock({'1000'}),
    r,
    context
  )

  eq(#r.aobs[1].hook_candidates,0)
  eq(r.scripts[1].defines.a,false)
end)

test('Lua static RVA hook is inventoried without execution',function()
  local r=report([=[
[ENABLE]
{$lua}
if syntaxcheck then return end
local base=getAddress('Dawnwalker.exe')
local source=base+0x5F33B4A
local expected={0x48,0x8B,0x4B,0x10,0x48,0x8B,0xD0,0xE8,0xDA,0x33,0x13,0xFB,0x84,0xC0,0x0F,0x84}
local original={0x48,0x8B,0x4B,0x10,0x48,0x8B,0xD0}
local cave=allocateMemory(4096,source,0x40)
local assembly=string.format([[nop]])
local ok,err=autoAssemble(assembly)
{$asm}
[DISABLE]
]=])

  eq(#r.resources,1)

  local resource=r.resources[1]

  eq(resource.command,'lua_rva_hook')

  local hook=resource.hook

  eq(hook.kind,'lua_rva_hook')
  eq(hook.module,'Dawnwalker.exe')
  eq(hook.rva,'0x5F33B4A')
  eq(hook.expected_bytes,16)
  eq(hook.original_bytes,7)
  eq(hook.allocation,true)
  eq(hook.dynamic_aa,true)

  eq(hook.expected[1],0x48)
  eq(hook.expected[16],0x84)

  eq(hook.original[1],0x48)
  eq(hook.original[7],0xD0)

  local found=false

  for _,w in ipairs(r.diagnostics) do
    if w.rule=='LUA-RVA-HOOK' then
      found=true
    end
  end

  assert(found)
end)

test('bundle installs once and cleans only its own menu; export is fresh',function()
  local installed,destroyed=0,0

  getMainForm=function()
    return {
      Menu={
        Items={
          add=function()
            installed=installed+1
          end
        }
      }
    }
  end

  createMenuItem=function()
    return {
      add=function()
      end,

      destroy=function()
        destroyed=destroyed+1
      end
    }
  end

  getOpenedProcessID=function()
    return 0
  end

  getCEVersion=function()
    return 7.7
  end

  local core=dofile('releases/CESuite_Core.lua')

  eq(installed,1)

  local again=dofile('releases/CESuite_Core.lua')

  eq(again,core)
  eq(installed,1)
  eq(destroyed,0)

  local r=core.analyze('export')

  eq(r.target.attached,false)

  core.export(
    'ce/tests/generated-report.json'
  )

  local fake=mock({'1010'})

  for k,v in pairs(fake) do
    _G[k]=v
  end

  process='test.exe'

  targetIs64Bit=function()
    return true
  end

  enumModules=function()
    return {
      {
        Name='test.exe',
        Address=0x1000,
        Is64Bit=true,
        PathToFile='synthetic/test.exe'
      }
    }
  end

  getModuleSize=function()
    return 0x100
  end

  vtAutoAssembler=11

  getAddressList=function()
    return {
      Count=1,
      LoadedTableVersion=45,

      getMemoryRecord=function()
        return {
          ID=1,
          Description='Synthetic only',
          Type=11,
          OffsetCount=0,
          Script=
            '[ENABLE]\n'..
            'aobscanmodule(p,test.exe,48 8B ??)\n'..
            'p+17:\n'..
            'jmp x\n'..
            '[DISABLE]'
        }
      end
    }
  end

  getLuaEngine=function()
    return {
      mScript={
        Lines={
          Text='-- synthetic table Lua'
        }
      }
    }
  end

  readBytes=function()
    local b={}

    for i=1,48 do
      b[i]=0x90
    end

    return b
  end

  createDisassembler=function()
    return {
      disassemble=function()
        return 'nop'
      end,

      getLastDisassembleData=function()
        return {
          opcode='nop',
          bytes={
            0x90
          },
          isCall=false,
          isJump=false,
          isRet=false
        }
      end,

      destroy=function()
      end
    }
  end

  r=core.analyze('export')

  eq(
    r.aobs[1].uniqueness,
    'unique_current_scan'
  )

  core.export(
    'ce/tests/generated-observed.json'
  )

  getAddressList=function()
    return {Count=1,LoadedTableVersion=45,getMemoryRecord=function()
      return {ID=2,Type=11,Description='Dependency fixture',OffsetCount=0,Script=[[
[ENABLE]
alloc(buffer,16)
registersymbol(buffer)
{$lua}
error('SOURCE MUST NEVER EXECUTE')
local s=DWG_HC_PLAYER
DWG_HC_GODMODE={enabled=true}
local base = getAddress('test.exe')
local source = base + 0x10
local expected = {0x90}
local original = {0x90}
{$asm}
[DISABLE]
unregistersymbol(buffer)
dealloc(buffer)
]]}
    end}
  end
  core.export('ce/tests/generated-dependencies.json')

  core.shutdown()

  eq(destroyed,1)
end)

print(
  string.format(
    '%d Lua tests passed (synthetic CE API mocks; no live CE validation)',
    tests
  )
)
