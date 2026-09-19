-- Static, case-sensitive exclusions. Never inspect ambient _G or call CE APIs.
-- Lua 5.1-5.4 standard names and a deliberately bounded CE API inventory.
-- CE spellings follow celua.txt and defines.lua; not a complete API catalog.
local M={}
local function names(text)
  local set={}
  for name in text:gmatch('%S+') do set[name]=true end
  return set
end
M.keywords=names([[
and break do else elseif end false for function goto if in local nil not or
repeat return then true until while
]])
M.builtins=names([[
_G _ENV _VERSION assert collectgarbage dofile error getfenv getmetatable ipairs
load loadfile loadstring module newproxy next pairs pcall print rawequal rawget
rawlen rawset require select setfenv setmetatable tonumber tostring type unpack
warn xpcall arg bit32 coroutine debug io math os package string table utf8
]])
M.ce=names([[
syntaxcheck memrec TrainerOrigin process MainForm AddressList
getCEVersion getCheatEngineFileVersion getOperatingSystem getSystemArchitecture
getCheatEngineDir getAutorunPath getOpenedProcessID getProcessIDFromProcessName
getProcesslist getMainForm getAddressList getLuaEngine
getMemoryViewForm getSettings getTranslationFolder translate translateID
getAddress getAddressSafe getNameFromAddress getModuleSize enumModules
targetIs64Bit targetIsArm openProcess closeCE
pause unpause speedhack_setSpeed speedhack_getSpeed
readBytes readSmallInteger readInteger readQword readPointer readFloat readDouble
readString readBytesLocal readSmallIntegerLocal readIntegerLocal readQwordLocal
readPointerLocal readFloatLocal readDoubleLocal readStringLocal
writeBytes writeSmallInteger writeInteger writeQword writePointer writeFloat
writeDouble writeString writeBytesLocal writeIntegerLocal writeQwordLocal
writeFloatLocal writeDoubleLocal writeStringLocal
allocateMemory deAlloc fullAccess setMemoryProtection getMemoryProtection
copyMemory compareMemory autoAssemble autoAssembleCheck
registerSymbol unregisterSymbol getSymbolInfo reinitializeSymbolhandler
registerAutoAssemblerCommand unregisterAutoAssemblerCommand
registerAutoAssemblerPrologue unregisterAutoAssemblerPrologue
registerSymbolLookupCallback unregisterSymbolLookupCallback
AOBScan AOBScanUnique AOBScanModuleUnique createMemScan createFoundList
disassemble splitDisassembledString getInstructionSize
getPreviousOpcode getVisibleDisassembler
createTimer createThread createNativeThread synchronize sleep getTickCount
createForm createFormFromFile createFormFromStream createPanel createLabel
createButton createCheckBox createEdit createMemo createComboBox createListBox
createListView createTreeView createMenuItem createPopupMenu createMainMenu
createStringlist createMemoryStream createFileStream createStringStream
createOpenDialog createSaveDialog createFont createPicture createImage
showMessage messageDialog inputQuery print executeCode executeCodeEx
executeCodeLocal executeCodeLocalEx shellExecute playSound beep
loadTable saveTable findTableFile createTableFile
isKeyPressed createHotkey getXBox360ControllerState
debug_setBreakpoint debug_removeBreakpoint debug_continueFromBreakpoint
debug_getContext debug_setContext debugProcess debug_isDebugging
vtByte vtWord vtDword vtQword vtSingle vtDouble vtString vtUnicodeString
vtByteArray vtBinary vtAutoAssembler vtPointer vtCustom vtGrouped vtAll
soUnknownValue soExactValue soValueBetween soBiggerThan soSmallerThan
soIncreasedValue soIncreasedValueBy soDecreasedValue soDecreasedValueBy
soChanged soUnchanged rtRounded rtTruncated rtExtremerounded
fsmNotAligned fsmAligned fsmLastDigits caNone caHide caFree caMinimize
mrNone mrOK mrCancel mrAbort mrRetry mrIgnore mrYes mrNo mrAll
mtWarning mtError mtInformation mtConfirmation mbYes mbNo mbOK mbCancel
alNone alTop alBottom alLeft alRight alClient
VK_SHIFT VK_CONTROL VK_MENU VK_SPACE VK_RETURN VK_ESCAPE
VK_F1 VK_F2 VK_F3 VK_F4 VK_F5 VK_F6 VK_F7 VK_F8 VK_F9 VK_F10 VK_F11 VK_F12
]])
function M.excluded(name)
  return M.keywords[name] or M.builtins[name] or M.ce[name]
end
return M
