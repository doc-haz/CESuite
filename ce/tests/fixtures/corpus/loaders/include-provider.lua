local function include(name)
  local f = assert(findTableFile(name .. '.lua'))
  return assert(load(readStringLocal(f.stream.memory, f.stream.size)))()
end
_G.Register = include('Register')
_G.UE = include('UE')
