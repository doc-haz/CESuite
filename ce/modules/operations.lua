-- Operational telemetry: timings, completion state and structured warnings.
-- This is metadata about the work, never evidence about the target. Telemetry is
-- best effort: a missing clock yields null metrics plus a warning, it never fails
-- the operation that is being measured.
local U=require('util')
local M={}

local WRAP=4294967296

function M.clock()
  if type(getTickCount)=='function' then
    local ok,value=pcall(getTickCount)
    if ok and type(value)=='number' then return value,'getTickCount' end
  end
  if type(os)=='table' and type(os.clock)=='function' then
    local ok,value=pcall(os.clock)
    if ok and type(value)=='number' then return value*1000,'os.clock' end
  end
  return nil,nil
end

function M.begin()
  local value,source=M.clock()
  return value,source
end

function M.elapsed(start)
  if type(start)~='number' then return U.null,'unavailable' end
  local now,source=M.clock()
  if type(now)~='number' then return U.null,'unavailable' end
  local delta=now-start
  if delta<0 then delta=delta+WRAP end
  if delta<0 then return U.null,'invalid' end
  return delta,source
end

function M.new(stage)
  return {
    status='complete',
    source_complete=false,
    partial=false,
    cancelled=false,
    stage=stage or 'operation',
    provenance='instrumented',
    timing_source='unavailable',
    warnings=U.array(),
    metrics={
      duration_ms=U.null,
      parse_ms=U.null,
      scan_ms=U.null,
      export_ms=U.null,
      serialize_ms=U.null,
      write_ms=U.null,
      source_bytes=U.null,
      export_bytes=U.null,
      items_processed=U.null,
      items_total=U.null,
      operations_attempted=U.null,
      operations_completed=U.null
    }
  }
end

function M.warn(operation,code,message,stage)
  if type(operation)~='table' then return end
  for _,warning in ipairs(operation.warnings) do
    if warning.code==code and warning.stage==(stage or operation.stage) then return end
  end
  operation.warnings[#operation.warnings+1]={code=code,message=message,stage=stage or operation.stage}
end

function M.stage(operation,field,start,label)
  local ms,source=M.elapsed(start)
  operation.metrics[field]=ms
  if ms~=U.null then
    operation.timing_source=source or operation.timing_source
    if source=='os.clock' then
      M.warn(operation,'TIMING_APPROXIMATE',
        'getTickCount is unavailable; durations use os.clock CPU time and underestimate wall time.',
        label or operation.stage)
    end
  else
    M.warn(operation,'TIMING_UNAVAILABLE',
      'The timing source did not provide a value for this stage.',
      label or operation.stage)
  end
  return ms
end

function M.finish(operation,start,label)
  return M.stage(operation,'duration_ms',start,label or operation.stage)
end

function M.finalize(operation)
  if operation.cancelled then
    operation.status='cancelled'
  elseif operation.status=='failed' or operation.status=='unavailable' then
    -- Keep the explicit status chosen by the caller.
  elseif operation.partial then
    operation.status='partial'
  else
    operation.status='complete'
  end
  if not operation.source_complete then
    M.warn(operation,'SOURCE_INCOMPLETE',
      'The operation produced usable work but could not traverse the full planned source.',
      operation.stage)
  end
  return operation
end

function M.exportOperation(timing)
  timing=timing or {}
  local operation=M.new('export')
  operation.source_complete=timing.total_ms~=nil and timing.total_ms~=U.null
  operation.metrics.export_ms=timing.total_ms or U.null
  operation.metrics.serialize_ms=timing.serialize_ms or U.null
  operation.metrics.write_ms=timing.write_ms or U.null
  operation.metrics.export_bytes=timing.bytes or U.null
  operation.metrics.items_total=1
  operation.metrics.items_processed=timing.ok and 1 or 0
  operation.metrics.operations_attempted=1
  operation.metrics.operations_completed=timing.ok and 1 or 0
  if not timing.ok then operation.status='failed' else operation.status='complete' end
  if operation.metrics.export_ms==U.null then
    M.warn(operation,'TIMING_UNAVAILABLE','Export timing was not available.','write')
  end
  return M.finalize(operation)
end

local function metric(value,suffix)
  if value==U.null or value==nil then return 'unavailable' end
  if type(value)~='number' then return tostring(value) end
  if suffix=='ms' then return string.format('%.1f ms',value) end
  return tostring(value)
end

function M.render(operation,export_operation)
  local lines={'','Operation Summary',''}
  if type(operation)~='table' then
    lines[#lines+1]='No operation telemetry available.'
  else
    lines[#lines+1]=string.format('Status: %s | source complete: %s | partial: %s | cancelled: %s',
      tostring(operation.status),operation.source_complete and 'yes' or 'no',
      operation.partial and 'yes' or 'no',operation.cancelled and 'yes' or 'no')
    local metrics=operation.metrics or {}
    lines[#lines+1]='Parse: '..metric(metrics.parse_ms,'ms')..
      ' | Scan: '..metric(metrics.scan_ms,'ms')..
      ' | Total: '..metric(metrics.duration_ms,'ms')
    lines[#lines+1]='Source bytes: '..metric(metrics.source_bytes)..
      ' | Items: '..metric(metrics.items_processed)..'/'..metric(metrics.items_total)
    lines[#lines+1]=string.format('Timing source: %s',tostring(operation.timing_source))
    if #operation.warnings>0 then
      lines[#lines+1]='Warnings: '..#operation.warnings
      for _,warning in ipairs(operation.warnings) do
        lines[#lines+1]='  - '..warning.code..' ('..warning.stage..'): '..warning.message
      end
    else
      lines[#lines+1]='Warnings: 0'
    end
  end
  if type(export_operation)=='table' then
    lines[#lines+1]=''
    lines[#lines+1]=string.format('Last export: %s | total %s | serialize %s | write %s | %s bytes',
      tostring(export_operation.status),
      metric(export_operation.metrics.export_ms,'ms'),
      metric(export_operation.metrics.serialize_ms,'ms'),
      metric(export_operation.metrics.write_ms,'ms'),
      metric(export_operation.metrics.export_bytes))
  end
  return table.concat(lines,'\n')
end

return M
