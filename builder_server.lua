--[[
============================================================
--
--  Author: Corrupt
--  VisionX Builder - Server-Side
--  Version: 3.2.4 (Fixed Githup Auto Updater)
--
--  CHANGELOG:
--  - Standalone Template updated to include /vx and X to disable. (Requested)
--  - Added Startup Notification DX Text to Standalone (Center-Up position).
--  - Added logic to fetch map resources (`visionx:requestMapResources`).
--  - Modified build handler to automatically write script and update meta.xml.
--  - Requires ACL permission: 'general.ModifyOtherObjects'
--
============================================================
]]

-- ////////////////////////////////////////////////////////////////////////////
-- // 1. MAP MANAGEMENT & SAVING LOGIC
-- ////////////////////////////////////////////////////////////////////////////

addEvent("visionx:requestMapList", true)
addEventHandler("visionx:requestMapList", root, function()
    local mapResources = {}
    for _, res in ipairs(getResources()) do
        if getResourceInfo(res, "type") == "map" then
            table.insert(mapResources, getResourceName(res))
        end
    end
    table.sort(mapResources)
    triggerClientEvent(source, "visionx:receiveMapList", source, mapResources)
end)

addEvent("visionx:saveToMap", true)
addEventHandler("visionx:saveToMap", root, function(mapName, scriptContent)
    -- ACL Check
    if not hasObjectPermissionTo(getThisResource(), "general.ModifyOtherObjects") then
        triggerClientEvent(source, "visionx:onSaveResult", source, false, "VisionX needs Admin rights (ACL) to modify maps.")
        return
    end

    local res = getResourceFromName(mapName)
    if not res then
        triggerClientEvent(source, "visionx:onSaveResult", source, false, "Map resource not found.")
        return
    end

    local fileName = "visionx_client.lua"
    local filePath = ":" .. mapName .. "/" .. fileName

    -- 1. Create/Overwrite the Lua file
    local file = fileCreate(filePath)
    if not file then
        triggerClientEvent(source, "visionx:onSaveResult", source, false, "Could not create file in map folder.")
        return
    end
    fileWrite(file, scriptContent)
    fileClose(file)

    -- 2. Update meta.xml
    local metaPath = ":" .. mapName .. "/meta.xml"
    local xml = xmlLoadFile(metaPath)
    if not xml then
        triggerClientEvent(source, "visionx:onSaveResult", source, false, "Could not load map's meta.xml.")
        return
    end

    local scriptExists = false
    local children = xmlNodeGetChildren(xml)
    for _, node in ipairs(children) do
        if xmlNodeGetName(node) == "script" and xmlNodeGetAttribute(node, "src") == fileName then
            scriptExists = true
            break
        end
    end

    if not scriptExists then
        local child = xmlCreateChild(xml, "script")
        xmlNodeSetAttribute(child, "src", fileName)
        xmlNodeSetAttribute(child, "type", "client")
        xmlSaveFile(xml)
    end
    xmlUnloadFile(xml)

    triggerClientEvent(source, "visionx:onSaveResult", source, true, "Successfully saved to '" .. mapName .. "'!")
    outputServerLog("[VisionX] Injected standalone script into " .. mapName .. " by " .. getPlayerName(source))
end)

-- ////////////////////////////////////////////////////////////////////////////
-- // 2. TEMPLATE GENERATION
-- ////////////////////////////////////////////////////////////////////////////

local function getModelIDsForCategories(category, categoryLookup, uniqueMapModels)
    local includedIDs, otherIDs = {}, {}
    if not category or not categoryLookup or not uniqueMapModels then return includedIDs, otherIDs end

    for modelId, _ in pairs(uniqueMapModels) do
        local objectCategory = categoryLookup[modelId] or "OTHER"
        local shouldInclude = (category == "All" and (objectCategory == "Decoration" or objectCategory == "Track")) or
                              (category == objectCategory)
        
        if shouldInclude then table.insert(includedIDs, modelId)
        elseif objectCategory == "OTHER" then table.insert(otherIDs, modelId) end
    end
    return includedIDs, otherIDs
end

local function formatModelIDTable(modelIDs, isCommented)
    if #modelIDs == 0 then return "" end
    local parts = {}
    local prefix = isCommented and "--      " or "        "
    for _, id in ipairs(modelIDs) do table.insert(parts, string.format("[%d] = true", id)) end
    local output, line = {}, {}
    for i, part in ipairs(parts) do
        table.insert(line, part)
        if i % 8 == 0 or i == #parts then
            table.insert(output, prefix .. table.concat(line, ", "))
            line = {}
        end
    end
    return table.concat(output, ",\n")
end

local function generateStandaloneScript(settings, includedString, otherString)
    local template = [=[
--[[
============================================================
--
--  VisionX Standalone - Generated for Map Resource
--  Author: Corrupt
--  Version: 3.2.4 (Core Logic + Startup Info)
--
--  This is a self-contained, core-only script. 
--  It includes spatial grid, clone limits, and
--  frustum culling logic for performance.
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
-- // CONFIGURATION & PRESETS
-- ////////////////////////////////////////////////////////////////////////////

-- "DEFAULT" values are injected by the Builder based on Mapper's Settings.
VisionX.PRESETS = {
    { name = "DEFAULT", range = %d, min = %d, batch = %d, tick = %d, grid = %d, clones = %d },
     { name = "OFF",     range = 0,    min = 0,   batch = 0,   tick = 0,    grid = 0,   clones = 0 },
    { name = "LOW",     range = 500,  min = 150, batch = 25,  tick = 1000, grid = 400, clones = 300 },
    { name = "MEDIUM",  range = 700, min = 300, batch = 50,  tick = 700,  grid = 250, clones = 600 },
    { name = "HIGH",    range = 1500, min = 270, batch = 100, tick = 500,  grid = 200, clones = 1000 }
    
}

-- All object models to be rendered by this script
VisionX.TARGET_MODEL_IDS = {
%s
}

-- Current active config (Starts empty, populated by ApplyMode)
VisionX.CONFIG = {
    ENABLED_BY_DEFAULT = true,
    MAX_VIEW_RANGE = 0,
    MIN_VIEW_RANGE = 0,
    CREATION_BATCH_LIMIT = 0,
    UPDATE_TICK_RATE = 0,
    SPATIAL_GRID_CELL_SIZE = 0,
    CLONE_LIMIT = 0,
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
    currentModeIndex = 1, -- Defaults to 1 (DEFAULT / Mapper Settings)
    objectRegistry = {}, 
    activeClones = {}, 
    spatialGrid = {}, 
    screenWidth = 0, 
    screenHeight = 0,
}

-- ////////////////////////////////////////////////////////////////////////////
-- // DX FEEDBACK SYSTEM (Mode Switching)
-- ////////////////////////////////////////////////////////////////////////////

local feedbackState = { text = "", alpha = 0, tick = 0, duration = 3000 }
local startupState = { alpha = 0, tick = 0, duration = 5000, isRendering = false }
local sx, sy = guiGetScreenSize()

local function showFeedback(text)
    feedbackState.text = text
    feedbackState.alpha = 255
    feedbackState.tick = getTickCount()
    if not feedbackState.isRendering then
        addEventHandler("onClientRender", root, renderFeedback)
        feedbackState.isRendering = true
    end
end

function renderFeedback()
    local currentTick = getTickCount()
    local progress = currentTick - feedbackState.tick
    
    if progress > feedbackState.duration then
        feedbackState.alpha = feedbackState.alpha - 5
        if feedbackState.alpha <= 0 then
            removeEventHandler("onClientRender", root, renderFeedback)
            feedbackState.isRendering = false
            feedbackState.alpha = 0
        end
    end

    if feedbackState.alpha > 0 then
        local text = "VisionX: " .. feedbackState.text
        -- Draw Shadow
        dxDrawText(text, sx/2 + 2, sy - 148, sx/2 + 2, sy - 148, tocolor(0,0,0, feedbackState.alpha), 2, "default-bold", "center", "bottom")
        
        -- Draw Text (Red for OFF, Green for Active)
        local r, g, b = 100, 255, 100
        if feedbackState.text == "OFF" then r,g,b = 255, 100, 100 end
        dxDrawText(text, sx/2, sy - 150, sx/2, sy - 150, tocolor(r,g,b, feedbackState.alpha), 2, "default-bold", "center", "bottom")
    end
end

-- ////////////////////////////////////////////////////////////////////////////
-- // DX STARTUP NOTIFICATION
-- ////////////////////////////////////////////////////////////////////////////

local function showStartupMessage()
    startupState.alpha = 255
    startupState.tick = getTickCount()
    if not startupState.isRendering then
        addEventHandler("onClientRender", root, renderStartupMessage)
        startupState.isRendering = true
    end
end

function renderStartupMessage()
    local currentTick = getTickCount()
    local progress = currentTick - startupState.tick
    
    -- Fade out in the last 1 second
    if progress > (startupState.duration - 1000) then
        startupState.alpha = 255 - ((progress - (startupState.duration - 1000)) / 1000 * 255)
    end

    if progress > startupState.duration then
        removeEventHandler("onClientRender", root, renderStartupMessage)
        startupState.isRendering = false
        startupState.alpha = 0
        return
    end

    if startupState.alpha > 0 then
        local text = "This map uses VisionX.\nPress 'X' to change settings or to turn it off.\nOr use /vx [default/low/medium/high/off]"
        -- Position: Middle (sx/2), 10%% Up from Middle (sy * 0.4)
        local yPos = sy * 0.4 
        local scale = 1.5
        
        -- Draw Shadow
        dxDrawText(text, sx/2 + 2, yPos + 2, sx/2 + 2, yPos + 2, tocolor(0,0,0, startupState.alpha), scale, "default-bold", "center", "center")
        
        -- Draw Text (Brand Color Blue-ish)
        dxDrawText(text, sx/2, yPos, sx/2, yPos, tocolor(13, 188, 255, startupState.alpha), scale, "default-bold", "center", "center")
    end
end

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
        -- Check against the GLOBAL target list
        if VisionX.TARGET_MODEL_IDS[modelId] and not getElementData(entity, "visionx_clone") and getElementDimension(entity) == playerDimension then
            
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

-- ////////////////////////////////////////////////////////////////////////////
-- // MODE MANAGEMENT (Apply / Cycle)
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:ApplyMode(index)
    local preset = self.PRESETS[index]
    if not preset then return end
    
    self.state.currentModeIndex = index
    
    -- COMPLETE SHUTDOWN if OFF
    if preset.name == "OFF" then
        self:Deactivate()
        showFeedback("OFF")
        return
    end

    -- Update Configuration from Preset
    self.CONFIG.MAX_VIEW_RANGE = preset.range
    self.CONFIG.MIN_VIEW_RANGE = preset.min
    self.CONFIG.CREATION_BATCH_LIMIT = preset.batch
    self.CONFIG.UPDATE_TICK_RATE = preset.tick
    self.CONFIG.SPATIAL_GRID_CELL_SIZE = preset.grid
    self.CONFIG.CLONE_LIMIT = preset.clones

    -- If currently running, restart to apply new settings
    if self.state.isEnabled then
        self:Deactivate()
    end
    
    self:Activate()
    showFeedback(preset.name)
end

function VisionX:CycleMode()
    local nextIndex = self.state.currentModeIndex + 1
    if nextIndex > #self.PRESETS then nextIndex = 1 end
    self:ApplyMode(nextIndex)
end

function VisionX:Activate()
    if self.state.isEnabled then return end
    self.state.isEnabled = true

    self:_BuildObjectRegistry()
    self:_BuildSpatialGrid()
    self:_PerformSpawningLogic() -- Run once immediately

    -- Start the main update loops.
    self.timers.spawn = setTimer(function() self:_PerformSpawningLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    self.timers.cullDelay = setTimer(function()
        self.timers.cull = setTimer(function() self:_PerformCullingLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
    
    -- Set LODs
    for id, _ in pairs(VisionX.TARGET_MODEL_IDS) do engineSetModelLODDistance(id, self.CONFIG.MIN_VIEW_RANGE) end
end

function VisionX:Deactivate()
    if not self.state.isEnabled then return end
    self.state.isEnabled = false
    
    -- Stop All Timers
    for _, timer in pairs(self.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    self.timers = {}
    
    -- Purge Clones
    self:_PurgeAllClones()
    
    -- Reset LODs
    for id, _ in pairs(VisionX.TARGET_MODEL_IDS) do engineSetModelLODDistance(id, 300) end
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
    
    -- Start in DEFAULT mode (Index 1) using Mapper Settings
    if self.CONFIG.ENABLED_BY_DEFAULT then
        self:ApplyMode(1)
        showStartupMessage() -- Trigger the startup DX Text
    end
    
    -- Refresh if player streams back in (e.g., changing dimension)
    addEventHandler("onClientPlayerStreamIn", root, function()
        if source == localPlayer and VisionX.state.isEnabled then
            VisionX:Deactivate()
            VisionX:Activate()
        end
    end)
    
    -- Binds
    bindKey("x", "down", function()
        if not isChatBoxInputActive() and not isConsoleActive() then
            VisionX:CycleMode()
        end
    end)
    
    -- Commands
    addCommandHandler("vx", function(_, arg)
        local arg = string.lower(arg or "")
        if arg == "off" then VisionX:ApplyMode(5)
        elseif arg == "low" then VisionX:ApplyMode(2)
        elseif arg == "medium" or arg == "med" then VisionX:ApplyMode(3)
        elseif arg == "high" then VisionX:ApplyMode(4)
        elseif arg == "default" or arg == "def" then VisionX:ApplyMode(1)
        else showFeedback("Use: /vx [default/low/medium/high/off]") end
    end)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // AUTO-START
-- ////////////////////////////////////////////////////////////////////////////
addEventHandler("onClientResourceStart", resourceRoot, function() VisionX:Initialize() end)
addEventHandler("onClientResourceStop", resourceRoot, function() VisionX:Deactivate() end)
]=]

    -- Inject user settings from the builder UI into the template string (DEFAULT PRESET)
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
-- // EVENT HANDLERS
-- ////////////////////////////////////////////////////////////////////////////

addEvent("visionx:buildScript", true)
addEventHandler("visionx:buildScript", root, function(settings, category, uniqueMapModels)
    -- Get the resource this script is running in and its name
    local thisResource = getThisResource()
    local thisResourceName = getResourceName(thisResource)
    
    -- Check if the main script has exported the required function in this resource
    if not exports[thisResourceName] or not exports[thisResourceName].getCategoryLookup then
        triggerClientEvent(source, "visionx:receiveBuildError", source, "Could not find exported functions. Make sure 'builder_server.lua' is in the same resource as the main 'server.lua'.")
        return
    end

    -- Get the category lookup table from the main server script using the dynamic resource name
    local categoryLookup = exports[thisResourceName]:getCategoryLookup()
    if not categoryLookup or type(categoryLookup) ~= "table" then
        triggerClientEvent(source, "visionx:receiveBuildError", source, "Could not retrieve valid category data from the main resource.")
        return
    end

    -- Generate the script using only the models present on the client's map
    local includedIDs, otherIDs = getModelIDsForCategories(category, categoryLookup, uniqueMapModels)
    local includedString = formatModelIDTable(includedIDs, false)
    local otherString = formatModelIDTable(otherIDs, true)
    
    -- GENERATE CODE (Passing Settings now)
    local generatedCode = generateStandaloneScript(settings, includedString, otherString)

    -- Send the generated code back to the client
    triggerClientEvent(source, "visionx:receiveGeneratedScript", source, generatedCode)
end)