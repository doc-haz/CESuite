-- Evidence metadata only: no CE API calls, capability detection or source execution.
local U=require('util')
local M={}
function M.profile(ce_version)
  local function note(id,version,feature)
    return {id=id,version=version,feature=feature,
      evidence_kind='release_note_evidence',evidence_ref='user-chronology/'..version,
      runtime_validation='not_performed'}
  end
  return {
    profile_version='1',profile_id='ce-public-ec45d5f-to-runtime-r1',
    source_profile={repository='https://github.com/cheat-engine/cheat-engine',
      commit='ec45d5f47f92a239ba0bf51ec5d04a7509c3fd37',
      version_label='7.5.1 public-source baseline',version_label_basis='research_context_not_binary_identity'},
    runtime_profile={declared_version=U.null,declared_version_basis='not_available',
      api_version=ce_version,file_version=U.null,binary_sha256=U.null},
    source_runtime_equivalence='unverified',
    known_post_source_changes=U.array({
      note('luacode-no-dll-injection','7.5.2','LuaCode no longer requires DLL injection.'),
      note('globalalloc-save','7.6.1','Globalalloc symbols are no longer saved in tables.'),
      note('aa-conditionals-aob','7.6.2','IFDEF/IFNDEF/ENDIF conditionals also apply to AOB scans.'),
      note('aa-hook-unhook','7.6.3','HOOK/UNHOOK commands introduced.'),
      note('aobscanex-executable-fix','7.7.1','Fix for AOBSCANEX not being restricted to executable memory.'),
      note('async-thread-ondestroy','7.7.1','OnDestroy for the asynchronous Memory Record thread.')
    })
  }
end
return M
