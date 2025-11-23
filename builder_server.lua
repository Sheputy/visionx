--[[
============================================================
--
--  Author: Corrupt
--  VisionX Builder - Server-Side
--  Version: 3.2.3 (Automatic File Saving)
--
--  CHANGELOG:
--  - Standalone Template updated to include /vx and X to disable. (Requested)
--  - Added logic to fetch map resources (`visionx:requestMapResources`).
--  - Modified build handler to automatically write script and update meta.xml.
--  - Requires ACL permission: 'general.ModifyOtherObjects'
--
============================================================
]]

local STANDALONE_SCRIPT_NAME = "visionx_standalone.lua"

---
-- @function getModelIDsForCategories
-- Filters the unique models on the map to get two lists of model IDs:
-- one for the selected category, and one for "OTHER".
---
local function getModelIDsForCategories(category, categoryLookup, uniqueMapModels)
    local includedIDs = {}
    local otherIDs = {}
    if not category or not categoryLookup or not uniqueMapModels then return includedIDs, otherIDs end

    -- Iterate only through the models that actually exist on the map
    for modelId, _ in pairs(uniqueMapModels) do
        local objectCategory = categoryLookup[modelId] or "OTHER"
        
        local shouldInclude = (category == "All" and (objectCategory == "Decoration" or objectCategory == "Track")) or
                              (category == objectCategory)
        
        if shouldInclude then
            table.insert(includedIDs, modelId)
        elseif objectCategory == "OTHER" then
            -- Only add to 'other' list if it wasn't included
            table.insert(otherIDs, modelId)
        end
    end
    return includedIDs, otherIDs
end

---
-- @function formatModelIDTable
-- Formats a Lua table of model IDs into a string for injection into the script template.
---
local function formatModelIDTable(modelIDs, isCommented)
    if #modelIDs == 0 then return "" end
    local parts = {}
    local prefix = isCommented and "--        " or "        "

    for _, id in ipairs(modelIDs) do
        table.insert(parts, string.format("[%d] = true", id))
    end

    local output, line = {}, {}
    for i, part in ipairs(parts) do
        table.insert(line, part)
        -- Format 8 models per line
        if i % 8 == 0 or i == #parts then
            table.insert(output, prefix .. table.concat(line, ", "))
            line = {}
        end
    end
    return table.concat(output, ",\n")
end

---
-- @function generateStandaloneScript
-- Constructs the full standalone script as a string using the new v3.2.3 (Core) template.
---
local function generateStandaloneScript(settings, includedString, otherString)
    -- *** UPDATED TEMPLATE: Added Deactivation Logic ***
    local template = [=[
--[[
============================================================
--
--  VisionX Standalone - Generated for Map Resource
--  Author: Corrupt
--  Version: 3.2.3 (Core Logic + Deactivation)
--
--  This is a self-contained, core-only script. 
--  Includes spatial grid, clone limits, frustum culling,
--  and simple deactivation command.
--
============================================================
]]

-- Helper function
function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

VisionX = {}
VisionX.state = {}
VisionX.timers = {}

-- ////////////////////////////////////////////////////////////////////////////
-- // CONFIGURATION (Generated)
-- ////////////////////////////////////////////////////////////////////////////

VisionX.CONFIG = {
    ENABLED_BY_DEFAULT = true,
    MAX_VIEW_RANGE = %d,
    MIN_VIEW_RANGE = %d,
    CREATION_BATCH_LIMIT = %d,
    UPDATE_TICK_RATE = %d,
    SPATIAL_GRID_CELL_SIZE = %d,
    CLONE_LIMIT = %d, -- ADDED: Hard limit on active clones
    
    -- All object models to be rendered by this script
    TARGET_MODEL_IDS = {
%s
    },
}

--[[
    -- NOTE: The following 'uncategorized' objects were found on your map.
    -- They are NOT being rendered. If they should be, copy them
    -- into the TARGET_MODEL_IDS table above.
%s
--]]

-- ////////////////////////////////////////////////////////////////////////////
-- // INTERNAL STATE
-- ////////////////////////////////////////////////////////////////////////////

VisionX.state = {
    isInitialized = false,
    isEnabled = false,
    objectRegistry = {}, 
    activeClones = {}, 
    spatialGrid = {}, 
    screenWidth = 0, 
    screenHeight = 0,
}

-- ////////////////////////////////////////////////////////////////////////////
-- // CORE LOGIC
-- ////////////////////////////////////////////////////////////////////////////

-- Performs the initial scan of all map objects to build a targeted cache.
function VisionX:_BuildObjectRegistry()
    self.state.objectRegistry = {}
    local allGameObjects = getElementsByType("object")
    local playerDimension = getElementDimension(localPlayer)

    for _, entity in ipairs(allGameObjects) do
        local modelId = getElementModel(entity)
        -- Check if model is in our target list and not a clone
        if self.CONFIG.TARGET_MODEL_IDS[modelId] and not getElementData(entity, "visionx_clone") and getElementDimension(entity) == playerDimension then
            
            local scale = getObjectScale(entity)
            local alpha = getElementAlpha(entity)
            
            if (scale >= 0.1 and scale <= 400) and (alpha >= 50) then
                local pX, pY, pZ = getElementPosition(entity)
                local rX, rY, rZ = getElementRotation(entity)
                self.state.objectRegistry[entity] = {
                    model = modelId,
                    pos = { pX, pY, pZ },
                    rot = { rX, rY, rZ },
                    scale = scale, 
                    dimension = getElementDimension(entity),
                    interior = getElementInterior(entity)
                }
            end
        end
    end
end

-- Builds the spatial grid from the targeted object registry.
function VisionX:_BuildSpatialGrid()
    self.state.spatialGrid = {}
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    if not cellSize or cellSize <= 0 then cellSize = 250 end -- Safety check

    for entity, data in pairs(self.state.objectRegistry) do
        local gridX = math.floor(data.pos[1] / cellSize)
        local gridY = math.floor(data.pos[2] / cellSize)
        local key = gridX .. "_" .. gridY
        if not self.state.spatialGrid[key] then
            self.state.spatialGrid[key] = {}
        end
        table.insert(self.state.spatialGrid[key], entity)
    end
end

-- Destroys all active clone objects.
function VisionX:_PurgeAllClones()
    for _, cloneInstance in pairs(self.state.activeClones) do
        if isElement(cloneInstance) then destroyElement(cloneInstance) end
    end
    self.state.activeClones = {}
end

-- Culling Logic: Removes clones that are too close, too far, or invalid.
function VisionX:_PerformCullingLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local clonesToCull = {}
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE

    for sourceElement, cloneInstance in pairs(self.state.activeClones) do
        if not isElement(sourceElement) or not isElement(cloneInstance) then
            table.insert(clonesToCull, sourceElement)
        else
            local sourceData = self.state.objectRegistry[sourceElement]
            if not sourceData or sourceData.dimension ~= playerDim then
                table.insert(clonesToCull, sourceElement)
            else
                local dx, dy, dz = sourceData.pos[1] - camX, sourceData.pos[2] - camY, sourceData.pos[3] - camZ
                local distSq = dx*dx + dy*dy + dz*dz
                
                -- Cull if too close or too far
                if distSq < minRangeSq or distSq > maxRangeSq then
                    table.insert(clonesToCull, sourceElement)
                end
            end
        end
    end

    for _, sourceElement in ipairs(clonesToCull) do
        local cloneInstance = self.state.activeClones[sourceElement]
        if isElement(cloneInstance) then destroyElement(cloneInstance) end
        self.state.activeClones[sourceElement] = nil
    end
end

-- Spawning Logic: Creates new clones for objects that enter the view range.
function VisionX:_PerformSpawningLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local createdThisCycle = 0
    
    local currentCloneCount = table.size(self.state.activeClones)
    if currentCloneCount >= self.CONFIG.CLONE_LIMIT then
        return -- Hard stop, we are at or over the limit
    end
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    
    local searchRadius = math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)
    local pGridX = math.floor(camX / cellSize)
    local pGridY = math.floor(camY / cellSize)
    
    -- Get screen size once for frustum culling
    local screenWidth, screenHeight = self.state.screenWidth, self.state.screenHeight
    local screenBuffer = 200 -- Spawn objects 200px off-screen to avoid "pop-in"
    
    for i = -searchRadius, searchRadius do
        for j = -searchRadius, searchRadius do
            local key = (pGridX + i) .. "_" .. (pGridY + j)
            if self.state.spatialGrid[key] then
                for _, sourceElement in ipairs(self.state.spatialGrid[key]) do
                    -- Check batch limit
                    if createdThisCycle >= self.CONFIG.CREATION_BATCH_LIMIT then return end
                    
                    -- Check if adding this clone would exceed the limit
                    if (currentCloneCount + createdThisCycle) >= self.CONFIG.CLONE_LIMIT then
                        return -- Stop spawning this cycle
                    end
                    
                    local data = self.state.objectRegistry[sourceElement]
                    if data and not self.state.activeClones[sourceElement] and data.dimension == playerDim then
                        local dx, dy, dz = data.pos[1] - camX, data.pos[2] - camY, data.pos[3] - camZ
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq >= minRangeSq and distSq <= maxRangeSq then
                            
                            -- Stricter frustum culling logic
                            local sX, sY = getScreenFromWorldPosition(data.pos[1], data.pos[2], data.pos[3])
                            
                            if sX and sY and 
                               sX >= -screenBuffer and sX <= screenWidth + screenBuffer and
                               sY >= -screenBuffer and sY <= screenHeight + screenBuffer then
                                
                                local newClone = createObject(data.model, data.pos[1], data.pos[2], data.pos[3], data.rot[1], data.rot[2], data.rot[3], true)
                                setElementDimension(newClone, data.dimension)
                                setElementInterior(newClone, data.interior)
                                setObjectScale(newClone, data.scale)
                                setElementData(newClone, "visionx_clone", true, false)
                                self.state.activeClones[sourceElement] = newClone
                                createdThisCycle = createdThisCycle + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

function VisionX:Activate()
    if self.state.isEnabled then return end
    self.state.isEnabled = true

    self:_BuildObjectRegistry()
    self:_BuildSpatialGrid()
    self:_PerformSpawningLogic() -- Run once immediately

    -- Set LOD for targeted models (Assumes target models are loaded)
    for modelId, _ in pairs(self.CONFIG.TARGET_MODEL_IDS) do
        engineSetModelLODDistance(modelId, self.CONFIG.MIN_VIEW_RANGE)
    end
    
    -- Start the main update loops.
    self.timers.spawn = setTimer(function() self:_PerformSpawningLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    self.timers.cullDelay = setTimer(function()
        self.timers.cull = setTimer(function() self:_PerformCullingLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
    
    outputChatBox("[VisionX Standalone] Activated. Clones: " .. table.size(self.state.activeClones), 255, 255, 255)
end

function VisionX:Deactivate()
    if not self.state.isEnabled then return end
    self.state.isEnabled = false
    
    for _, timer in pairs(self.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    self.timers = {}
    
    self:_PurgeAllClones()
    outputChatBox("[VisionX Standalone] Deactivated. All clones destroyed.", 255, 255, 255)
    
    -- Reset LOD for targeted models to default 1000
    for modelId, _ in pairs(self.CONFIG.TARGET_MODEL_IDS) do
        engineSetModelLODDistance(modelId, 1000)
    end
end

function VisionX:Initialize()
    if self.state.isInitialized then return end
    self.state.isInitialized = true
    
    -- Get initial screen size and set up handler (required for frustum culling)
    local sx, sy = guiGetScreenSize()
    self.state.screenWidth = sx
    self.state.screenHeight = sy
    
    addEventHandler("onClientScreenSizeChange", root,
        function (width, height)
            VisionX.state.screenWidth = width
            VisionX.state.screenHeight = height
        end
    )
    
    -- ADDED: Simple Deactivation Commands
    addCommandHandler("vx", function(cmd, arg)
        if string.lower(arg or "") == "off" then
            VisionX:Deactivate()
        elseif string.lower(arg or "") == "on" then
            VisionX:Activate()
        else
            outputChatBox("Usage: /vx [on|off]", 255, 255, 255)
        end
    end)
    
    -- ADDED: Keybind 'X' to toggle (Must only be used in standalone!)
    bindKey("x", "down", function()
        if isChatBoxInputActive() or isConsoleActive() then return end
        if VisionX.state.isEnabled then
            VisionX:Deactivate()
        else
            VisionX:Activate()
        end
    end)
    
    if self.CONFIG.ENABLED_BY_DEFAULT then
        self:Activate()
    end
    
    -- Refresh if player streams back in (e.g., changing dimension)
    addEventHandler("onClientPlayerStreamIn", root, function()
        if source == localPlayer and VisionX.state.isEnabled then
            VisionX:Deactivate()
            VisionX:Activate()
        end
    end)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // AUTO-START
-- ////////////////////////////////////////////////////////////////////////////
addEventHandler("onClientResourceStart", resourceRoot, function() VisionX:Initialize() end)
addEventHandler("onClientResourceStop", resourceRoot, function() VisionX:Deactivate() end)
]=]

    -- Inject user settings from the builder UI into the template string
    return string.format(template,
        settings.MAX_VIEW_RANGE,
        settings.MIN_VIEW_RANGE,
        settings.CREATION_BATCH_LIMIT,
        settings.UPDATE_TICK_RATE,
        settings.SPATIAL_GRID_CELL_SIZE,
        settings.CLONE_LIMIT,
        includedString,
        otherString
    )
end


-- ////////////////////////////////////////////////////////////////////////////
-- // SERVER EVENT HANDLERS (for Map Selection and Script Saving)
-- ////////////////////////////////////////////////////////////////////////////

-- ADDED: Handler to fetch map resources
addEvent("visionx:requestMapResources", true)
addEventHandler("visionx:requestMapResources", root, function()
    local map_resources = {}
    for _, resource in pairs(getResources()) do
        local name = getResourceName(resource) 
        -- Only send back resources explicitly marked as type "map"
        if name and getResourceInfo(resource,"type") == "map" then 
            table.insert(map_resources, name) 
        end
    end
    triggerClientEvent(source, "visionx:receiveMapResources", source, map_resources)
end)


-- MODIFIED: buildScript now handles file I/O for automatic saving
addEvent("visionx:buildScript", true)
addEventHandler("visionx:buildScript", root, function(settings, category, uniqueMapModels, mapName)
    local player = source
    local thisResource = getThisResource()
    local thisResourceName = getResourceName(thisResource)

    -- ** ACL CHECK for file modification **
    if not hasObjectPermissionTo(thisResource,"general.ModifyOtherObjects") then
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Permission denied. The VisionX resource needs 'general.ModifyOtherObjects' ACL permission to save files.")
        return
    end
    
    -- 1. Get the Category Lookup from the Core Server file
    if not exports[thisResourceName] or not exports[thisResourceName].getCategoryLookup then
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Could not find exported functions. Builder script is not correctly set up.")
        return
    end

    local categoryLookup = exports[thisResourceName]:getCategoryLookup()
    if not categoryLookup or type(categoryLookup) ~= "table" then
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Could not retrieve valid category data from the main resource.")
        return
    end

    -- 2. Generate the Code
    local includedIDs, otherIDs = getModelIDsForCategories(category, categoryLookup, uniqueMapModels)
    local includedString = formatModelIDTable(includedIDs, false)
    local otherString = formatModelIDTable(otherIDs, true)
    local generatedCode = generateStandaloneScript(settings, includedString, otherString)

    -- 3. Save the File (Using robust append logic, similar to user example's intent)
    local scriptPath = ":" .. mapName .. "/" .. STANDALONE_SCRIPT_NAME
    local fScript

    if not fileExists(scriptPath) then
        fScript = fileCreate(scriptPath)
    else
        fScript = fileOpen(scriptPath, "a") -- Open in append mode
    end
    
    if not fScript then
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Failed to create or open file: '" .. STANDALONE_SCRIPT_NAME .. "'. Check map resource folder existence/permissions.")
        return
    end
    
    fileWrite(fScript, "\n\n--[[ === VisionX Standalone Script Start | " .. getRealTime().." === ]] \n\n" .. generatedCode)
    fileClose(fScript)


    -- 4. Update meta.xml
    local xmlPath = ":" .. mapName .. "/meta.xml"
    local xml = xmlLoadFile(xmlPath)
    local metaUpdated = false

    if xml then
        local metaNodes = xmlNodeGetChildren(xml) 
        
        -- Check if script node already exists
        for i, node in ipairs(metaNodes) do
            if xmlNodeGetName(node) == "script" and xmlNodeGetAttribute(node, "src") == STANDALONE_SCRIPT_NAME then
                metaUpdated = true -- Already in meta, no need to add.
                break
            end
        end

        if not metaUpdated then
            local child = xmlCreateChild(xml, "script")
            xmlNodeSetAttribute(child, "src", STANDALONE_SCRIPT_NAME)
            xmlNodeSetAttribute(child, "type", "client")
            
            if xmlSaveFile(xml) then
                metaUpdated = true
            else
                triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Failed to save/update '" .. mapName .. "/meta.xml'.")
                return
            end
        end
        xmlUnloadFile(xml)

        -- 5. Final Success message
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, true, mapName, "Script saved and meta updated.")
    else
        triggerClientEvent(player, "visionx:receiveGeneratedScript", player, false, mapName, "Unable to load '" .. mapName .. "/meta.xml'. Make sure it exists in the map folder.")
    end
end)