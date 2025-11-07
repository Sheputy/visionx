--[[
============================================================
--
--  Author: Corrupt
--  VisionX Builder - Server-Side
--  Version: 3.2.0 
--
============================================================
]]

---
-- @function getModelIDsForCategories
-- @private
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
-- @private
-- Formats a Lua table of model IDs into a string for injection into the script template.
---
local function formatModelIDTable(modelIDs, isCommented)
    if #modelIDs == 0 then return "" end
    local parts = {}
    local prefix = isCommented and "--         " or "        "

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
-- @private
-- Constructs the full standalone script as a string using the new v4.x template.
---
local function generateStandaloneScript(settings, includedString, otherString)
    -- This large string is the template for the standalone script.
    local template = [=[
--[[
============================================================
--
--  VisionX Standalone - Generated for Map Resource
--  Author: Corrupt
--  Version: 3.2.0
--
--  This is a self-contained script. Paste it into your
--  map's client-side files or include it via meta.xml.
--  It includes spatial grid logic for performance.
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
    objectRegistry = {}, -- Caches only objects matching TARGET_MODEL_IDS
    activeClones = {}, -- Tracks currently rendered clone objects.
    spatialGrid = {}, -- The spatial grid for performance optimization.
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
            
            -- ** MODIFIED: Added scale and alpha filtering **
            local scale = getObjectScale(entity)
            local alpha = getElementAlpha(entity)
            
            if (scale >= 0.1 and scale <= 100) and (alpha >= 50) then
                local pX, pY, pZ = getElementPosition(entity)
                local rX, rY, rZ = getElementRotation(entity)
                self.state.objectRegistry[entity] = {
                    model = modelId,
                    pos = { pX, pY, pZ },
                    rot = { rX, rY, rZ },
                    scale = scale, -- Use the 'scale' variable
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
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    
    local searchRadius = math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)
    local pGridX = math.floor(camX / cellSize)
    local pGridY = math.floor(camY / cellSize)
    
    for i = -searchRadius, searchRadius do
        for j = -searchRadius, searchRadius do
            local key = (pGridX + i) .. "_" .. (pGridY + j)
            if self.state.spatialGrid[key] then
                for _, sourceElement in ipairs(self.state.spatialGrid[key]) do
                    if createdThisCycle >= self.CONFIG.CREATION_BATCH_LIMIT then return end
                    
                    local data = self.state.objectRegistry[sourceElement]
                    if data and not self.state.activeClones[sourceElement] and data.dimension == playerDim then
                        local dx, dy, dz = data.pos[1] - camX, data.pos[2] - camY, data.pos[3] - camZ
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq >= minRangeSq and distSq <= maxRangeSq then
                            
                            -- Correct frustum culling
                            local sX, sY = getScreenFromWorldPosition(data.pos[1], data.pos[2], data.pos[3])
                            if sX and sY then
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

    -- Start the main update loops.
    self.timers.spawn = setTimer(function() self:_PerformSpawningLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    self.timers.cullDelay = setTimer(function()
        self.timers.cull = setTimer(function() self:_PerformCullingLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
end

function VisionX:Deactivate()
    if not self.state.isEnabled then return end
    self.state.isEnabled = false
    
    for _, timer in pairs(self.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    self.timers = {}
    
    self:_PurgeAllClones()
end

function VisionX:Initialize()
    if self.state.isInitialized then return end
    self.state.isInitialized = true
    
    -- Set LOD for targeted models
    for modelId, _ in pairs(self.CONFIG.TARGET_MODEL_IDS) do
        engineSetModelLODDistance(modelId, self.CONFIG.MIN_VIEW_RANGE)
    end
    
    if self.CONFIG.ENABLED_BY_DEFAULT then
        self:Activate()
    end
    
    -- Handle map editor state changes
    addEventHandler("onClientEditorSuspended", root, function(suspended)
        if suspended then
            -- Editor is active, disable script
            VisionX:Deactivate()
        else
            -- Editor is inactive, enable script
            VisionX:Activate()
        end
    end)
    
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
    local generatedCode = generateStandaloneScript(settings, includedString, otherString)

    -- Send the generated code back to the client
    triggerClientEvent(source, "visionx:receiveGeneratedScript", source, generatedCode)
end)