--[[
============================================================
--
--  Author: Corrupt
--  VisionX Builder - Server-Side
--  Version: 3.4.1 (Massive performance overhaul, LOD & FarClip)
--
--  CHANGELOG: (3.2.8 → 3.4.1)
--  - Server-side builder endpoints for saving generated scripts to map resources.
--  - Templates updated to include priority categories and clone-limit configuration.
--  - Security checks added for file and meta modifications (ACL enforcement).
--  - Improvements to model grouping and formatting for standalone outputs.
--
============================================================
]]

-- [CORE SAVING LOGIC]
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
    -- Security Check
    local account = getPlayerAccount(client)
    local isAllowed = false
    if not isGuestAccount(account) then
        if
            isObjectInACLGroup(
                "user." .. getAccountName(account),
                aclGetGroup("Admin")
            )
            or isObjectInACLGroup(
                "user." .. getAccountName(account),
                aclGetGroup("Supermods")
            )
        then
            isAllowed = true
        end
    end
    if not isAllowed then
        triggerClientEvent(
            source,
            "visionx:onSaveResult",
            source,
            false,
            "Access Denied: You must be Admin."
        )
        return
    end
    if
        not hasObjectPermissionTo(
            getThisResource(),
            "general.ModifyOtherObjects"
        )
    then
        triggerClientEvent(
            source,
            "visionx:onSaveResult",
            source,
            false,
            "Resource needs Admin rights."
        )
        return
    end

    local res = getResourceFromName(mapName)
    if not res then
        triggerClientEvent(
            source,
            "visionx:onSaveResult",
            source,
            false,
            "Map not found."
        )
        return
    end

    local fileName = "visionx.lua"
    local filePath = ":" .. mapName .. "/" .. fileName
    local file = fileCreate(filePath)
    if not file then
        triggerClientEvent(
            source,
            "visionx:onSaveResult",
            source,
            false,
            "Could not create file."
        )
        return
    end
    fileWrite(file, scriptContent)
    fileClose(file)

    local metaPath = ":" .. mapName .. "/meta.xml"
    local xml = xmlLoadFile(metaPath)
    if not xml then
        triggerClientEvent(
            source,
            "visionx:onSaveResult",
            source,
            false,
            "Could not load meta.xml."
        )
        return
    end
    local scriptExists = false
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        if
            xmlNodeGetName(node) == "script"
            and xmlNodeGetAttribute(node, "src") == fileName
        then
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
    triggerClientEvent(
        source,
        "visionx:onSaveResult",
        source,
        true,
        "Saved to '" .. mapName .. "'!"
    )
end)

local function getModelIDsForCategories(
    category,
    categoryLookup,
    uniqueMapModels,
    groupTypeRegistry
)
    local includedIDs, otherIDs = {}, {}
    if not category or not categoryLookup or not uniqueMapModels then
        return includedIDs, otherIDs
    end
    for modelId, _ in pairs(uniqueMapModels) do
        local groupName = categoryLookup[modelId] or "General"
        local objectType = groupTypeRegistry[groupName] or "OTHER"
        local shouldInclude = (
            category == "All"
            and (objectType == "Decoration" or objectType == "Track")
        ) or (category == objectType)
        if shouldInclude then
            table.insert(includedIDs, modelId)
        else
            table.insert(otherIDs, modelId)
        end
    end
    return includedIDs, otherIDs
end

local function formatModelIDTable(modelIDs, categoryLookup, isCommented)
    if #modelIDs == 0 then
        return ""
    end
    local parts = {}
    local prefix = isCommented and "        " or "        " -- Never comment out, we need them for LODs
    for _, id in ipairs(modelIDs) do
        local cat = categoryLookup[id] or "General"
        table.insert(parts, string.format('[%d] = "%s"', id, cat))
    end
    local output, line = {}, {}
    for i, part in ipairs(parts) do
        table.insert(line, part)
        if i % 4 == 0 or i == #parts then
            table.insert(output, prefix .. table.concat(line, ", "))
            line = {}
        end
    end
    return table.concat(output, ",\n")
end

local function generateStandaloneScript(settings, cloneString, lodString)
    local pHigh, pMed, pLow, pCustom =
        settings.PRIORITY_HIGH or "Land Masses",
        settings.PRIORITY_MED or "Trees",
        settings.PRIORITY_LOW or "Plants",
        settings.CUSTOM_PRIORITY_IDS or ""

    local template = [=[
--[[
============================================================
--
--  Author: Corrupt
--  VisionX - Standalone Script
--  Version: 3.4.0 (Performance Optimizations)
--
============================================================
]]

--[[ Configuration ]]--

VisionX = {}
VisionX.state = {}
VisionX.timers = {}
VisionX.FPS = 60

VisionX.PRESETS = {
    { name = "DEFAULT", range = %d, min = %d, batch = %d, tick = %d, grid = %d, clones = %d },
    { name = "OFF",     range = 0,    min = 0,   batch = 0,   tick = 0,    grid = 0,   clones = 0 },
    { name = "LOW",     range = 500,  min = 150, batch = 25,  tick = 1000, grid = 400, clones = 300 },
    { name = "MEDIUM",  range = 700,  min = 300, batch = 50,  tick = 700,  grid = 250, clones = 600 },
    { name = "HIGH",    range = 1500, min = 270, batch = 100, tick = 500,  grid = 200, clones = 1000 }
}

VisionX.CONFIG = {
    ENABLED_BY_DEFAULT = true, 
    MAX_VIEW_RANGE = 0, 
    MIN_VIEW_RANGE = 0, 
    CREATION_BATCH_LIMIT = 0, 
    UPDATE_TICK_RATE = 0, 
    SPATIAL_GRID_CELL_SIZE = 0, 
    CLONE_LIMIT = 0,
    PRIORITY_HIGH = "%s", 
    PRIORITY_MED = "%s", 
    PRIORITY_LOW = "%s", 
    CUSTOM_PRIORITY_IDS = "%s"
}

-- [CLONE TARGETS] - These objects will be part of the dynamic streaming grid
VisionX.CLONE_TARGETS = {
%s
}

-- [LOD ONLY] - These objects just get 325 LOD + Extended flag
VisionX.LOD_ONLY_LIST = {
%s 
}

VisionX.state = {
    isInitialized = false, 
    isEnabled = false, 
    currentModeIndex = 1, 
    objectRegistry = {}, 
    activeClones = {}, 
    spatialGrid = {}, 
    screenWidth = 0, 
    screenHeight = 0,
    gridBounds = { minX = math.huge, minY = math.huge, minZ = math.huge, maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge },
    tablePool = {}, 
    queueItemPool = {}, 
    cullBuffer = {}, 
    customPriorityMap = {},
}

-- Memory Management Helpers
function VisionX:AcquireTable()
    local t = table.remove(self.state.tablePool)
    return t or {}
end

function VisionX:ReleaseTable(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
    table.insert(self.state.tablePool, t)
end

function VisionX:AcquireQueueItem(element, data)
    local t = table.remove(self.state.queueItemPool)
    if not t then 
        return { el = element, d = data } 
    else 
        t.el = element
        t.d = data
        return t 
    end
end

function VisionX:ReleaseQueueItem(t)
    if not t then return end
    t.el = nil
    t.d = nil
    table.insert(self.state.queueItemPool, t)
end

function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Visual Feedback
local feedbackState = { text = "", alpha = 0, tick = 0, duration = 3000 }
local startupState = { alpha = 0, tick = 0, duration = 5000, isRendering = false }
local sx, sy = guiGetScreenSize()

function renderFeedback()
    local progress = getTickCount() - feedbackState.tick
    if progress > feedbackState.duration then 
        feedbackState.alpha = feedbackState.alpha - 5
        if feedbackState.alpha <= 0 then 
            removeEventHandler("onClientRender", root, renderFeedback)
            feedbackState.isRendering = false
            feedbackState.alpha = 0 
        end 
    end
    if feedbackState.alpha > 0 then
        local r, g, b = 100, 255, 100
        if feedbackState.text == "OFF" then r,g,b = 255, 100, 100 end
        dxDrawText("VisionX: " .. feedbackState.text, sx/2 + 2, sy - 148, sx/2 + 2, sy - 148, tocolor(0,0,0, feedbackState.alpha), 2, "default-bold", "center", "bottom")
        dxDrawText("VisionX: " .. feedbackState.text, sx/2, sy - 150, sx/2, sy - 150, tocolor(r,g,b, feedbackState.alpha), 2, "default-bold", "center", "bottom")
    end
end

local function showFeedback(text)
    feedbackState.text = text
    feedbackState.alpha = 255
    feedbackState.tick = getTickCount()
    if not feedbackState.isRendering then 
        addEventHandler("onClientRender", root, renderFeedback)
        feedbackState.isRendering = true 
    end 
end

function renderStartupMessage()
    local progress = getTickCount() - startupState.tick
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
        dxDrawText("This map uses VisionX.\nPress 'X' to change settings.", sx/2 + 2, (sy * 0.4) + 2, sx/2 + 2, (sy * 0.4) + 2, tocolor(0,0,0, startupState.alpha), 1.5, "default-bold", "center", "center")
        dxDrawText("This map uses VisionX.\nPress 'X' to change settings.", sx/2, sy * 0.4, sx/2, sy * 0.4, tocolor(13, 188, 255, startupState.alpha), 1.5, "default-bold", "center", "center")
    end
end

-- Core Logic
function VisionX:ParseCustomPriorities()
    self.state.customPriorityMap = {}
    local str = self.CONFIG.CUSTOM_PRIORITY_IDS
    for id in string.gmatch(str, "%%d+") do 
        local num = tonumber(id)
        if num then self.state.customPriorityMap[num] = true end 
    end
end

local frameTicks = {}
function VisionX.UpdateFPS()
    local now = getTickCount()
    table.insert(frameTicks, now)
    for i = #frameTicks, 1, -1 do 
        if now - frameTicks[i] > 1000 then table.remove(frameTicks, i) end 
    end
    VisionX.FPS = #frameTicks
end

function VisionX:_BuildObjectRegistry()
    self.state.objectRegistry = {}
    local allGameObjects = getElementsByType("object")
    local playerDimension = getElementDimension(localPlayer)
    
    for _, entity in ipairs(allGameObjects) do
        local modelId = getElementModel(entity)
        local isClone = getElementData(entity, "visionx_clone")
        
        -- Clone Targets
        if VisionX.CLONE_TARGETS[modelId] and not isClone and getElementDimension(entity) == playerDimension then
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
                    interior = getElementInterior(entity), 
                    doubleSided = isElementDoubleSided(entity), 
                    alpha = alpha 
                }
            end
        end
    end
end

function VisionX:_BuildSpatialGrid()
    for k, v in pairs(self.state.spatialGrid) do 
        self:ReleaseTable(v)
        self.state.spatialGrid[k] = nil 
    end
    self.state.gridBounds = { minX = math.huge, minY = math.huge, minZ = math.huge, maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge }
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    if cellSize <= 0 then cellSize = 250 end 

    for entity, data in pairs(self.state.objectRegistry) do
        local gridX, gridY, gridZ = math.floor(data.pos[1] / cellSize), math.floor(data.pos[2] / cellSize), math.floor(data.pos[3] / cellSize)
        
        if gridX < self.state.gridBounds.minX then self.state.gridBounds.minX = gridX end
        if gridX > self.state.gridBounds.maxX then self.state.gridBounds.maxX = gridX end
        if gridY < self.state.gridBounds.minY then self.state.gridBounds.minY = gridY end
        if gridY > self.state.gridBounds.maxY then self.state.gridBounds.maxY = gridY end
        if gridZ < self.state.gridBounds.minZ then self.state.gridBounds.minZ = gridZ end
        if gridZ > self.state.gridBounds.maxZ then self.state.gridBounds.maxZ = gridZ end
        
        local key = gridX .. "_" .. gridY .. "_" .. gridZ
        if not self.state.spatialGrid[key] then self.state.spatialGrid[key] = self:AcquireTable() end
        table.insert(self.state.spatialGrid[key], entity)
    end
end

function VisionX:_PurgeAllClones()
    for _, cloneInstance in pairs(self.state.activeClones) do 
        if isElement(cloneInstance) then destroyElement(cloneInstance) end 
    end
    self.state.activeClones = {}
end

function VisionX:_PerformCullingLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    for k in pairs(self.state.cullBuffer) do self.state.cullBuffer[k] = nil end
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE^2
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE^2

    for sourceElement, cloneInstance in pairs(self.state.activeClones) do
        if not isElement(sourceElement) or not isElement(cloneInstance) then 
            table.insert(self.state.cullBuffer, sourceElement)
        else
            local sourceData = self.state.objectRegistry[sourceElement]
            if not sourceData or sourceData.dimension ~= playerDim then 
                table.insert(self.state.cullBuffer, sourceElement)
            else
                local dx, dy, dz = sourceData.pos[1] - camX, sourceData.pos[2] - camY, sourceData.pos[3] - camZ
                local distSq = dx*dx + dy*dy + dz*dz
                if distSq < minRangeSq or distSq > maxRangeSq then 
                    table.insert(self.state.cullBuffer, sourceElement) 
                end
            end
        end
    end
    for _, sourceElement in ipairs(self.state.cullBuffer) do
        local cloneInstance = self.state.activeClones[sourceElement]
        if isElement(cloneInstance) then destroyElement(cloneInstance) end
        self.state.activeClones[sourceElement] = nil
    end
end

function VisionX:_PerformSpawningLogic()
    local batch = self.CONFIG.CREATION_BATCH_LIMIT
    if VisionX.FPS < 40 then batch = math.max(2, math.floor(batch * 0.3)) 
    elseif VisionX.FPS < 50 then batch = math.max(5, math.floor(batch * 0.6)) end
    
    local camX, camY, camZ, targetX, targetY, targetZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local created = 0
    
    if table.size(self.state.activeClones) >= self.CONFIG.CLONE_LIMIT then return end
    
    local fwdX, fwdY = targetX - camX, targetY - camY
    local length = math.sqrt(fwdX*fwdX + fwdY*fwdY)
    if length > 0 then fwdX, fwdY = fwdX/length, fwdY/length else fwdX, fwdY = 0, 1 end

    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE^2
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE^2
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    
    local pGridX, pGridY, pGridZ = math.floor(camX / cellSize), math.floor(camY / cellSize), math.floor(camZ / cellSize)
    local mapMaxZ = (self.state.gridBounds.maxZ ~= -math.huge) and (self.state.gridBounds.maxZ * cellSize) or 1000
    local scanRadiusV = (mapMaxZ > 2000) and math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize) or 3
    local scanRadiusMax = math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)
    
    local queueCustom, queueHigh, queueMed, queueLow, queueOther = {}, {}, {}, {}, {}
    local screenBuffer = 200
    
    for i = -scanRadiusMax, scanRadiusMax do
        for j = -scanRadiusMax, scanRadiusMax do
            local cellRelX, cellRelY = i * cellSize, j * cellSize
            local distFwd = (cellRelX * fwdX) + (cellRelY * fwdY)
            local distSide = math.abs((cellRelX * -fwdY) + (cellRelY * fwdX))
            
            if (distFwd < self.CONFIG.MAX_VIEW_RANGE) and (distFwd > -cellSize) and (distSide < (5 * cellSize)) then
                for k = -scanRadiusV, scanRadiusV do
                    local key = (pGridX + i) .. "_" .. (pGridY + j) .. "_" .. (pGridZ + k)
                    if self.state.spatialGrid[key] then
                        for _, sourceElement in ipairs(self.state.spatialGrid[key]) do
                            if isElement(sourceElement) and not self.state.activeClones[sourceElement] then
                                local data = self.state.objectRegistry[sourceElement]
                                if data and data.dimension == playerDim then
                                    local dx, dy, dz = data.pos[1] - camX, data.pos[2] - camY, data.pos[3] - camZ
                                    local distSq = dx*dx + dy*dy + dz*dz
                                    
                                    if distSq >= minRangeSq and distSq <= maxRangeSq then
                                        local sX, sY = getScreenFromWorldPosition(data.pos[1], data.pos[2], data.pos[3])
                                        if sX and sY and sX >= -screenBuffer and sX <= self.state.screenWidth + screenBuffer and sY >= -screenBuffer and sY <= self.state.screenHeight + screenBuffer then
                                            local qItem = self:AcquireQueueItem(sourceElement, data)
                                            local group = VisionX.CLONE_TARGETS[data.model]
                                            
                                            if self.state.customPriorityMap[data.model] then table.insert(queueCustom, qItem)
                                            elseif group == self.CONFIG.PRIORITY_HIGH then table.insert(queueHigh, qItem)
                                            elseif group == self.CONFIG.PRIORITY_MED then table.insert(queueMed, qItem)
                                            elseif group == self.CONFIG.PRIORITY_LOW then table.insert(queueLow, qItem)
                                            else table.insert(queueOther, qItem) end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    local function processQueue(queue)
        for _, item in ipairs(queue) do
            if created >= batch or (table.size(self.state.activeClones) + created) >= self.CONFIG.CLONE_LIMIT then break end
            if isElement(item.el) and not self.state.activeClones[item.el] then
                local newClone = createObject(item.d.model, item.d.pos[1], item.d.pos[2], item.d.pos[3], item.d.rot[1], item.d.rot[2], item.d.rot[3], true)
                if isElement(newClone) then
                    setElementDimension(newClone, item.d.dimension)
                    setElementInterior(newClone, item.d.interior)
                    setObjectScale(newClone, item.d.scale)
                    setElementData(newClone, "visionx_clone", true, false)
                    setElementDoubleSided(newClone, item.d.doubleSided)
                    setElementAlpha(newClone, item.d.alpha)
                    setElementCollisionsEnabled(newClone, false)
                    setElementFrozen(newClone, true)
                    self.state.activeClones[item.el] = newClone
                    created = created + 1
                end
            end
        end
    end
    
    processQueue(queueCustom); processQueue(queueHigh); processQueue(queueMed); processQueue(queueLow); processQueue(queueOther)
    
    local function clean(q) 
        for _, item in ipairs(q) do VisionX:ReleaseQueueItem(item) end
        VisionX:ReleaseTable(q) 
    end
    clean(queueCustom); clean(queueHigh); clean(queueMed); clean(queueLow); clean(queueOther)
end

function VisionX:ApplyMode(index)
    local preset = self.PRESETS[index]; if not preset then return end
    self.state.currentModeIndex = index
    if preset.name == "OFF" then self:Deactivate(); showFeedback("OFF"); return end
    for k, v in pairs(preset) do 
        if k ~= "name" then 
            if k == "range" then self.CONFIG.MAX_VIEW_RANGE = v 
            elseif k == "min" then self.CONFIG.MIN_VIEW_RANGE = v
            elseif k == "batch" then self.CONFIG.CREATION_BATCH_LIMIT = v
            elseif k == "tick" then self.CONFIG.UPDATE_TICK_RATE = v
            elseif k == "grid" then self.CONFIG.SPATIAL_GRID_CELL_SIZE = v
            elseif k == "clones" then self.CONFIG.CLONE_LIMIT = v end
        end 
    end
    if self.state.isEnabled then self:Deactivate() end
    self:Activate(); showFeedback(preset.name)
end

function VisionX:CycleMode() 
    local next = self.state.currentModeIndex + 1
    if next > #self.PRESETS then next = 1 end
    self:ApplyMode(next) 
end

function VisionX:ApplyGlobalLODRules()
    setFarClipDistance(2500)
    for id, _ in pairs(VisionX.CLONE_TARGETS) do engineSetModelLODDistance(id, 325, true) end
    for id, _ in pairs(VisionX.LOD_ONLY_LIST) do engineSetModelLODDistance(id, 325, true) end
end

function VisionX:Activate()
    if self.state.isEnabled then return end
    self.state.isEnabled = true
    self:ApplyGlobalLODRules()
    self:ParseCustomPriorities()
    self:_BuildObjectRegistry()
    self:_BuildSpatialGrid()
    self:_PerformSpawningLogic() 
    self.timers.spawn = setTimer(function() self:_PerformSpawningLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0)
    self.timers.cullDelay = setTimer(function() 
        self.timers.cull = setTimer(function() self:_PerformCullingLogic() end, self.CONFIG.UPDATE_TICK_RATE, 0) 
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
end

function VisionX:Deactivate()
    if not self.state.isEnabled then return end
    self.state.isEnabled = false
    for _, timer in pairs(self.timers) do if isTimer(timer) then killTimer(timer) end end
    self.timers = {}
    self:_PurgeAllClones()
    self:ApplyGlobalLODRules() -- Maintain global settings
end

function VisionX:Initialize()
    if self.state.isInitialized then return end
    self.state.isInitialized = true
    local sx, sy = guiGetScreenSize()
    self.state.screenWidth = sx
    self.state.screenHeight = sy
    addEventHandler("onClientScreenSizeChange", root, function (w, h) VisionX.state.screenWidth = w; VisionX.state.screenHeight = h end)
    
    self:ApplyGlobalLODRules() -- Apply immediately on start
    
    setTimer(function() 
        if self.CONFIG.ENABLED_BY_DEFAULT then self:ApplyMode(1); showStartupMessage() end 
    end, 500, 1)
    
    addEventHandler("onClientPlayerStreamIn", root, function() 
        if source == localPlayer and VisionX.state.isEnabled then VisionX:Deactivate(); VisionX:Activate() end 
    end)
    bindKey("x", "down", function() 
        if not isChatBoxInputActive() and not isConsoleActive() then VisionX:CycleMode() end 
    end)
    addCommandHandler("vx", function(_, arg)
        local arg = string.lower(arg or "")
        if arg == "off" then VisionX:ApplyMode(2) 
        elseif arg == "low" then VisionX:ApplyMode(3) 
        elseif arg == "medium" or arg == "med" then VisionX:ApplyMode(4) 
        elseif arg == "high" then VisionX:ApplyMode(5) 
        elseif arg == "default" or arg == "def" then VisionX:ApplyMode(1) 
        else showFeedback("Use: /vx [default/low/medium/high/off]") end
    end)
    addEventHandler("onClientRender", root, VisionX.UpdateFPS)
end
addEventHandler("onClientResourceStart", resourceRoot, function() VisionX:Initialize() end)
addEventHandler("onClientResourceStop", resourceRoot, function() VisionX:Deactivate() end)
]=]

    return string.format(
        template,
        settings.MAX_VIEW_RANGE,
        settings.MIN_VIEW_RANGE,
        settings.CREATION_BATCH_LIMIT,
        settings.UPDATE_TICK_RATE,
        settings.SPATIAL_GRID_CELL_SIZE,
        settings.CLONE_LIMIT,
        pHigh,
        pMed,
        pLow,
        pCustom,
        cloneString,
        lodString
    )
end

addEvent("visionx:buildScript", true)
addEventHandler(
    "visionx:buildScript",
    root,
    function(settings, category, uniqueMapModels)
        local thisResource = getThisResource()
        if not exports[getResourceName(thisResource)].getCategoryLookup then
            triggerClientEvent(
                source,
                "visionx:receiveBuildError",
                source,
                "Export error"
            )
            return
        end
        local categoryLookup =
            exports[getResourceName(thisResource)]:getCategoryLookup()
        local groupTypeRegistry = {
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

        -- [UPDATED] Separate into Clone Targets vs Pure LOD objects
        local cloneIDs, lodOnlyIDs = getModelIDsForCategories(
            category,
            categoryLookup,
            uniqueMapModels,
            groupTypeRegistry
        )

        -- We now include ALL IDs in the script, split into two tables
        local cloneString = formatModelIDTable(cloneIDs, categoryLookup, false)
        local lodString = formatModelIDTable(lodOnlyIDs, categoryLookup, false)

        local generatedCode =
            generateStandaloneScript(settings, cloneString, lodString)

        triggerClientEvent(
            source,
            "visionx:receiveGeneratedScript",
            source,
            generatedCode
        )
    end
)
