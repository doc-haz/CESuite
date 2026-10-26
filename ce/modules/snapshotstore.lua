-- Bounded snapshot file storage. Files are data only; no code is executed.
local U=require('util')
local Snapshot=require('snapshot')

local M={}
M.MAX_BYTES=8*1024*1024
M.PARTIAL_SUFFIX='.cesuite-partial'
M.BACKUP_SUFFIX='.cesuite-backup'

local function file_size(path)
  local f=io.open(path,'rb')
  if not f then return nil end
  local size=f:seek('end')
  f:close()
  return size
end
local function exists(path) return file_size(path)~=nil end

function M.read(path,options)
  if type(path)~='string' or path=='' then return nil,{code='invalid_path',message='path required'} end
  local size=file_size(path)
  if size==nil then return nil,{code='read_failed',message='could not open snapshot'} end
  if size>M.MAX_BYTES then return nil,{code='snapshot_too_large',message='snapshot exceeds 8 MiB'} end
  local f,openError=io.open(path,'rb')
  if not f then return nil,{code='read_failed',message=tostring(openError)} end
  local text=f:read('*a');f:close()
  if type(text)~='string' then return nil,{code='read_failed',message='could not read snapshot'} end
  if #text>M.MAX_BYTES then return nil,{code='snapshot_too_large',message='snapshot exceeds 8 MiB'} end
  local snapshot,err=Snapshot.decode(text,{max_bytes=M.MAX_BYTES})
  if not snapshot then return nil,err end
  return snapshot
end

function M.write(snapshot,path,options)
  options=options or {}
  if type(path)~='string' or path=='' then return nil,{code='invalid_path',message='path required'} end
  local ok,errs=Snapshot.validate(snapshot)
  if not ok then return nil,{code='schema_invalid',message=table.concat(errs,'; ')} end
  local encoded=Snapshot.encode(snapshot)
  if #encoded>M.MAX_BYTES then return nil,{code='snapshot_too_large',message='snapshot exceeds 8 MiB'} end
  local existed=exists(path)
  if existed and options.overwrite~=true then
    return nil,{code='overwrite_required',message='snapshot already exists'}
  end
  local temp=path..M.PARTIAL_SUFFIX
  if exists(temp) then return nil,{code='temp_exists',message='reserved temporary file already exists'} end
  local f,openError=io.open(temp,'wb')
  if not f then return nil,{code='write_failed',message=tostring(openError)} end
  local wrote,writeError=f:write(encoded)
  local closed,closeError=f:close()
  if not wrote or not closed then
    pcall(os.remove,temp)
    return nil,{code='write_failed',message=tostring(writeError or closeError)}
  end
  if existed then
    local backup=path..M.BACKUP_SUFFIX
    if exists(backup) then
      pcall(os.remove,temp)
      return nil,{code='backup_exists',message='reserved backup file already exists'}
    end
    local moved,moveError=os.rename(path,backup)
    if not moved then
      pcall(os.remove,temp)
      return nil,{code='rename_failed',message=tostring(moveError)}
    end
    local promoted,promoteError=os.rename(temp,path)
    if not promoted then
      pcall(os.rename,backup,path)
      pcall(os.remove,temp)
      return nil,{code='rename_failed',message=tostring(promoteError)}
    end
    pcall(os.remove,backup)
  else
    local promoted,promoteError=os.rename(temp,path)
    if not promoted then
      pcall(os.remove,temp)
      return nil,{code='rename_failed',message=tostring(promoteError)}
    end
  end
  return {status='complete',path=path,bytes=#encoded,overwritten=existed}
end

return M
