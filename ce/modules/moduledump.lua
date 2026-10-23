-- Explicit user action only. Never called by passive report capture.
local U=require('util')
local Export=require('exporter')
local M={}
local function integer(n) return type(n)=='number' and n%1==0 and n>=0 end
local function find(api,name)
  local found
  for _,m in ipairs(assert(api.enumModules(),'Module enumeration failed')) do
    if type(m.Name)=='string' and m.Name:lower()==name:lower() then
      assert(not found,'Ambiguous module name');found=m
    end
  end
  return assert(found,'Module not found: '..name)
end
local function exists(path)
  local f=io.open(path,'rb');if f then f:close();return true end
  -- os.rename also detects some existing files that cannot be opened for reading.
  return os.rename(path,path) and true or false
end
function M.list(api)
  assert(integer(api.getOpenedProcessID()) and api.getOpenedProcessID()>0,'No process attached')
  return assert(api.enumModules(),'Module enumeration failed')
end
function M.write(api,name,path,options)
  options=options or {}
  assert(type(name)=='string' and name~='','Choose a module')
  assert(type(path)=='string' and path~='','Choose a destination')
  local pid=api.getOpenedProcessID()
  assert(integer(pid) and pid>0,'No process attached')
  local module=find(api,name)
  local base=module.Address
  assert(integer(base) and base>0,'Invalid module base')
  -- Numeric addresses only: never resolve a user expression or table symbol.
  assert(api.readSmallInteger(base)==0x5A4D,'Missing MZ header')
  local pe=api.readInteger(base+0x3C)
  assert(integer(pe) and pe>=64 and pe<=1048576,'Invalid PE offset')
  assert(api.readInteger(base+pe)==0x4550,'Missing PE signature')
  local magic=api.readSmallInteger(base+pe+24)
  assert(magic==0x10B or magic==0x20B,'Unsupported PE image')
  local size=api.readInteger(base+pe+0x50)
  assert(integer(size) and size>pe+0x54 and size<=0xFFFFFFFF,'Invalid SizeOfImage')
  local partial=path..'.partial'
  local metadata=path..'.json'
  local previous=U.array()
  for _,candidate in ipairs({path,partial,metadata}) do
    if exists(candidate) then previous[#previous+1]=candidate end
  end
  if #previous>0 then
    assert(type(options.confirmOverwrite)=='function',
      'Destination or sidecar already exists; overwrite confirmation required')
    if options.confirmOverwrite(previous)~=true then
      return {status='cancelled',bytes_written=0,size=size,file=path,
        error='Overwrite declined; existing files were kept.'}
    end
  end
  local report={schema_version='module-dump-1',status='partial',pid=pid,module=module.Name,
    module_path=module.PathToFile or U.null,base=U.hex(base),size=size,bytes_written=0,
    layout='mapped_image',file=partial,unreadable_ranges=U.array(),
    started_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),atomic_snapshot=false,
    binary_fingerprint=U.null,
    note='Explicit memory read; not a reconstructed executable or gameplay validation. Stops at first unreadable block; no zero padding.'}
  local function same()
    assert(api.getOpenedProcessID()==pid,'Process changed during dump')
    local current=find(api,module.Name)
    assert(current.Address==base,'Module changed during dump')
  end
  same()
  -- Retain previous outputs before replacing them. A cancelled/failed new dump
  -- must not destroy a previously complete dump or its metadata.
  if #previous>0 then
    local backups=U.array()
    local backed,failure=pcall(function()
      for _,original in ipairs(previous) do
        local saved=original..'.previous'
        local index=0
        while exists(saved) do index=index+1;saved=original..'.previous.'..index end
        assert(os.rename(original,saved))
        backups[#backups+1]={original=original,backup=saved}
      end
    end)
    if not backed then
      for index=#backups,1,-1 do
        local entry=backups[index]
        if not exists(entry.original) then os.rename(entry.backup,entry.original) end
      end
      error('Could not preserve existing output; export stopped: '..tostring(failure))
    end
    report.previous_files=backups
  end
  assert(not exists(path) and not exists(partial) and not exists(metadata),
    'Destination changed while preparing export; choose another filename')
  local f,err=io.open(partial,'wb');assert(f,err)
  local ok,failure=xpcall(function()
    local offset=0
    while offset<size do
      if options.progress and options.progress(offset,size)==false then
        report.cancelled=true;error('Cancelled by user')
      end
      assert(api.getOpenedProcessID()==pid,'Process changed during dump')
      local count=math.min(65536,size-offset)
      local success,data=pcall(api.readBytes,base+offset,count,true)
      if not success or type(data)~='table' or #data~=count then
        report.unreadable_ranges[1]={offset=offset,address=U.hex(base+offset),size=count,
          note='Failed block; following bytes were not attempted.'}
        error('Unreadable memory at '..U.hex(base+offset))
      end
      local parts={}
      for first=1,count,4096 do
        local last=math.min(first+4095,count)
        -- string.char validates integer/range itself; avoid a Lua function call
        -- and assertion for every byte of a several-hundred-MiB image.
        parts[#parts+1]=string.char(table.unpack(data,first,last))
      end
      assert(f:write(table.concat(parts)))
      offset=offset+count;report.bytes_written=offset
    end
    if options.progress and options.progress(size,size)==false then
      report.cancelled=true;error('Cancelled by user')
    end
    same()
    assert(api.readInteger(base+pe+0x50)==size,'Module size changed during dump')
  end,function(e) return tostring(e) end)
  local closed,closeError=f:close()
  if not closed then ok=false;failure=tostring(closeError) end
  if ok then
    -- Do not replace a destination created while reading memory.
    if exists(path) then ok=false;failure='Destination appeared during dump'
    else
      local renamed,renameError=os.rename(partial,path)
      if renamed then report.status='complete';report.file=path
      else ok=false;failure=tostring(renameError) end
    end
  end
  if not ok then report.error=failure end
  report.completed_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
  local saved,saveError=pcall(Export.write,report,metadata)
  assert(saved,'Dump status '..report.status..'; metadata could not be saved: '..tostring(saveError))
  return report
end
return M
