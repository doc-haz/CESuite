-- Minimal loader binding fixture. Text only; the analyzer never executes it.
local function include(name)
    local tf = assert(findTableFile(name .. '.lua'))
    local source = readStringLocal(tf.stream.memory, tf.stream.size)
    return assert(load(source))()
end
_G.Starter = include('Starter')
_G.Register = include('Register')
_G.Recorder = include('Recorder')
_G.UE = include('UE')
