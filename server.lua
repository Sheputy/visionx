--[[
============================================================
--
--  Author: Corrupt
--  VisionX Advanced - Server-Side Logic
--  Version: 3.2.0
--  Handles settings persistence and object categorization.
--
============================================================
]]

-- ////////////////////////////////////////////////////////////////////////////
-- // SERVER CONFIGURATION & DATA
-- ////////////////////////////////////////////////////////////////////////////

-- Default settings, used if settings.json is missing or corrupt.
local serverConfig = {
    MAX_VIEW_RANGE = 1000,
    MIN_VIEW_RANGE = 250,
    CREATION_BATCH_LIMIT = 100,
    UPDATE_TICK_RATE = 500,
    SPATIAL_GRID_CELL_SIZE = 200,
    DEBUG_MODE = false,
}


local categoryLookup = {}
local decorationGroups = {
    -- From "Beach and Sea"
    ["Ships, Docks, and Piers"] = true, ["General"] = true,
    -- From "buildings"
    ["Factories and Warehouses"] = true, ["Stores and Shops"] = true, ["Graveyard"] = true,
    ["Houses and Apartments"] = true, ["Offices and Skyscrapers"] = true, ["Other Buildings"] = true,
    ["Restaurants and Hotels"] = true, ["Sports and Stadium Objects"] = true, ["Bars, Clubs, and Casinos"] = true,
    -- From "industrial"
    ["Construction"] = true, ["Cranes"] = true, ["Crates, Drums, and Racks"] = true, ["Food and Drinks"] = true, ["Special"] = true, ["Military"] = true, ["Pickups and Icons"] = true,
    -- From "interior objects"
    ["Bar Items"] = true, ["Shop Items"] = true, ["Household Items"] = true, ["Furniture"] = true, ["Trash"] = true,
    ["Casino Items"] = true, ["More Interiors"] = true, ["Doors and Windows"] = true, ["Clothes"] = true, ["Car parts"] = true, ["Weapon Models"] = true,
    ["Tables and Chairs"] = true, ["Alpha Channels and Non Collidable"] = true, ["Nighttime Objects"] = true,
    -- From "land masses"
    ["Concrete and Rock"] = true, ["Grass and Dirt"] = true,
    -- From "nature"
    ["Rocks"] = true, ["Trees"] = true, ["Plants"] = true,
    -- From "structures"
    ["Garages and Petrol Stations"] = true, ["Ramps"] = true, ["Signs, Billboards, and Statues"] = true,
    -- From "miscellaneous"
    ["Street and Road Items"] = true, ["Military"] = true, ["Ladders, Stairs, and Scaffolding"] = true, ["Farm Objects"] = true, ["Fences, Walls, Gates, and Barriers"] = true,
    -- From "Wires and Cables"
    ["Wires and Cables"] = true,
}
local trackGroups = {
    ["Roads, Bridges, and Tunnels"] = true, ["Airport and Aircraft Objects"] = true, ["Railroads"] = true,
}

-- ////////////////////////////////////////////////////////////////////////////
-- // CORE SERVER LOGIC
-- ////////////////////////////////////////////////////////////////////////////

---
-- @function table.size
-- Helper to get the count of key-value pairs in a table.
---
function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end


---
-- @function buildCategoryLookup
-- Loads objects.xml and categorizes every model ID into Decoration, Track, or OTHER.
-- This is a heavy one-time operation on server start.
---
function buildCategoryLookup()
    outputDebugString("[VisionX] Loading and parsing objects.xml...")
    local xmlFile = xmlLoadFile("objects.xml")
    if not xmlFile then
        outputServerLog("[VisionX] FATAL ERROR: Could not load objects.xml! The resource will not function.")
        return
    end

    local function processNode(node)
        -- Process objects in the current group
        local j = 0
        local objectNode = xmlFindChild(node, "object", j)
        while objectNode do
            local modelID = tonumber(xmlNodeGetAttribute(objectNode, "model"))
            local parentGroup = xmlNodeGetParent(objectNode)
            if modelID and parentGroup then
                local groupName = xmlNodeGetAttribute(parentGroup, "name")
                if decorationGroups[groupName] then
                    categoryLookup[modelID] = "Decoration"
                elseif trackGroups[groupName] then
                    categoryLookup[modelID] = "Track"
                end
            end
            j = j + 1
            objectNode = xmlFindChild(node, "object", j)
        end
        
        -- Recurse into subgroups
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

    -- Force-categorize specific custom/problematic objects
    categoryLookup[3458] = "Track"; categoryLookup[8558] = "Track"; categoryLookup[8838] = "Track";
    categoryLookup[6959] = "Track"; categoryLookup[7657] = "Track"; categoryLookup[3095] = "Track";
    categoryLookup[18450] = "Track"; categoryLookup[2910] = "Track"; categoryLookup[3437] = "Track";
    categoryLookup[8392] = "Track"; categoryLookup[9623] = "Track"; categoryLookup[8357] = "Track";
    categoryLookup[7488] = "Track"; categoryLookup[3877] = "Track"; categoryLookup[9282] = "Track";
    categoryLookup[6949] = "Track"; categoryLookup[18253] = "Track";

    categoryLookup[10444] = "Decoration"; categoryLookup[7916] = "Decoration"; categoryLookup[852] = "Decoration";
    categoryLookup[16135] = "Decoration"; categoryLookup[4206] = "Decoration"; categoryLookup[3276] = "Decoration";
    categoryLookup[1408] = "Decoration"; categoryLookup[3260] = "Decoration"; categoryLookup[1446] = "Decoration";
    categoryLookup[7423] = "Decoration";
    
    outputServerLog("[VisionX] Finished building category list. " .. table.size(categoryLookup) .. " objects categorized.")
end

---
-- @function loadSettings
-- Loads the saved settings from a JSON file on resource start.
---
function loadSettings()
    local file = fileOpen("settings.json")
    if file then
        local content = fileRead(file, fileGetSize(file))
        fileClose(file)
        local success, data = pcall(fromJSON, content)
        if success and type(data) == "table" then
            serverConfig = data
            outputServerLog("[VisionX] Successfully loaded saved settings from settings.json")
        else
            outputServerLog("[VisionX] Could not parse settings.json, using default values.")
        end
    else
        outputServerLog("[VisionX] No settings.json found, using default values.")
    end
end

-- ////////////////////////////////////////////////////////////////////////////
-- // EVENT HANDLERS
-- ////////////////////////////////////////////////////////////////////////////

-- On resource start, load data.
addEventHandler("onResourceStart", resourceRoot,
    function()
        loadSettings()
        buildCategoryLookup()
    end
)

-- When a player's client starts the resource, send them all necessary data.
addEvent("visionx:requestInitialData", true)
addEventHandler("visionx:requestInitialData", root,
    function()
        -- Check if the player is an admin or supermod
        local playerAccount = getPlayerAccount(source)
        local isModerator = false
        if not isGuestAccount(playerAccount) then
            isModerator = isObjectInACLGroup("user." .. getAccountName(playerAccount), aclGetGroup("Admin")) or
                          isObjectInACLGroup("user." .. getAccountName(playerAccount), aclGetGroup("Supermods"))
        end
        
        -- Send categories, server settings, and the player's admin status
        triggerClientEvent(source, "visionx:receiveInitialData", source, categoryLookup, serverConfig, isModerator)
    end
)

-- When a player saves their settings via the UI.
addEvent("visionx:saveSettings", true)
addEventHandler("visionx:saveSettings", root,
    function(newSettings)
        if type(newSettings) ~= "table" then return end

        -- ** ACL CHECK **
        local playerAccount = getPlayerAccount(source)
        local isModerator = false
        if not isGuestAccount(playerAccount) then
            isModerator = isObjectInACLGroup("user." .. getAccountName(playerAccount), aclGetGroup("Admin")) or
                          isObjectInACLGroup("user." .. getAccountName(playerAccount), aclGetGroup("Supermods"))
        end

        if not isModerator then
            triggerClientEvent(source, "visionx:onSettingsSaved", source, false, "You do not have permission to change global settings.")
            return
        end
        
        serverConfig = newSettings
        
        -- Save the settings to file
        local file = fileCreate("settings.json")
        if file then
            fileWrite(file, toJSON(serverConfig, true))
            fileClose(file)
            
            -- Inform the source player of success
            triggerClientEvent(source, "visionx:onSettingsSaved", source, true, "Settings saved and applied to all players.")
            
            -- Sync the new settings with ALL players
            triggerClientEvent(getRootElement(), "visionx:syncSettings", resourceRoot, serverConfig)
            outputServerLog("[VisionX] Settings updated and saved by " .. getPlayerName(source))
        else
            -- Inform the source player of failure
            triggerClientEvent(source, "visionx:onSettingsSaved", source, false, "Failed to write settings.json on server.")
            outputServerLog("[VisionX] ERROR: Could not create or write to settings.json.")
        end
    end
)

-- ////////////////////////////////////////////////////////////////////////////
-- // EXPORTED FUNCTIONS (for other resources)
-- ////////////////////////////////////////////////////////////////////////////

function getCategoryLookup()
    return categoryLookup
end
