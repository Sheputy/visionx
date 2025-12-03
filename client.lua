--[[
============================================================
--
--  Author: Corrupt
--  VisionX Advanced - Client-Side Logic
--  Version: 3.4.0 (Massive performance overhaul, LOD & FarClip)
--
--  CHANGELOG: (3.2.8 → 3.4.0)
--  - Added standalone Builder UI and map-selection save flow (auto-save to map resource).
--  - Separated GUI into `gui_client.lua` and improved notification UX.
--  - Introduced configurable `CLONE_LIMIT` and on-screen clone overlay with color thresholds.
--  - Improved spawning with stricter frustum culling to reduce pop-in.
--  - Added priority categories: "Land Masses", "Trees", "Plants" and `CUSTOM_PRIORITY_IDS` support.
--  - Increased default `MIN_VIEW_RANGE` and tuned LOD/Update throttling for performance.
--
============================================================
]]

-- ////////////////////////////////////////////////////////////////////////////
-- // HELPER FUNCTIONS
-- ////////////////////////////////////////////////////////////////////////////

function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ////////////////////////////////////////////////////////////////////////////
-- // SCRIPT INITIALIZATION
-- ////////////////////////////////////////////////////////////////////////////

VisionX = {}
VisionX.state = {}
VisionX.timers = {}
VisionX.FPS = 60 -- Added for throttling

-- ////////////////////////////////////////////////////////////////////////////
-- // CONFIGURATION & STATE
-- ////////////////////////////////////////////////////////////////////////////

VisionX.CONFIG = {
    MAX_VIEW_RANGE = 1000,
    MIN_VIEW_RANGE = 300,
    CREATION_BATCH_LIMIT = 100,
    UPDATE_TICK_RATE = 500,
    SPATIAL_GRID_CELL_SIZE = 200,
    CLONE_LIMIT = 500,
    DEBUG_MODE = false,
    -- Priorities
    PRIORITY_HIGH = "Land Masses",
    PRIORITY_MED = "Trees",
    PRIORITY_LOW = "Plants",
    CUSTOM_PRIORITY_IDS = "",
}

VisionX.state = {
    isInitialized = false,
    isAdmin = false,
    isEnabled = false,
    isGridVisible = false,
    activeCategory = false,

    masterObjectRegistry = {},
    objectRegistry = {},
    activeClones = {},
    spatialGrid = {},

    uniqueModelIDs = {},
    categoryLookup = {},
    groupTypes = {},
    customPriorityMap = {},

    gridBounds = {
        minX = math.huge,
        minY = math.huge,
        minZ = math.huge,
        maxX = -math.huge,
        maxY = -math.huge,
        maxZ = -math.huge,
    },
    outlierObjects = {
        minX = nil,
        maxX = nil,
        minY = nil,
        maxY = nil,
        minZ = nil,
        maxZ = nil,
    },

    screenWidth = 0,
    screenHeight = 0,
    whiteTexture = nil,

    -- Memory Pools
    tablePool = {},
    queueItemPool = {},
    cullBuffer = {},
    hardRefreshTimer = nil,
}

local sx, sy = guiGetScreenSize()
VisionX.state.screenWidth, VisionX.state.screenHeight = sx, sy

-- ////////////////////////////////////////////////////////////////////////////
-- // MEMORY POOLING
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:AcquireTable()
    local t = table.remove(self.state.tablePool)
    return t or {}
end

function VisionX:ReleaseTable(t)
    if not t then
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
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
    if not t then
        return
    end
    t.el = nil
    t.d = nil
    table.insert(self.state.queueItemPool, t)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // DATA & FPS
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:ParseCustomPriorities()
    self.state.customPriorityMap = {}
    local str = self.CONFIG.CUSTOM_PRIORITY_IDS
    if type(str) == "string" and str ~= "" then
        for id in string.gmatch(str, "%d+") do
            local num = tonumber(id)
            if num then
                self.state.customPriorityMap[num] = true
            end
        end
    end
end

local frameTicks = {}
function VisionX.UpdateFPS()
    local now = getTickCount()
    table.insert(frameTicks, now)
    for i = #frameTicks, 1, -1 do
        if now - frameTicks[i] > 1000 then
            table.remove(frameTicks, i)
        end
    end
    VisionX.FPS = #frameTicks
end

-- ////////////////////////////////////////////////////////////////////////////
-- // 3D GRID VISUALIZER (STATIC VOLUMETRIC)
-- ////////////////////////////////////////////////////////////////////////////

VisionX.RenderGrid = function()
    if not VisionX.state.isGridVisible then
        return
    end
    local bounds = VisionX.state.gridBounds
    if bounds.minX == math.huge then
        return
    end

    if not VisionX.state.whiteTexture then
        VisionX.state.whiteTexture = dxCreateRenderTarget(1, 1)
        if VisionX.state.whiteTexture then
            dxSetRenderTarget(VisionX.state.whiteTexture)
            dxDrawRectangle(0, 0, 1, 1, tocolor(255, 255, 255, 255))
            dxSetRenderTarget()
        end
    end

    local cellSize = VisionX.CONFIG.SPATIAL_GRID_CELL_SIZE
    local minX, maxX = bounds.minX * cellSize, (bounds.maxX + 1) * cellSize
    local minY, maxY = bounds.minY * cellSize, (bounds.maxY + 1) * cellSize
    local minZ, maxZ = bounds.minZ * cellSize, (bounds.maxZ + 1) * cellSize

    -- Colors
    local gridColor = tocolor(255, 0, 0, 255) -- Red Lines
    local boundColor = tocolor(0, 255, 255, 255) -- Cyan Bounds
    local outlierColor = tocolor(255, 255, 0, 255) -- Yellow Text

    local fillYellow = tocolor(255, 255, 0, 30) -- Yellow Fill (Static)
    local fillBlue = tocolor(0, 0, 255, 30) -- Blue Fill (Static)

    local innerThickness = 6.0
    local outerThickness = 12.0

    -- 1. Draw Static Filled Volumes (Checkered Cross-Planes)
    if VisionX.state.whiteTexture then
        for i = bounds.minX, bounds.maxX do
            for j = bounds.minY, bounds.maxY do
                local isYellow = (i + j) % 2 == 0
                local color = isYellow and fillYellow or fillBlue

                local cx = (i + 0.5) * cellSize
                local cy = (j + 0.5) * cellSize

                -- Draw Vertical Plane facing X (YZ plane)
                dxDrawMaterialLine3D(
                    cx,
                    cy,
                    minZ,
                    cx,
                    cy,
                    maxZ,
                    VisionX.state.whiteTexture,
                    cellSize,
                    color,
                    cx + 100,
                    cy,
                    minZ
                )

                -- Draw Vertical Plane facing Y (XZ plane)
                dxDrawMaterialLine3D(
                    cx,
                    cy,
                    minZ,
                    cx,
                    cy,
                    maxZ,
                    VisionX.state.whiteTexture,
                    cellSize,
                    color,
                    cx,
                    cy + 100,
                    minZ
                )
            end
        end
    end

    -- 2. Draw Internal Grid Lines (Red)
    -- Vertical Pillars
    for i = bounds.minX, bounds.maxX + 1 do
        local x = i * cellSize
        for j = bounds.minY, bounds.maxY + 1 do
            local y = j * cellSize
            dxDrawLine3D(x, y, minZ, x, y, maxZ, gridColor, innerThickness)
        end
    end

    -- Horizontal Lines at MinZ & MaxZ
    for i = bounds.minX, bounds.maxX + 1 do
        local x = i * cellSize
        dxDrawLine3D(x, minY, minZ, x, maxY, minZ, gridColor, innerThickness)
        dxDrawLine3D(x, minY, maxZ, x, maxY, maxZ, gridColor, innerThickness)
    end
    for i = bounds.minY, bounds.maxY + 1 do
        local y = i * cellSize
        dxDrawLine3D(minX, y, minZ, maxX, y, minZ, gridColor, innerThickness)
        dxDrawLine3D(minX, y, maxZ, maxX, y, maxZ, gridColor, innerThickness)
    end

    -- 3. Draw Outer Bounds Box (Cyan)
    dxDrawLine3D(minX, minY, minZ, minX, minY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, minY, minZ, maxX, minY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(minX, maxY, minZ, minX, maxY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, maxY, minZ, maxX, maxY, maxZ, boundColor, outerThickness)

    dxDrawLine3D(minX, minY, minZ, maxX, minY, minZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, minY, minZ, maxX, maxY, minZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, maxY, minZ, minX, maxY, minZ, boundColor, outerThickness)
    dxDrawLine3D(minX, maxY, minZ, minX, minY, minZ, boundColor, outerThickness)

    dxDrawLine3D(minX, minY, maxZ, maxX, minY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, minY, maxZ, maxX, maxY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(maxX, maxY, maxZ, minX, maxY, maxZ, boundColor, outerThickness)
    dxDrawLine3D(minX, maxY, maxZ, minX, minY, maxZ, boundColor, outerThickness)

    -- 4. Draw Outlier Labels
    for type, entity in pairs(VisionX.state.outlierObjects) do
        if isElement(entity) then
            local x, y, zObj = getElementPosition(entity)
            local sx, sy = getScreenFromWorldPosition(x, y, zObj + 2)
            if sx then
                dxDrawText(
                    "BOUND: " .. string.upper(type),
                    sx,
                    sy,
                    sx,
                    sy,
                    outlierColor,
                    1,
                    "default-bold",
                    "center"
                )
            end
        end
    end
end

-- ////////////////////////////////////////////////////////////////////////////
-- // REGISTRY & GRID
-- ////////////////////////////////////////////////////////////////////////////

local function _isModelIncluded(modelId, activeCategory)
    if not activeCategory then
        return false
    end
    local groupName = VisionX.state.categoryLookup[modelId]
    if not groupName then
        return false
    end
    local objectType = VisionX.state.groupTypes[groupName] or "OTHER"

    if activeCategory == "All" then
        return objectType == "Decoration" or objectType == "Track"
    else
        return objectType == activeCategory
    end
end

function VisionX:_BuildMasterObjectRegistry()
    if UIManager then
        UIManager:AddNotification("Scanning map objects...", "info")
    end

    self.state.masterObjectRegistry = {}
    self.state.uniqueModelIDs = {}

    local allGameObjects = getElementsByType("object")
    local playerDimension = getElementDimension(localPlayer)

    for _, entity in ipairs(allGameObjects) do
        if
            not getElementData(entity, "visionx_clone")
            and getElementDimension(entity) == playerDimension
        then
            local scale = getObjectScale(entity)
            local alpha = getElementAlpha(entity)

            if (scale >= 0.1 and scale <= 400) and (alpha >= 50) then
                local modelId = getElementModel(entity)
                local pX, pY, pZ = getElementPosition(entity)
                local rX, rY, rZ = getElementRotation(entity)

                self.state.masterObjectRegistry[entity] = {
                    model = modelId,
                    pos = { pX, pY, pZ },
                    rot = { rX, rY, rZ },
                    scale = scale,
                    dimension = getElementDimension(entity),
                    interior = getElementInterior(entity),
                    doubleSided = isElementDoubleSided(entity),
                }
                self.state.uniqueModelIDs[modelId] = true
            end
        end
    end
    -- [CRITICAL] Apply global LODs immediately after scan
    self:_ApplyGlobalLODRules()

    if UIManager then
        UIManager:AddNotification(
            "Cached "
                .. table.size(self.state.masterObjectRegistry)
                .. " objects.",
            "info"
        )
    end
end

function VisionX:_ApplyGlobalLODRules()
    -- Rule: All objects get max LOD + Extended flag, regardless of cloning mode
    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        engineSetModelLODDistance(modelId, 325, true)
    end
    setFarClipDistance(2500)
end

function VisionX:_BuildTargetedRegistry()
    self.state.objectRegistry = {}
    local activeCategory = self.state.activeCategory
    if not activeCategory then
        return
    end

    for entity, data in pairs(self.state.masterObjectRegistry) do
        if _isModelIncluded(data.model, activeCategory) then
            self.state.objectRegistry[entity] = data
        end
    end
end

function VisionX:_BuildSpatialGrid()
    for k, v in pairs(self.state.spatialGrid) do
        self:ReleaseTable(v)
        self.state.spatialGrid[k] = nil
    end

    self.state.gridBounds = {
        minX = math.huge,
        minY = math.huge,
        minZ = math.huge,
        maxX = -math.huge,
        maxY = -math.huge,
        maxZ = -math.huge,
    }
    self.state.outlierObjects = {
        minX = nil,
        maxX = nil,
        minY = nil,
        maxY = nil,
        minZ = nil,
        maxZ = nil,
    }

    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE or 250
    if cellSize <= 0 then
        cellSize = 250
    end

    for entity, data in pairs(self.state.objectRegistry) do
        if isElement(entity) then
            local gridX = math.floor(data.pos[1] / cellSize)
            local gridY = math.floor(data.pos[2] / cellSize)
            local gridZ = math.floor(data.pos[3] / cellSize)

            if gridX < self.state.gridBounds.minX then
                self.state.gridBounds.minX = gridX
                self.state.outlierObjects.minX = entity
            end
            if gridX > self.state.gridBounds.maxX then
                self.state.gridBounds.maxX = gridX
                self.state.outlierObjects.maxX = entity
            end
            if gridY < self.state.gridBounds.minY then
                self.state.gridBounds.minY = gridY
                self.state.outlierObjects.minY = entity
            end
            if gridY > self.state.gridBounds.maxY then
                self.state.gridBounds.maxY = gridY
                self.state.outlierObjects.maxY = entity
            end
            if gridZ < self.state.gridBounds.minZ then
                self.state.gridBounds.minZ = gridZ
                self.state.outlierObjects.minZ = entity
            end
            if gridZ > self.state.gridBounds.maxZ then
                self.state.gridBounds.maxZ = gridZ
                self.state.outlierObjects.maxZ = entity
            end

            local key = gridX .. "_" .. gridY .. "_" .. gridZ
            if not self.state.spatialGrid[key] then
                self.state.spatialGrid[key] = self:AcquireTable()
            end
            table.insert(self.state.spatialGrid[key], entity)
        end
    end
    if UIManager then
        UIManager:UpdateStats()
    end
end

function VisionX:_HandleStreamIn(element)
    if
        getElementType(element) ~= "object"
        or getElementData(element, "visionx_clone")
        or getElementDimension(element) ~= getElementDimension(localPlayer)
    then
        return
    end
    local modelId = getElementModel(element)
    self.state.uniqueModelIDs[modelId] = true
end

function VisionX:_PurgeAllClones()
    for _, cloneInstance in pairs(self.state.activeClones) do
        if isElement(cloneInstance) then
            destroyElement(cloneInstance)
        end
    end
    self.state.activeClones = {}
end

function VisionX:_PerformCullingLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)

    for k in pairs(self.state.cullBuffer) do
        self.state.cullBuffer[k] = nil
    end

    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE

    for sourceElement, cloneInstance in pairs(self.state.activeClones) do
        if not isElement(sourceElement) or not isElement(cloneInstance) then
            table.insert(self.state.cullBuffer, sourceElement)
        else
            local sourceData = self.state.masterObjectRegistry[sourceElement]
            if not sourceData or sourceData.dimension ~= playerDim then
                table.insert(self.state.cullBuffer, sourceElement)
            else
                local dx, dy, dz =
                    sourceData.pos[1] - camX,
                    sourceData.pos[2] - camY,
                    sourceData.pos[3] - camZ
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq < minRangeSq or distSq > maxRangeSq then
                    table.insert(self.state.cullBuffer, sourceElement)
                end
            end
        end
    end

    for i, sourceElement in ipairs(self.state.cullBuffer) do
        local cloneInstance = self.state.activeClones[sourceElement]
        if isElement(cloneInstance) then
            destroyElement(cloneInstance)
        end
        self.state.activeClones[sourceElement] = nil
        self.state.cullBuffer[i] = nil
    end
end

-- [OPTIMIZED] Spawning Logic
function VisionX:_PerformSpawningLogic()
    local dynamicBatchLimit = self.CONFIG.CREATION_BATCH_LIMIT
    if VisionX.FPS < 40 then
        dynamicBatchLimit = math.max(2, math.floor(dynamicBatchLimit * 0.3))
    elseif VisionX.FPS < 50 then
        dynamicBatchLimit = math.max(5, math.floor(dynamicBatchLimit * 0.6))
    end

    local camX, camY, camZ, targetX, targetY, targetZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local createdThisCycle = 0

    local currentCloneCount = table.size(self.state.activeClones)
    if currentCloneCount >= self.CONFIG.CLONE_LIMIT then
        return
    end

    local fwdX, fwdY = targetX - camX, targetY - camY
    local length = math.sqrt(fwdX * fwdX + fwdY * fwdY)
    if length > 0 then
        fwdX, fwdY = fwdX / length, fwdY / length
    else
        fwdX, fwdY = 0, 1
    end

    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE

    local pGridX = math.floor(camX / cellSize)
    local pGridY = math.floor(camY / cellSize)
    local pGridZ = math.floor(camZ / cellSize)

    local mapMaxZ = (self.state.gridBounds.maxZ ~= -math.huge)
            and (self.state.gridBounds.maxZ * cellSize)
        or 1000
    local scanRadiusV = (mapMaxZ > 2000)
            and math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)
        or 3
    local scanRadiusMax = math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)

    local queueCustom, queueHigh, queueMed, queueLow, queueOther =
        {}, {}, {}, {}, {}
    local screenBuffer = 200

    for i = -scanRadiusMax, scanRadiusMax do
        for j = -scanRadiusMax, scanRadiusMax do
            local cellRelX, cellRelY = i * cellSize, j * cellSize
            local distFwd = (cellRelX * fwdX) + (cellRelY * fwdY)
            local distSide = math.abs((cellRelX * -fwdY) + (cellRelY * fwdX))

            if
                (distFwd < self.CONFIG.MAX_VIEW_RANGE)
                and (distFwd > -cellSize)
                and (distSide < (5 * cellSize))
            then
                for k = -scanRadiusV, scanRadiusV do
                    local key = (pGridX + i)
                        .. "_"
                        .. (pGridY + j)
                        .. "_"
                        .. (pGridZ + k)
                    if self.state.spatialGrid[key] then
                        for _, sourceElement in
                            ipairs(self.state.spatialGrid[key])
                        do
                            if
                                isElement(sourceElement)
                                and not self.state.activeClones[sourceElement]
                            then
                                local data =
                                    self.state.objectRegistry[sourceElement]
                                if data and data.dimension == playerDim then
                                    local dx, dy, dz =
                                        data.pos[1] - camX,
                                        data.pos[2] - camY,
                                        data.pos[3] - camZ
                                    local distSq = dx * dx + dy * dy + dz * dz

                                    if
                                        distSq >= minRangeSq
                                        and distSq <= maxRangeSq
                                    then
                                        local sX, sY =
                                            getScreenFromWorldPosition(
                                                data.pos[1],
                                                data.pos[2],
                                                data.pos[3]
                                            )

                                        if
                                            sX
                                            and sY
                                            and sX >= -screenBuffer
                                            and sX <= sx + screenBuffer
                                            and sY >= -screenBuffer
                                            and sY <= sy + screenBuffer
                                        then
                                            local group =
                                                VisionX.state.categoryLookup[data.model]
                                            local qItem = self:AcquireQueueItem(
                                                sourceElement,
                                                data
                                            )

                                            if
                                                self.state.customPriorityMap[data.model]
                                            then
                                                table.insert(queueCustom, qItem)
                                            elseif
                                                group
                                                == self.CONFIG.PRIORITY_HIGH
                                            then
                                                table.insert(queueHigh, qItem)
                                            elseif
                                                group
                                                == self.CONFIG.PRIORITY_MED
                                            then
                                                table.insert(queueMed, qItem)
                                            elseif
                                                group
                                                == self.CONFIG.PRIORITY_LOW
                                            then
                                                table.insert(queueLow, qItem)
                                            else
                                                table.insert(queueOther, qItem)
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
    end

    local function processQueue(queue)
        for _, item in ipairs(queue) do
            if createdThisCycle >= dynamicBatchLimit then
                return false
            end
            if
                (currentCloneCount + createdThisCycle)
                >= self.CONFIG.CLONE_LIMIT
            then
                return false
            end

            if isElement(item.el) and not self.state.activeClones[item.el] then
                local newClone = createObject(
                    item.d.model,
                    item.d.pos[1],
                    item.d.pos[2],
                    item.d.pos[3],
                    item.d.rot[1],
                    item.d.rot[2],
                    item.d.rot[3],
                    true
                )
                if isElement(newClone) then
                    setElementDimension(newClone, item.d.dimension)
                    setElementInterior(newClone, item.d.interior)
                    setObjectScale(newClone, item.d.scale)
                    setElementData(newClone, "visionx_clone", true, false)
                    setElementDoubleSided(newClone, item.d.doubleSided)
                    setElementCollisionsEnabled(newClone, false)
                    setElementFrozen(newClone, true)

                    self.state.activeClones[item.el] = newClone
                    createdThisCycle = createdThisCycle + 1
                end
            end
        end
        return true
    end

    if processQueue(queueCustom) then
        if processQueue(queueHigh) then
            if processQueue(queueMed) then
                if processQueue(queueLow) then
                    processQueue(queueOther)
                end
            end
        end
    end

    local function clean(q)
        for _, item in ipairs(q) do
            self:ReleaseQueueItem(item)
        end
    end
    clean(queueCustom)
    clean(queueHigh)
    clean(queueMed)
    clean(queueLow)
    clean(queueOther)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // CONTROL & COMMANDS
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:Activate(category, isRefresh)
    if
        self.state.isEnabled
        and self.state.activeCategory == category
        and not isRefresh
    then
        return
    end
    if self.state.isEnabled then
        self:Deactivate(true)
    end

    self.state.isEnabled = true
    self.state.activeCategory = category

    self:_ApplyGlobalLODRules() -- Ensure LODs/Clip are forced
    self:ParseCustomPriorities()
    self:_BuildTargetedRegistry()
    self:_BuildSpatialGrid()
    self:_PerformSpawningLogic()

    if UIManager then
        UIManager:SyncRadioButtons()
        UIManager:UpdateStats()
        UIManager:UpdateOverlayText()
    end

    if isTimer(self.timers.spawn) then
        killTimer(self.timers.spawn)
    end
    if isTimer(self.timers.cull) then
        killTimer(self.timers.cull)
    end

    self.timers.spawn = setTimer(function()
        self:_PerformSpawningLogic()
        if UIManager then
            UIManager:UpdateOverlayText()
        end
    end, self.CONFIG.UPDATE_TICK_RATE, 0)

    self.timers.cull = setTimer(function()
        self:_PerformCullingLogic()
        if UIManager then
            UIManager:UpdateStats()
            UIManager:UpdateOverlayText()
        end
    end, self.CONFIG.UPDATE_TICK_RATE, 0)
end

function VisionX:Deactivate(isSwitching)
    if not self.state.isEnabled then
        return
    end
    for _, timer in pairs(self.timers) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    self.timers = {}
    self:_PurgeAllClones()
    self.state.isEnabled = false

    if not isSwitching then
        self.state.activeCategory = false
        self.state.spatialGrid = {}
        self.state.gridBounds = {
            minX = math.huge,
            minY = math.huge,
            minZ = math.huge,
            maxX = -math.huge,
            maxY = -math.huge,
            maxZ = -math.huge,
        }
    end
    -- We do NOT reset LODs to default/low on Deactivate anymore.
    -- We keep the enhanced 325 LOD setting active as requested.
    self:_ApplyGlobalLODRules()

    if UIManager then
        UIManager:SyncRadioButtons()
        UIManager:UpdateStats()
        UIManager:UpdateOverlayText()
    end
end

function VisionX:Refresh(isHardReset, delay, isSilent)
    local lastCategory = self.state.activeCategory
    if self.state.hardRefreshTimer and isTimer(self.state.hardRefreshTimer) then
        return
    end

    if not isSilent and UIManager then
        local msg = isHardReset and "FULL REFRESH..." or "Quick Refresh..."
        UIManager:AddNotification(msg, "warning")
    end

    self:Deactivate(true)
    if isHardReset then
        self.state.masterObjectRegistry = {}
        self.state.uniqueModelIDs = {}
        self.state.objectRegistry = {}
    end

    self.state.hardRefreshTimer = setTimer(function()
        if isHardReset then
            self:_BuildMasterObjectRegistry()
            if UIManager then
                UIManager:UpdateStats()
            end
        end
        if lastCategory then
            self:Activate(lastCategory, true)
            if not isSilent and UIManager then
                UIManager:AddNotification("Mode restored.", "info")
            end
        else
            self:_ApplyGlobalLODRules()
        end
        self.state.hardRefreshTimer = nil
    end, delay or 1000, 1)
end

function VisionX:Initialize()
    if self.state.isInitialized then
        return
    end
    self.state.isInitialized = true

    if UIManager then
        local editor = getResourceFromName("editor_main")
        UIManager.isEditorRunning = (
            editor and getResourceState(editor) == "running"
        )
        UIManager:CreateMainPanel()
        UIManager:CreateSettingsPanel()
        UIManager:CreateExportPanel()
    end

    setFarClipDistance(2500)
    self:_BuildMasterObjectRegistry()
    addEventHandler("onClientRender", root, VisionX.UpdateFPS)
    if UIManager then
        UIManager:AddNotification("VisionX 3.4.0 Loaded.", "info")
    end
end

addEvent("visionx:receiveInitialData", true)
addEventHandler(
    "visionx:receiveInitialData",
    root,
    function(categories, settings, isAdmin, groupTypes)
        VisionX.state.categoryLookup = categories
        VisionX.state.groupTypes = groupTypes or {}
        VisionX.CONFIG = settings
        VisionX.state.isAdmin = isAdmin
        VisionX:Initialize()
    end
)

addEvent("visionx:syncSettings", true)
addEventHandler("visionx:syncSettings", root, function(settings)
    local wasEnabled = VisionX.state.isEnabled
    local activeCategory = VisionX.state.activeCategory
    if wasEnabled then
        VisionX:Deactivate(true)
    end
    VisionX.CONFIG = settings
    if UIManager then
        UIManager:AddNotification("Settings updated.", "warning")
    end
    if wasEnabled then
        VisionX:Activate(activeCategory, true)
    end
end)

addEvent("visionx:receiveGeneratedScript", true)
addEventHandler("visionx:receiveGeneratedScript", root, function(code)
    if UIManager then
        UIManager.generatedCodeCache = code
        if UIManager.Export.window then
            guiSetVisible(UIManager.Export.window, true)
            guiBringToFront(UIManager.Export.window)
            showCursor(true)
        end
    end
end)

addEvent("visionx:receiveMapList", true)
addEventHandler("visionx:receiveMapList", root, function(mapList)
    if UIManager and UIManager.Export.comboMaps then
        guiComboBoxClear(UIManager.Export.comboMaps)
        for _, mapName in ipairs(mapList) do
            guiComboBoxAddItem(UIManager.Export.comboMaps, mapName)
        end
    end
end)

addEvent("visionx:onSaveResult", true)
addEventHandler("visionx:onSaveResult", root, function(success, msg)
    if UIManager then
        UIManager:AddNotification(msg, success and "info" or "error")
        if success then
            guiSetVisible(UIManager.Export.window, false)
            showCursor(false)
        end
    end
end)

-- Bindings
bindKey("z", "down", function()
    if not UIManager or isChatBoxInputActive() or isConsoleActive() then
        return
    end
    UIManager.isPanelVisible = not UIManager.isPanelVisible
    guiSetVisible(UIManager.Main.window, UIManager.isPanelVisible)
    if not UIManager.isPanelVisible and UIManager.Settings.window then
        guiSetVisible(UIManager.Settings.window, false)
    end
    UIManager:UpdateCursorState()
end)

bindKey("l", "down", function()

    VisionX:Refresh(true, 500, false)
end)

addCommandHandler("vx", function(cmd, arg)
    arg = string.lower(arg or "")
    if not UIManager then
        return
    end
    if arg == "deco" or arg == "decoration" then
        VisionX:Activate("Decoration")
        UIManager:AddNotification("Mode set to: Decoration", "info")
    elseif arg == "track" then
        VisionX:Activate("Track")
        UIManager:AddNotification("Mode set to: Track", "info")
    elseif arg == "all" then
        VisionX:Activate("All")
        UIManager:AddNotification("Mode set to: All", "info")
    elseif arg == "off" then
        VisionX:Deactivate()
        UIManager:AddNotification("Mode set to: Off", "error")
    elseif arg == "settings" then
        if VisionX.state.isAdmin then
            UIManager:onSettingsOpen()
            UIManager:UpdateCursorState()
        else
            UIManager:AddNotification("Permission Denied.", "error")
        end
    elseif arg == "build" then
        UIManager:onBuildScript()
        UIManager:UpdateCursorState()
    elseif arg == "stats" then
        UIManager:UpdateStats()
        UIManager:AddNotification("Stats printed to Console (F8)", "info")
    elseif arg == "refresh" then
        UIManager:onRefresh()
    elseif arg == "clones" then
        UIManager.Overlay.isVisible = not UIManager.Overlay.isVisible
        UIManager:AddNotification("Clone overlay toggled.", "info")
    elseif arg == "grid" then
        VisionX.state.isGridVisible = not VisionX.state.isGridVisible
        if VisionX.state.isGridVisible then
            addEventHandler("onClientRender", root, VisionX.RenderGrid)
            UIManager:AddNotification("Grid visualizer ENABLED", "info")
        else
            removeEventHandler("onClientRender", root, VisionX.RenderGrid)
            UIManager:AddNotification("Grid visualizer DISABLED", "info")
        end
    else
        UIManager:AddNotification(
            "Cmds: deco, track, all, off, settings, build, refresh, grid",
            "info"
        )
    end
end)

-- HARD REFRESH TRIGGERS
addEventHandler("onClientPlayerSpawn", localPlayer, function()
    if VisionX.state.isInitialized then
        setTimer(function()
            VisionX:Refresh(true, 500, true)
        end, 1000, 1)
    end
end)

addEvent("onServerSendMapData", true)
addEventHandler("onServerSendMapData", root, function()
    if VisionX.state.isInitialized then
        setTimer(function()
            VisionX:Refresh(true, 500, false)
        end, 5000, 1)
    end
end)

addEventHandler("onClientResourceStart", root, function(res)
    if res == getThisResource() then
        triggerServerEvent("visionx:requestInitialData", localPlayer)
    elseif
        getResourceName(res) == "editor_main" and VisionX.state.isInitialized
    then
        if UIManager then
            UIManager.isEditorRunning = true
        end
        setTimer(function()
            VisionX:Refresh(true, 500, false)
        end, 5000, 1)
    end
end)

addEventHandler("onClientResourceStop", root, function(res)
    if
        getResourceName(res) == "editor_main" and VisionX.state.isInitialized
    then
        if UIManager then
            UIManager.isEditorRunning = false
        end
        setTimer(function()
            VisionX:Refresh(true, 500, false)
        end, 5000, 1)
    end
end)

addEventHandler("onClientCommand", root, function(cmd)
    if cmd == "save" and VisionX.state.isInitialized then
        VisionX:Refresh(true, 100, false)
    end
end)
