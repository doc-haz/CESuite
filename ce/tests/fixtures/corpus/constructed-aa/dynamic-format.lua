local fmt = 'aobScanRegion(%s, %X, %X, %s)'
local payload = makePayload()
autoAssemble(fmt:format('sym', 1, 2, payload))
