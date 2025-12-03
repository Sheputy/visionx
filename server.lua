--[[
============================================================
--
--  Author: Corrupt
--  VisionX Builder - Server-Side
--  Version: 3.3.0 (Massive performance overhaul, LOD & FarClip)
--
--  CHANGELOG: (3.2.8 → 3.3.0)
--  - Added builder endpoints for saving generated standalone scripts to map resources.
--  - Centralized default settings and introduced priority categories (Land Masses, Trees, Plants).
--  - Increased default MIN_VIEW_RANGE and tuned LOD handling for large maps.
--  - Added CLONE_LIMIT enforcement and safer save/ACL checks for builder operations.
--  - General performance improvements and XML/group mapping refinements.
--
============================================================
]]

-- ////////////////////////////////////////////////////////////////////////////
-- // SERVER CONFIGURATION & DATA
-- ////////////////////////////////////////////////////////////////////////////

local serverConfig = {
    MAX_VIEW_RANGE = 1000,
    MIN_VIEW_RANGE = 300,
    CREATION_BATCH_LIMIT = 100,
    UPDATE_TICK_RATE = 500,
    SPATIAL_GRID_CELL_SIZE = 200,
    CLONE_LIMIT = 500,
    DEBUG_MODE = false,
    -- [UPDATED] Default Priorities
    PRIORITY_HIGH = "Land Masses",
    PRIORITY_MED = "Trees", -- Updated from Nature
    PRIORITY_LOW = "Plants",
    CUSTOM_PRIORITY_IDS = "",
}

local categoryLookup = {}
local groupTypeRegistry = {}

-- [UPDATED] Mapping XML Groups to Meta Categories
local xmlToMetaGroup = {
    -- Split Nature
    ["Trees"] = "Trees",
    ["Plants"] = "Plants",

    -- Land Masses (Now includes Rocks)
    ["Concrete and Rock"] = "Land Masses",
    ["Grass and Dirt"] = "Land Masses",
    ["Rocks"] = "Land Masses",

    -- Buildings
    ["Factories and Warehouses"] = "Buildings",
    ["Stores and Shops"] = "Buildings",
    ["Graveyard"] = "Buildings",
    ["Houses and Apartments"] = "Buildings",
    ["Offices and Skyscrapers"] = "Buildings",
    ["Other Buildings"] = "Buildings",
    ["Restaurants and Hotels"] = "Buildings",
    ["Sports and Stadium Objects"] = "Buildings",
    ["Bars, Clubs, and Casinos"] = "Buildings",

    -- Industrial
    ["Construction"] = "Industrial",
    ["Cranes"] = "Industrial",
    ["Crates, Drums, and Racks"] = "Industrial",
    ["Food and Drinks"] = "Industrial",
    ["Special"] = "Industrial",
    ["Military"] = "Industrial",
    ["Pickups and Icons"] = "Industrial",

    -- Interior
    ["Bar Items"] = "Interior",
    ["Shop Items"] = "Interior",
    ["Household Items"] = "Interior",
    ["Furniture"] = "Interior",
    ["Trash"] = "Interior",
    ["Casino Items"] = "Interior",
    ["More Interiors"] = "Interior",
    ["Doors and Windows"] = "Interior",
    ["Clothes"] = "Interior",
    ["Car parts"] = "Interior",
    ["Weapon Models"] = "Interior",
    ["Tables and Chairs"] = "Interior",
    ["Alpha Channels and Non Collidable"] = "Interior",
    ["Nighttime Objects"] = "Interior",

    -- Structures
    ["Garages and Petrol Stations"] = "Structures",
    ["Ramps"] = "Structures",
    ["Signs, Billboards, and Statues"] = "Structures",

    -- Infrastructure (Miscellaneous)
    ["Street and Road Items"] = "Infrastructure",
    ["Ladders, Stairs, and Scaffolding"] = "Infrastructure",
    ["Farm Objects"] = "Infrastructure",
    ["Fences, Walls, Gates, and Barriers"] = "Infrastructure",
    ["Wires and Cables"] = "Infrastructure",
    ["Ships, Docks, and Piers"] = "Infrastructure",
    ["General"] = "Infrastructure",

    -- Track
    ["Roads, Bridges, and Tunnels"] = "Track",
    ["Airport and Aircraft Objects"] = "Track",
    ["Railroads"] = "Track",
}

-- Define which Meta Groups are Decoration vs Track
local metaGroupTypes = {
    ["Trees"] = "Decoration",
    ["Plants"] = "Decoration",
    ["Land Masses"] = "Decoration",
    ["Buildings"] = "Decoration",
    ["Industrial"] = "Decoration",
    ["Interior"] = "Decoration",
    ["Structures"] = "Decoration",
    ["Infrastructure"] = "Decoration",
    ["Track"] = "Track",
}

-- ////////////////////////////////////////////////////////////////////////////
-- // CORE SERVER LOGIC
-- ////////////////////////////////////////////////////////////////////////////

function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function buildCategoryLookup()
    outputDebugString("[VisionX] Loading and parsing objects.xml...")
    local xmlFile = xmlLoadFile("objects.xml")
    if not xmlFile then
        outputServerLog(
            "[VisionX] FATAL ERROR: Could not load objects.xml! The resource will not function."
        )
        return
    end

    -- Populate Registry for Client
    for metaName, typeName in pairs(metaGroupTypes) do
        groupTypeRegistry[metaName] = typeName
    end

    local function processNode(node)
        local j = 0
        local objectNode = xmlFindChild(node, "object", j)
        while objectNode do
            local modelID = tonumber(xmlNodeGetAttribute(objectNode, "model"))
            local parentGroup = xmlNodeGetParent(objectNode)
            if modelID and parentGroup then
                local xmlGroupName = xmlNodeGetAttribute(parentGroup, "name")
                local metaCategory = xmlToMetaGroup[xmlGroupName]

                if metaCategory then
                    categoryLookup[modelID] = metaCategory
                end
            end
            j = j + 1
            objectNode = xmlFindChild(node, "object", j)
        end

        local k = 0
        local subGroupNode = xmlFindChild(node, "group", k)
        while subGroupNode do
            processNode(subGroupNode)
            k = k + 1
            subGroupNode = xmlFindChild(node, "group", k)
        end
    end

    processNode(xmlFile)
    xmlUnloadFile(xmlFile)

    -- Manual Overrides (Force specific objects to Track meta-group)
    local trackOverrides = {
        3458,
        8558,
        8838,
        6959,
        7657,
        3095,
        18450,
        2910,
        3437,
        8392,
        9623,
        8357,
        7488,
        3877,
        9282,
        6949,
        18253,
    }
    for _, id in ipairs(trackOverrides) do
        categoryLookup[id] = "Track"
    end

    outputServerLog(
        "[VisionX] Finished building category list. "
            .. table.size(categoryLookup)
            .. " objects categorized."
    )
end

function loadSettings()
    local file = fileOpen("settings.json")
    if file then
        local content = fileRead(file, fileGetSize(file))
        fileClose(file)
        local success, data = pcall(fromJSON, content)
        if success and type(data) == "table" then
            for k, v in pairs(data) do
                serverConfig[k] = v
            end
            outputServerLog("[VisionX] Successfully loaded saved settings.")
        else
            outputServerLog(
                "[VisionX] Could not parse settings.json, using default values."
            )
        end
    else
        outputServerLog(
            "[VisionX] No settings.json found, using default values."
        )
    end
end

-- ////////////////////////////////////////////////////////////////////////////
-- // EVENT HANDLERS
-- ////////////////////////////////////////////////////////////////////////////

addEventHandler("onResourceStart", resourceRoot, function()
    loadSettings()
    buildCategoryLookup()
end)

addEvent("visionx:requestInitialData", true)
addEventHandler("visionx:requestInitialData", root, function()
    local playerAccount = getPlayerAccount(source)
    local isModerator = false
    if not isGuestAccount(playerAccount) then
        isModerator = isObjectInACLGroup(
            "user." .. getAccountName(playerAccount),
            aclGetGroup("Admin")
        ) or isObjectInACLGroup(
            "user." .. getAccountName(playerAccount),
            aclGetGroup("Supermods")
        )
    end

    triggerClientEvent(
        source,
        "visionx:receiveInitialData",
        source,
        categoryLookup,
        serverConfig,
        isModerator,
        groupTypeRegistry
    )
end)

addEvent("visionx:saveSettings", true)
addEventHandler("visionx:saveSettings", root, function(newSettings)
    if type(newSettings) ~= "table" then
        return
    end

    local playerAccount = getPlayerAccount(source)
    local isModerator = false
    if not isGuestAccount(playerAccount) then
        isModerator = isObjectInACLGroup(
            "user." .. getAccountName(playerAccount),
            aclGetGroup("Admin")
        ) or isObjectInACLGroup(
            "user." .. getAccountName(playerAccount),
            aclGetGroup("Supermods")
        )
    end

    if not isModerator then
        triggerClientEvent(
            source,
            "visionx:onSettingsSaved",
            source,
            false,
            "You do not have permission to change global settings."
        )
        return
    end

    serverConfig = newSettings

    local file = fileCreate("settings.json")
    if file then
        fileWrite(file, toJSON(serverConfig, true))
        fileClose(file)
        triggerClientEvent(
            source,
            "visionx:onSettingsSaved",
            source,
            true,
            "Settings saved and applied to all players."
        )
        triggerClientEvent(
            getRootElement(),
            "visionx:syncSettings",
            resourceRoot,
            serverConfig
        )
        outputServerLog(
            "[VisionX] Settings updated and saved by " .. getPlayerName(source)
        )
    else
        triggerClientEvent(
            source,
            "visionx:onSettingsSaved",
            source,
            false,
            "Failed to write settings.json on server."
        )
    end
end)

function getCategoryLookup()
    return categoryLookup
end
