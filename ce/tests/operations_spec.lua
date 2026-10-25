package.path='ce/modules/?.lua;'..package.path
-- Operational telemetry tests. Synthetic clocks only; no CE and no target.
local U=require('util')
local Ops=require('operations')

local tests=0
local realGetTickCount=getTickCount
local realOsClock=os.clock
local function restoreClock()
  getTickCount=realGetTickCount
  os.clock=realOsClock
end
local function test(name,fn)
  local ok,err=pcall(fn)
  restoreClock()
  if not ok then error(name..': '..tostring(err)) end
  tests=tests+1
  print('PASS '..name)
end
local function eq(actual,expected,label)
  assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..
    ' got '..tostring(actual))
end
local function hasRule(op,code)
  for _,warning in ipairs(op.warnings) do if warning.code==code then return true end end
  return false
end

test('getTickCount is preferred and reports milliseconds',function()
  local now=1000
  getTickCount=function() return now end
  local op=Ops.new('unit')
  local started=Ops.begin()
  now=1042
  eq(Ops.stage(op,'parse_ms',started,'parse'),42)
  eq(op.timing_source,'getTickCount')
  eq(op.metrics.parse_ms,42)
end)

test('tick wrap is handled as a positive interval',function()
  local now=4294967290
  getTickCount=function() return now end
  local op=Ops.new('unit')
  local started=Ops.begin()
  now=4
  eq(Ops.stage(op,'duration_ms',started,'unit'),10)
  eq(op.metrics.duration_ms,10)
end)

test('missing clock yields null metrics and TIMING_UNAVAILABLE',function()
  getTickCount=nil
  os.clock=function() error('clock unavailable') end
  local op=Ops.new('unit')
  local started=Ops.begin()
  eq(started,nil)
  eq(Ops.stage(op,'parse_ms',started,'parse'),U.null)
  eq(op.metrics.parse_ms,U.null)
  assert(hasRule(op,'TIMING_UNAVAILABLE'),'TIMING_UNAVAILABLE expected')
  Ops.finish(op,started,'unit')
  eq(op.metrics.duration_ms,U.null)
end)

test('os.clock fallback is marked approximate',function()
  getTickCount=nil
  os.clock=function() return 1.25 end
  local op=Ops.new('unit')
  local started=Ops.begin()
  os.clock=function() return 1.26 end
  local ms=Ops.stage(op,'parse_ms',started,'parse')
  assert(type(ms)=='number' and ms>=0,'expected numeric duration')
  eq(op.timing_source,'os.clock')
  assert(hasRule(op,'TIMING_APPROXIMATE'),'TIMING_APPROXIMATE expected')
end)

test('default metrics are nullable and distinct per operation',function()
  local a=Ops.new('a')
  local b=Ops.new('b')
  eq(a.metrics.duration_ms,U.null)
  eq(a.metrics.source_bytes,U.null)
  a.metrics.source_bytes=10
  eq(b.metrics.source_bytes,U.null,'operations must not share metric tables')
  a.metrics.duration_ms=1.5
  eq(b.metrics.duration_ms,U.null)
end)

test('complete operation requires source_complete',function()
  local op=Ops.new('unit')
  op.source_complete=true
  Ops.finalize(op)
  eq(op.status,'complete')
  eq(hasRule(op,'SOURCE_INCOMPLETE'),false)
end)

test('partial operation is usable but marked partial',function()
  local op=Ops.new('unit')
  op.source_complete=false
  op.partial=true
  Ops.finalize(op)
  eq(op.status,'partial')
  assert(hasRule(op,'SOURCE_INCOMPLETE'),'SOURCE_INCOMPLETE expected')
end)

test('cancelled representation wins over other flags',function()
  local op=Ops.new('unit')
  op.cancelled=true
  op.partial=true
  Ops.finalize(op)
  eq(op.status,'cancelled')
  assert(hasRule(op,'SOURCE_INCOMPLETE'),'SOURCE_INCOMPLETE expected')
end)

test('failed and unavailable statuses are preserved',function()
  local failed=Ops.new('unit');failed.status='failed';Ops.finalize(failed)
  eq(failed.status,'failed')
  local unavailable=Ops.new('unit');unavailable.status='unavailable';Ops.finalize(unavailable)
  eq(unavailable.status,'unavailable')
end)

test('warnings are structured and de-duplicated per stage',function()
  local op=Ops.new('unit')
  Ops.warn(op,'BOUNDED_LIMIT','limit reached','scan')
  Ops.warn(op,'BOUNDED_LIMIT','limit reached again','scan')
  Ops.warn(op,'BOUNDED_LIMIT','limit reached','parse')
  eq(#op.warnings,2)
  local w=op.warnings[1]
  eq(type(w.code),'string');eq(type(w.message),'string');eq(type(w.stage),'string')
  eq(w.code,'BOUNDED_LIMIT');eq(w.stage,'scan')
end)

test('counters keep separate item and operation totals',function()
  local op=Ops.new('unit')
  op.metrics.items_total=4
  op.metrics.items_processed=3
  op.metrics.operations_attempted=4
  op.metrics.operations_completed=3
  Ops.finalize(op)
  eq(op.metrics.items_processed,3)
  eq(op.metrics.items_total,4)
  eq(op.metrics.operations_attempted,4)
  eq(op.metrics.operations_completed,3)
end)

test('export operation maps timings and bytes without claiming success',function()
  local op=Ops.exportOperation({ok=true,bytes=1234,serialize_ms=2.5,write_ms=1.5,total_ms=5})
  eq(op.status,'complete')
  eq(op.metrics.export_ms,5)
  eq(op.metrics.serialize_ms,2.5)
  eq(op.metrics.write_ms,1.5)
  eq(op.metrics.export_bytes,1234)
  eq(op.source_complete,true)
  local failed=Ops.exportOperation({ok=false,bytes=10,serialize_ms=1,write_ms=1,total_ms=2})
  eq(failed.status,'failed')
  eq(failed.metrics.items_processed,0)
end)

test('export without timing keeps null metrics and warns',function()
  local op=Ops.exportOperation({ok=true,bytes=3})
  eq(op.metrics.export_ms,U.null)
  assert(hasRule(op,'TIMING_UNAVAILABLE'),'TIMING_UNAVAILABLE expected')
end)

test('render is informative and avoids verdicts',function()
  local op=Ops.new('analysis')
  op.metrics.parse_ms=1
  op.metrics.scan_ms=2
  op.metrics.duration_ms=4
  op.metrics.source_bytes=10
  op.metrics.items_processed=1
  op.metrics.items_total=2
  op.source_complete=false
  op.partial=true
  Ops.warn(op,'SOURCE_INCOMPLETE','partial source','analysis')
  Ops.finalize(op)
  local text=Ops.render(op,Ops.exportOperation({ok=true,bytes=5,total_ms=1}))
  assert(text:find('Operation Summary',1,true),'summary title missing')
  assert(text:find('Status: partial',1,true),'status missing')
  assert(text:find('Parse: 1.0 ms',1,true),'parse metric missing')
  assert(text:find('Last export:',1,true),'export summary missing')
  for _,word in ipairs({'GOOD','BAD','FAST','SLOW'}) do
    assert(not text:find(word,1,true),'verdict word must not appear: '..word)
  end
end)

test('render without telemetry stays neutral',function()
  local text=Ops.render(nil,nil)
  assert(text:find('No operation telemetry available.',1,true),'missing neutral message')
end)
print(string.format('%d operations tests passed (synthetic clocks; no live CE)',tests))
