{$lua}
if syntaxcheck then return end

local tbl = Register.createSectionTable('$process')
local start, size = Register.getSectionRegion(tbl)

local prior = {
    ['Add Unreal Engine Menu'] = {
        {(type(LaunchUEInfoScanner) == "function") and start}
    },
    ['Required.getGEngine'] = {
        {'write_GEngine', UE.Sig.GEnigne[2], 1, start, size}
    },
    ['Required.getNamePoolData'] = {
        {'read_NamePoolData', UE.Sig.FName, 1, start, size}
    },
    ['Required.getGUObjectArray'] = {
        {'write_GUObjectArray', UE.Sig.GUObjectArray, 1, start, size}
    },
    ['Required.getInventoryForSafety'] = {
        {'read_inventory', '48xxxxxxxxxxxx48xxxxxxxxxxxx48xxxxxx48xxxx74xx39xx74xx48xxxxxx48xxxx75xx33', 1, start, size}
    }
}

local DhaosCollider = {
    ['Required.parseFNamePool'] = {
        {'read_NamePoolData'}
    },
    ['Required.addressUpdate'] = {
        {'write_GEngine'}
    },
    ['Required.initbIsKnown'] = {
        {'write_bIsKnown', '41890A0FB70266418942xx0FB6', 1, start, size}
    },
    ['Save Anywhere'] = {
        {'trace_VM_SystemMenu', '84C074xxB301EBxx807C24xx00', 1, start, size}
    },
    ['Encounter Multiplier'] = {
        {'trace_IsEncountIsMovie', '0F28BC24xxxxxxxxF30F5CC8410F2FC9', 1, start, size}
    },
    ['Movement Speed Multiplier'] = {
        {'write_walkSpeed', '0FB6xxxxxxxxxx3C0175xxF3xxxxxxxxxxxxxxF3', 1, start, size}
    },
    ['Ignore MP Costs'] = {
        {'trace_mp', '8Bxxxxxxxxxx85xx74xx66xxxxxx0F5BxxF3xxxxxxF3', 1, start, size}
    },
    ['Always Critical Hits'] = {
        {'trace_criticalDamageMagnification', 'F341xxxxxx0F2Fxx0F93xxEB', 1, start, size}
    },
    ['Instant Stagger'] = {
        {'trace_Breakpoint', '0F4Fxx48xxxxxx5FC3CCCC48', 1, start, size}
    },
    ['Instant Limit Bursts'] = {
        {'write_LimitBurstPoint', '440F4CC733xx45', 1, start, size}
    },
    ['Auto Libra'] = {
        {'read_IsAnalyzed',      '0FB6xx0448xxxxxx5BC3CC48',                                 1, start, size},
        {'read_analyzedElments', '0FB60048xxxxxxxx48xxxxxx5FC3CCCCCCCCCCCCCCCCCCCCCCCCCC48', 1, start, size}
    },
    ['Guaranteed Steal'] = {
        {'trace_StealItemRate1',  '76xxB00148xxxxxxxx48xxxxxxxx48xxxxxx5EC345', 1, start, size}
    },
    ['Prioritize Rare Steals'] = {
        {'trace_StealItemRate2', '83F9FF75xx8BC8E9', 1, start, size}
    },
    ['Damage Multiplier'] = {
        {'read_DamageTakenRate', 'F30F10401848xxxxxxC3CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC48', 1, start, size},
        {'read_DamageGivenRate', 'F30F10401C48xxxxxxC3',                                 1, start, size}
    },
    ['Always Drop Items'] = {
        {'trace_result_size', '0F2Fxx77xx49xxxxxx48xxxxxxxxxxxx8Bxxxxxxxxxx4C', 1, start, size}
    },
    ['EXP Multiplier'] = {
        {'read_ExpRate', 'F30F10402048xxxxxxC3', 1, start, size}
    },
    ['Money Multiplier'] = {
        {'read_MoneyRate', 'F30F10402448xxxxxxC3', 1, start, size}
    },
    ['MRP Multiplier'] = {
        {'read_MRPointRate', 'F30F10402848xxxxxxC3', 1, start, size}
    },
    ['Fast Travel Anywhere'] = {
        {'read_FastTravelMapTypeEnableMap', '440FB601EBxxCC', 1, start, size}
    },
    ['Reveal Map'] = {
        {'trace_bIsKnown', '894C24xx534883ECxxE8xxxxxxxx4885C0', 1, start, size}
    },
    ['Unit Parameter List'] = {
        {'write_GEngine'}
    },
    ['Inventory List'] = {
        {'write_GEngine'}
    },
    ['Save Data List'] = {
        {'write_GEngine'}
    },
    ['Give Item'] = {
        {'write_GEngine'},
        {'func_give_item', '48895C24xx574883ECxx8BDA8BF9E8xxxxxxxx8BCF8D1418', 1, start, size}
    },
    ['Give Items'] = {
        {'write_GEngine'},
        {'func_give_item', '48895C24xx574883ECxx8BDA8BF9E8xxxxxxxx8BCF8D1418', 1, start, size}
    },
    ['Give Vision'] = {
        {'write_GEngine'},
        {'func_give_vision', '4C8BDC49895Bxx55498D6Bxx4881ECxxxxxxxx488B05xxxxxxxx4833C4488945xx8B', 1, start, size}
    },
    ['Minimize Shop Prices'] = {
        {'read_buyingPrice', '88xxxx8Bxxxx89xxxx8Bxxxx89xxxx0FB6xxxx88xxxx48xxxx48xxxxxxxx48xxxxxx5FC3CCCCCCCC48', 1, start, size}
    },
    ['Easy Quest Requirements'] = {
        {'read_DeliveryQuantity', '7Dxx4883C1xx483BCA75xx32DB', 1, start, size}
    },
    ['Dropdown.MergeItems'] = {
        {'write_GEngine'}
    },
    ['Dropdown.MAP_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.SKILL_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.PASSIVE_SKILL_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.CONSUMABLES_ITEM_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.VALUABLE_ITEM_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.EQUIPMENT_ITEM_DATA'] = {
        {'write_GEngine'}
    },
    ['Dropdown.UNIT_PARAMETER'] = {
        {'write_GEngine'}
    },
    ['Dropdown.VISION_ITEM_DATA'] = {
        {'write_GEngine'}
    },
    ['Reserved.outputWorldCPPs'] = {
        {'write_GEngine'}
    },
    ['Reserved.outputGameInstanceCPPs'] = {
        {'write_GEngine'}
    },
    ['Reserved.outputDataTable'] = {
        {'write_GEngine'}
    },
    ['Reserved.PlayerOrEnemy'] = {
        {'func_player_or_enemy', '0FB681xxxxxxxxC3CCCCCCCCCCCCCCCC488991', 1, start, size}
    },
    ['Reserved.getCPP_VM_SystemMenu'] = {
        {'arg_CPP_VM_SystemMenu', '48895C24xx48897C24xx55488DAC24xxxxxxxx4881ECxxxxxxxx488B05xxxxxxxx4833C4488985xxxxxxxx488B41', 1, start, size}
    }
}

local mr = {
    Register.getRecordByKey("Required.allocation"),
    Register.getRecordByKey("Required.isAttached"),
    Register.getRecordByKey("Required.getGEngine"),
    Register.getRecordByKey("Required.getNamePoolData"),
    Register.getRecordByKey("Required.getGUObjectArray"),
    Register.getRecordByKey("Required.getInventoryForSafety"),
    Register.getRecordByKey("Required.parseFNamePool"),
    Register.getRecordByKey("Required.addressUpdate"),
    Register.getRecordByKey("Dropdown.MergeItems"),
    Register.getRecordByKey("Dropdown.MAP_DATA"),
    Register.getRecordByKey("Dropdown.UNIT_PARAMETER")
}

[ENABLE]

Register.log(process..tbl[1].Name..' section MD5: '..md5memory(start, size))
Register.allocateNearThisAddress = getAddress(start)
Register.onEnable(prior, DhaosCollider)
Register.enableMemoryRecords(mr)
Register.getRecordByKey(1).active  = true
Register.getRecordByKey(20).active = true
Register.getRecordByKey(21).active = true
memrec.color = Register.enabledColor

[DISABLE]

Register.disableMemoryRecords(Register.addEnableList(mr))
Register.onDisable(prior, DhaosCollider)
memrec.color = Register.disabledColor
