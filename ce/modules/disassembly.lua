local U=require('util')
local M={}
-- CE does not document a universal RIP-relative flag. Recognize only selected
-- legacy one-byte opcodes whose ModRM position is known; all others stay unknown.
function M.rip(bytes,arch)
  if arch=='x86' then return 'not_applicable' end
  if arch~='x64' then return 'unknown' end
  local i,addressOverride=1,false
  while bytes[i] do
    local b=bytes[i]
    if b==0x67 then addressOverride=true;i=i+1
    elseif b==0x66 or b==0xF0 or b==0xF2 or b==0xF3 or b==0x2E or b==0x36 or b==0x3E or b==0x26 or b==0x64 or b==0x65 or (b>=0x40 and b<=0x4F) then i=i+1
    else break end
  end
  local op=bytes[i]
  local known={[0x8B]=true,[0x89]=true,[0x8D]=true,[0x8A]=true,[0x88]=true,[0xFF]=true,[0xC7]=true,[0xC6]=true,
    [0x01]=true,[0x03]=true,[0x29]=true,[0x2B]=true,[0x39]=true,[0x3B]=true,[0x85]=true}
  local modrm=bytes[i+1]
  if not known[op] or not modrm then return 'unknown' end
  if addressOverride then return 'not_rip_relative' end
  return modrm<0x40 and modrm%8==5 and 'rip_relative' or 'not_rip_relative'
end
-- Compatibility stub: CE disassembly can invoke global overrides/callbacks.
-- Omit optional context without accessing CE APIs.
function M.capture(api,address,arch)
  return nil
end
return M
