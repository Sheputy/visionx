--[[
============================================================
--
--  Author: Corrupt
--  VisionX Advanced - Client-Side Logic
--  Version: 3.2.6 
--
--  CHANGELOG:
--  - Added Export UI Panel for saving scripts to maps.
--  - Added logic to request and display server map resources.
--  - Added clipboard vs direct save toggles.
--
============================================================
]]

-- ////////////////////////////////////////////////////////////////////////////
-- // HELPER FUNCTIONS
-- ////////////////////////////////////////////////////////////////////////////
function table.size(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- ////////////////////////////////////////////////////////////////////////////
-- // SCRIPT INITIALIZATION
-- ////////////////////////////////////////////////////////////////////////////

VisionX = {}
VisionX.state = {}
VisionX.timers = {}

-- ////////////////////////////////////////////////////////////////////////////
-- // CONFIGURATION & STATE
-- ////////////////////////////////////////////////////////////////////////////

-- Default settings, overwritten by the server on connection.
VisionX.CONFIG = {
    MAX_VIEW_RANGE = 1000,
    MIN_VIEW_RANGE = 250,
    CREATION_BATCH_LIMIT = 100,
    UPDATE_TICK_RATE = 500,
    SPATIAL_GRID_CELL_SIZE = 200,
    CLONE_LIMIT = 500, -- ADDED: Hard limit on active clones
    DEBUG_MODE = false,
}

VisionX.state = {
    isInitialized = false,
    isAdmin = false, -- Set by server
    isEnabled = false,
    activeCategory = false, -- false, "Decoration", "Track", or "All"
    masterObjectRegistry = {},
    objectRegistry = {},
    activeClones = {},
    uniqueModelIDs = {},
    categoryLookup = {},
    categoryCounts = { Decoration = 0, Track = 0, OTHER = 0 },
    hardRefreshTimer = nil,
    spatialGrid = {},
    gridBounds = { minX = 0, minY = 0, maxX = 0, maxY = 0 },
}

-- ////////////////////////////////////////////////////////////////////////////
-- // UI MANAGER (Native GUI)
-- ////////////////////////////////////////////////////////////////////////////
UIManager = {
    Main = {},
    Settings = {},
    Overlay = {}, 
    Export = {}, -- ADDED: For file saving
    brandColor = "0DBCFF", 
    isPanelVisible = false, 
    isEditorRunning = false,
    generatedCodeCache = nil,
}

-- === UI CREATION ===

UIManager.Overlay = {
    text = "Active Clones: 0 / 500",
    font = "default-bold",
    screenWidth = 0,
    screenHeight = 0,
    isVisible = true, 
    color = tocolor(0, 255, 0, 255), 
}
local sx, sy = guiGetScreenSize()
UIManager.Overlay.screenWidth = sx
UIManager.Overlay.screenHeight = sy

function UIManager:CreateMainPanel()
    local w, h = 230, 425
    local sx, sy = guiGetScreenSize()
    local x, y = 10, sy / 2 - h / 2
    
    local panel = guiCreateWindow(x, y, w, h, "VisionX v3.2", false)
    guiWindowSetSizable(panel, false)
    guiWindowSetMovable(panel, true)
    UIManager.Main.window = panel
    
    -- Mode Selection
    guiCreateLabel(10, 30, 80, 20, "Mode:", false, panel)
    UIManager.Main.radioOff = guiCreateRadioButton(30, 55, 100, 20, "Off", false, panel)
    UIManager.Main.radioDeco = guiCreateRadioButton(30, 80, 100, 20, "Decoration", false, panel)
    UIManager.Main.radioTrack = guiCreateRadioButton(120, 55, 100, 20, "Track", false, panel)
    UIManager.Main.radioAll = guiCreateRadioButton(120, 80, 100, 20, "All", false, panel)
    
    -- Stats
    local yPos = 115
    guiCreateLabel(10, yPos, 80, 20, "Map Stats:", false, panel)
    yPos = yPos + 25
    UIManager.Main.statCached = guiCreateLabel(20, yPos, 200, 20, "Total Cached: 0", false, panel)
    yPos = yPos + 20
    UIManager.Main.statActive = guiCreateLabel(20, yPos, 200, 20, "Active Objs (Off): 0", false, panel)
    yPos = yPos + 20
    UIManager.Main.statClones = guiCreateLabel(20, yPos, 200, 20, "Active Clones: 0", false, panel)
    yPos = yPos + 25
    
    guiCreateLabel(10, yPos, 100, 20, "Config Stats:", false, panel)
    yPos = yPos + 25
    UIManager.Main.statRange = guiCreateLabel(20, yPos, 200, 20, "View Range: 0 - 0", false, panel)
    yPos = yPos + 20
    UIManager.Main.statGridInfo = guiCreateLabel(20, yPos, 200, 20, "Grid Dims: 0x0 (0 Cells)", false, panel)
    yPos = yPos + 35
    
    -- Actions
    local btnY = yPos
    if VisionX.state.isAdmin then
        UIManager.Main.btnSettings = guiCreateButton(10, btnY, w - 20, 30, "Settings...", false, panel)
        btnY = btnY + 35
    end
    UIManager.Main.btnBuild = guiCreateButton(10, btnY, w - 20, 30, "Build Script...", false, panel)
    btnY = btnY + 35
    UIManager.Main.btnRefresh = guiCreateButton(10, btnY, w - 20, 30, "Refresh (L)", false, panel)
    
    -- Footer
    local footerLabel = guiCreateLabel(10, h - 25, w - 20, 20, "© Corrupt | Discord: @sheputy", false, panel)
    
    -- Align all stat labels
    local statLabels = { UIManager.Main.statCached, UIManager.Main.statActive, UIManager.Main.statClones, UIManager.Main.statRange, UIManager.Main.statGridInfo }
    for _, label in ipairs(statLabels) do
        guiLabelSetHorizontalAlign(label, "left", false)
    end
    guiLabelSetHorizontalAlign(footerLabel, "right", false)
    
    UIManager:SyncRadioButtons()
    UIManager:UpdateStats()
    guiSetVisible(panel, false)
end

function UIManager:CreateSettingsPanel()
    local w, h = 400, 310
    local sx, sy = guiGetScreenSize()
    local x, y = sx / 2 - w / 2, sy / 2 - h / 2
    
    local panel = guiCreateWindow(x, y, w, h, "VisionX Settings", false)
    guiWindowSetSizable(panel, false)
    UIManager.Settings.window = panel
    
    local labels = {
        "Max View Range (500-3000):",
        "Min View Range (0-300):",
        "Creation Batch (5-1000):",
        "Update Tick (50-9000ms):",
        "Spatial Grid (10-3000):",
        "Active Clone Limit (50-3000) Recommended (800):", 
    }
    local keys = { "MAX_VIEW_RANGE", "MIN_VIEW_RANGE", "CREATION_BATCH_LIMIT", "UPDATE_TICK_RATE", "SPATIAL_GRID_CELL_SIZE", "CLONE_LIMIT" } 
    UIManager.Settings.edits = {}
    
    local yPos = 30
    for i, label in ipairs(labels) do
        guiCreateLabel(10, yPos + 4, 180, 25, label, false, panel)
        local edit = guiCreateEdit(200, yPos, w - 210, 25, "", false, panel)
        UIManager.Settings.edits[keys[i]] = edit
        yPos = yPos + 30
    end
    
    UIManager.Settings.btnSave = guiCreateButton(10, h - 40, w / 2 - 15, 30, "Save", false, panel)
    UIManager.Settings.btnClose = guiCreateButton(w / 2 + 5, h - 40, w / 2 - 15, 30, "Close", false, panel)
    
    guiSetVisible(panel, false)
end

-- ADDED: Create the Export Panel (Updated with Instructions)
function UIManager:CreateExportPanel()
    local w, h = 450, 320 -- Increased height for larger text
    local sx, sy = guiGetScreenSize()
    local x, y = sx / 2 - w / 2, sy / 2 - h / 2
    
    local panel = guiCreateWindow(x, y, w, h, "VisionX Export Manager", false)
    guiWindowSetSizable(panel, false)
    UIManager.Export.window = panel
    
    local currentY = 30
    
    -- 1. Main Instruction
    local lblInfo = guiCreateLabel(10, currentY, w - 20, 35, "Select a map resource below to save the standalone script directly, or copy to clipboard.", false, panel)
    guiLabelSetHorizontalAlign(lblInfo, "left", true) -- Enable Word Wrap
    currentY = currentY + 35
    
    -- 2. Map Config Warning (Red & Bigger)
    local lblWarnMap = guiCreateLabel(10, currentY, w - 20, 60, "IMPORTANT: Ensure the target map is currently OPENED in Editor and you have configured the mode [Deco/Track/All] and settings in /vx settings.", false, panel)
    guiLabelSetColor(lblWarnMap, 52, 235, 113) -- Red
    guiLabelSetHorizontalAlign(lblWarnMap, "left", true)
    guiSetFont(lblWarnMap, "clear-normal") -- Bigger font
    currentY = currentY + 60
    
    -- 3. ACL Warning (Yellow)
    local resName = getResourceName(getThisResource())
    local aclText = string.format("PERMISSIONS: This resource needs Admin rights to save files.\nUse: /aclrequest allow %s all\nOr add 'resource.%s' to the Admin ACL group.", resName, resName)
    
    local lblWarnACL = guiCreateLabel(10, currentY, w - 20, 55, aclText, false, panel)
    guiLabelSetColor(lblWarnACL, 255, 255, 100) -- Yellow
    guiLabelSetHorizontalAlign(lblWarnACL, "left", true)
    guiSetFont(lblWarnACL, "default-bold-small") -- Bigger font
    currentY = currentY + 60
    
    -- Combobox
    UIManager.Export.comboMaps = guiCreateComboBox(10, currentY, w - 20, 150, "Select Map...", false, panel)
    currentY = currentY + 40
    
    -- Buttons
    UIManager.Export.btnSave = guiCreateButton(10, currentY, (w/2)-15, 35, "Save to Map", false, panel)
    guiSetProperty(UIManager.Export.btnSave, "NormalTextColour", "FFAAFF00")
    
    UIManager.Export.btnCopy = guiCreateButton((w/2)+5, currentY, (w/2)-15, 35, "Copy to Clipboard", false, panel)
    currentY = currentY + 45
    
    UIManager.Export.btnClose = guiCreateButton(10, currentY, w - 20, 30, "Close", false, panel)
    
    guiSetVisible(panel, false)
end

-- === UI EVENT HANDLERS ===

addEventHandler("onClientGUIClick", root, function()
    local main = UIManager.Main
    local settings = UIManager.Settings
    local export = UIManager.Export

    -- Main Panel Buttons
    if source == main.btnSettings then
        UIManager:onSettingsOpen()
        UIManager:UpdateCursorState()
    elseif source == main.btnBuild then
        UIManager:onBuildScript()
        UIManager:UpdateCursorState()
    elseif source == main.btnRefresh then
        UIManager:onRefresh()
    
    -- Mode Radio Buttons
    elseif source == main.radioOff then
        if VisionX.state.isEnabled then
            VisionX:Deactivate()
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #ffaaaaOff", 255, 255, 255, true)
        end
    elseif source == main.radioDeco then
        VisionX:Activate("Decoration")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaDecoration", 255, 255, 255, true)
    elseif source == main.radioTrack then
        VisionX:Activate("Track")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaTrack", 255, 255, 255, true)
    elseif source == main.radioAll then
        VisionX:Activate("All")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaAll", 255, 255, 255, true)

    -- Settings Panel Buttons
    elseif source == settings.btnSave then
        UIManager:onSettingsSave()
        UIManager:UpdateCursorState()
    elseif source == settings.btnClose then
        UIManager:onSettingsClose()
        UIManager:UpdateCursorState()

    -- Export Panel Buttons
    elseif source == export.btnCopy then
        if UIManager.generatedCodeCache then
            setClipboard(UIManager.generatedCodeCache)
            outputChatBox("[VisionX] #00FF00Code copied to clipboard!", 255, 255, 255, true)
        end
        
    elseif source == export.btnSave then
        local item = guiComboBoxGetSelected(export.comboMaps)
        local mapName = guiComboBoxGetItemText(export.comboMaps, item)
        
        if not mapName or mapName == "" or item == -1 then
            outputChatBox("[VisionX] #FF0000Please select a map first.", 255, 255, 255, true)
            return
        end
        
        if UIManager.generatedCodeCache then
            triggerServerEvent("visionx:saveToMap", localPlayer, mapName, UIManager.generatedCodeCache)
        end
        
    elseif source == export.btnClose then
        guiSetVisible(export.window, false)
        UIManager:UpdateCursorState()
    end
end)

-- Handle window close 'X' button
addEventHandler("onClientGUIClose", root, function()
    if source == UIManager.Main.window then
        UIManager.isPanelVisible = false 
        guiSetVisible(UIManager.Main.window, false)
        UIManager:UpdateCursorState()
    elseif source == UIManager.Settings.window then
        guiSetVisible(UIManager.Settings.window, false)
        UIManager:UpdateCursorState()
    elseif source == UIManager.Export.window then
        guiSetVisible(UIManager.Export.window, false)
        UIManager:UpdateCursorState()
    end
end)


-- === UI ACTION FUNCTIONS ===

function UIManager:UpdateCursorState()
    if UIManager.isEditorRunning then
        return
    end
    
    local settingsVisible = UIManager.Settings.window and guiGetVisible(UIManager.Settings.window)
    local exportVisible = UIManager.Export.window and guiGetVisible(UIManager.Export.window)
    
    showCursor(UIManager.isPanelVisible or settingsVisible or exportVisible)
end

function UIManager:UpdateStats()
    if not UIManager.Main.statCached or not isElement(UIManager.Main.statCached) then return end
    
    local state = VisionX.state
    local config = VisionX.CONFIG
    
    guiSetText(UIManager.Main.statCached, string.format("Total Cached: %d", table.size(state.masterObjectRegistry)))
    local categoryName = state.activeCategory or "Off"
    guiSetText(UIManager.Main.statActive, string.format("Active Objs (%s): %d", categoryName, table.size(state.objectRegistry)))
    guiSetText(UIManager.Main.statClones, string.format("Active Clones: %d / %d", table.size(state.activeClones), config.CLONE_LIMIT))
    guiSetText(UIManager.Main.statRange, string.format("View Range: %d - %d", config.MIN_VIEW_RANGE, config.MAX_VIEW_RANGE))
    
    local gridDims = "0x0 (0 Cells)"
    local cellCount = table.size(state.spatialGrid)
    if cellCount > 0 then
        local b = state.gridBounds
        local dimX = (b.maxX - b.minX) + 1
        local dimY = (b.maxY - b.minY) + 1
        gridDims = string.format("%dx%d (%d Cells)", dimX, dimY, cellCount)
    end
    guiSetText(UIManager.Main.statGridInfo, "Grid Dims: " .. gridDims)
end

function UIManager:SyncRadioButtons()
    if not UIManager.Main.radioOff or not isElement(UIManager.Main.radioOff) then return end

    local category = VisionX.state.activeCategory
    guiRadioButtonSetSelected(UIManager.Main.radioOff, category == false)
    guiRadioButtonSetSelected(UIManager.Main.radioDeco, category == "Decoration")
    guiRadioButtonSetSelected(UIManager.Main.radioTrack, category == "Track")
    guiRadioButtonSetSelected(UIManager.Main.radioAll, category == "All")
end

function UIManager:onSettingsOpen()
    if not UIManager.Settings.window or not isElement(UIManager.Settings.window) then return end
    
    for key, edit in pairs(UIManager.Settings.edits) do
        guiSetText(edit, tostring(VisionX.CONFIG[key]))
    end
    guiSetVisible(UIManager.Settings.window, true)
end

function UIManager:onSettingsClose()
    if not UIManager.Settings.window or not isElement(UIManager.Settings.window) then return end
    guiSetVisible(UIManager.Settings.window, false)
end

function UIManager:onSettingsSave()
    local newConfig = {}
    local edits = UIManager.Settings.edits
    
    local function getClampedValue(key, min, max)
        local num = tonumber(guiGetText(edits[key])) or VisionX.CONFIG[key]
        if num < min then num = min end
        if num > max then num = max end
        return num
    end
    
    newConfig.MAX_VIEW_RANGE = getClampedValue("MAX_VIEW_RANGE", 500, 3000)
    newConfig.MIN_VIEW_RANGE = getClampedValue("MIN_VIEW_RANGE", 0, 300)
    newConfig.CREATION_BATCH_LIMIT = getClampedValue("CREATION_BATCH_LIMIT", 1, 1000)
    newConfig.UPDATE_TICK_RATE = getClampedValue("UPDATE_TICK_RATE", 1, 9000)
    newConfig.SPATIAL_GRID_CELL_SIZE = getClampedValue("SPATIAL_GRID_CELL_SIZE", 1, 3000)
    newConfig.CLONE_LIMIT = getClampedValue("CLONE_LIMIT", 50, 3000) 
    newConfig.DEBUG_MODE = VisionX.CONFIG.DEBUG_MODE 
    
    triggerServerEvent("visionx:saveSettings", localPlayer, newConfig)
    
    UIManager:onSettingsClose()
end

function UIManager:onBuildScript()
    if not VisionX or not VisionX.state.isInitialized then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaPlease wait for the main script to initialize before building.", 255, 255, 255, true)
        return
    end

    local currentCategory = VisionX.state.activeCategory or "Decoration"
    
    triggerServerEvent("visionx:buildScript", localPlayer, VisionX.CONFIG, currentCategory, VisionX.state.uniqueModelIDs)
    triggerServerEvent("visionx:requestMapList", localPlayer)
    
    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Generating script using current server settings for category: #aaffaa" .. currentCategory, 255,255,255, true)
    
    guiSetVisible(UIManager.Main.window, false)
    guiSetVisible(UIManager.Settings.window, false)
    UIManager.isPanelVisible = false 
end

function UIManager:onRefresh(isSilent)
    if VisionX and VisionX.state.isInitialized then
        if not isSilent then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Performing #aaffaaHARD REFRESH#ffffff...", 255, 255, 255, true)
        end
        VisionX:Refresh(true, 1000, isSilent)
    else
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaVisionX is not initialized yet.", 255, 255, 255, true)
    end
end

function UIManager:UpdateOverlayText()
    local count = table.size(VisionX.state.activeClones)
    local limit = VisionX.CONFIG.CLONE_LIMIT
    UIManager.Overlay.text = string.format("Active Clones: %d / %d", count, limit)
    
    local percentage = count / limit
    if percentage >= 0.9 then
        UIManager.Overlay.color = tocolor(255, 50, 50, 255) 
    elseif percentage >= 0.75 then
        UIManager.Overlay.color = tocolor(255, 165, 0, 255) 
    else
        UIManager.Overlay.color = tocolor(50, 255, 50, 255) 
    end
end

function UIManager:RenderOverlay()
    if not UIManager.Overlay.isVisible then
        return
    end
    
    if not VisionX.state.isEnabled then
        return
    end
    
    local text = UIManager.Overlay.text 
    local x = UIManager.Overlay.screenWidth / 2 
    local y = UIManager.Overlay.screenHeight - 40 
    
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 200), 1.2, UIManager.Overlay.font, "center", "bottom")
    dxDrawText(text, x, y, x, y, UIManager.Overlay.color, 1.2, UIManager.Overlay.font, "center", "bottom")
end

-- === KEYBINDS & COMMANDS ===

bindKey("z", "down", function()
    if isChatBoxInputActive() or isConsoleActive() then return end
    
    if UIManager.Main.window and isElement(UIManager.Main.window) then
        UIManager.isPanelVisible = not UIManager.isPanelVisible
        guiSetVisible(UIManager.Main.window, UIManager.isPanelVisible)
        
        if not UIManager.isPanelVisible and UIManager.Settings.window and isElement(UIManager.Settings.window) then
            guiSetVisible(UIManager.Settings.window, false)
        end
        
        UIManager:UpdateCursorState()
    end
end)

bindKey("l", "down", function()
    if isChatBoxInputActive() or isConsoleActive() then return end
    UIManager:onRefresh()
end)

addCommandHandler("visionx_refresh", function()
    UIManager:onRefresh()
end)

addCommandHandler("vx", function(cmd, arg)
    arg = string.lower(arg or "")
    if arg == "deco" or arg == "decoration" then
        VisionX:Activate("Decoration")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaDecoration", 255, 255, 255, true)
    elseif arg == "track" then
        VisionX:Activate("Track")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaTrack", 255, 255, 255, true)
    elseif arg == "all" then
        VisionX:Activate("All")
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #aaffaaAll", 255, 255, 255, true)
    elseif arg == "off" then
        VisionX:Deactivate()
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Mode set to: #ffaaaaOff", 255, 255, 255, true)
    elseif arg == "settings" then
        if VisionX.state.isAdmin then
            UIManager:onSettingsOpen()
            UIManager:UpdateCursorState() 
        else
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaYou do not have permission to open settings.", 255, 255, 255, true)
        end
    elseif arg == "build" then
        UIManager:onBuildScript()
        UIManager:UpdateCursorState() 
    elseif arg == "stats" then
        UIManager:UpdateStats() 
        local state = VisionX.state
        local config = VisionX.CONFIG
        local b = state.gridBounds
        local cellCount = table.size(state.spatialGrid)
        local dimX = (b.maxX - b.minX) + 1
        local dimY = (b.maxY - b.minY) + 1
        local gridDims = (cellCount > 0) and string.format("%dx%d (%d Cells)", dimX, dimY, cellCount) or "0x0 (0 Cells)"

        outputChatBox("[#"..UIManager.brandColor.."VisionX Stats#ffffff] ----------------", 255, 255, 255, true)
        outputChatBox(string.format("  Mode: #aaffaa%s#ffffff | Clones: #aaffaa%d / %d", state.activeCategory or "Off", table.size(state.activeClones), config.CLONE_LIMIT), 255, 255, 255, true)
        outputChatBox(string.format("  Cached Objs: #aaffaa%d#ffffff | Active Objs: #aaffaa%d", table.size(state.masterObjectRegistry), table.size(state.objectRegistry)), 255, 255, 255, true)
        outputChatBox(string.format("  Range: #aaffaa%d - %d#ffffff | Grid Dims: #aaffaa%s", config.MIN_VIEW_RANGE, config.MAX_VIEW_RANGE, gridDims), 255, 255, 255, true)

    elseif arg == "refresh" then
        UIManager:onRefresh()
    elseif arg == "clones" then 
        UIManager.Overlay.isVisible = not UIManager.Overlay.isVisible
        if UIManager.Overlay.isVisible then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaaClone overlay enabled.", 255, 255, 255, true)
        else
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaClone overlay disabled.", 255, 255, 255, true)
        end
    else
        outputChatBox("Usage: /vx [deco|track|all|off|settings|build|stats|refresh|clones]", 255, 255, 255, true)
    end
end)

-- ////////////////////////////////////////////////////////////////////////////
-- // CORE VISIONX LOGIC
-- ////////////////////////////////////////////////////////////////////////////

local function _isModelIncluded(modelId, activeCategory)
    if not activeCategory then return false end
    local objectCategory = VisionX.state.categoryLookup[modelId] or "OTHER"
    if activeCategory == "All" then
        return objectCategory == "Decoration" or objectCategory == "Track"
    else
        return objectCategory == activeCategory
    end
end

function VisionX:_BuildMasterObjectRegistry()
    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Performing initial scan of all map objects. This may take a moment...", 255, 255, 255, true)
    self.state.masterObjectRegistry = {}
    self.state.uniqueModelIDs = {}
    local allGameObjects = getElementsByType("object")
    local playerDimension = getElementDimension(localPlayer)

    for _, entity in ipairs(allGameObjects) do
        if not getElementData(entity, "visionx_clone") and getElementDimension(entity) == playerDimension then
            
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
                    interior = getElementInterior(entity)
                }
                self.state.uniqueModelIDs[modelId] = true
            end
        end
    end
    outputChatBox(string.format("[#"..UIManager.brandColor.."VisionX#ffffff] Map scan complete. Cached %d objects.", table.size(self.state.masterObjectRegistry)), 255, 255, 255, true)

    local categoryCounts = { Decoration = 0, Track = 0, OTHER = 0 }
    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        local category = self.state.categoryLookup[modelId] or "OTHER"
        categoryCounts[category] = (categoryCounts[category] or 0) + 1
    end
    self.state.categoryCounts = categoryCounts
end

function VisionX:_BuildTargetedRegistry()
    self.state.objectRegistry = {}
    local activeCategory = self.state.activeCategory
    if not activeCategory then return end

    for entity, data in pairs(self.state.masterObjectRegistry) do
        if _isModelIncluded(data.model, activeCategory) then
            self.state.objectRegistry[entity] = data
        end
    end
end

function VisionX:_BuildSpatialGrid()
    self.state.spatialGrid = {}
    self.state.gridBounds = { minX = 9999, minY = 9999, maxX = -9999, maxY = -9999 }
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    if not cellSize or cellSize <= 0 then cellSize = 250 end 

    for entity, data in pairs(self.state.objectRegistry) do
        local gridX = math.floor(data.pos[1] / cellSize)
        local gridY = math.floor(data.pos[2] / cellSize)
        
        if gridX < self.state.gridBounds.minX then self.state.gridBounds.minX = gridX end
        if gridX > self.state.gridBounds.maxX then self.state.gridBounds.maxX = gridX end
        if gridY < self.state.gridBounds.minY then self.state.gridBounds.minY = gridY end
        if gridY > self.state.gridBounds.maxY then self.state.gridBounds.maxY = gridY end
        
        local key = gridX .. "_" .. gridY
        if not self.state.spatialGrid[key] then
            self.state.spatialGrid[key] = {}
        end
        table.insert(self.state.spatialGrid[key], entity)
    end
    
    UIManager:UpdateStats()
end

function VisionX:_ResetAllModelsLOD(distance)
    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        engineSetModelLODDistance(modelId, distance)
    end
end

function VisionX:_HandleStreamIn(element)
    if getElementType(element) ~= "object" or getElementData(element, "visionx_clone") or getElementDimension(element) ~= getElementDimension(localPlayer) then return end

    local modelId = getElementModel(element)
    self.state.uniqueModelIDs[modelId] = true

    local scale = getObjectScale(element)
    local alpha = getElementAlpha(element)

    if not self.state.masterObjectRegistry[element] and (scale >= 0.1 and scale <= 400) and (alpha >= 50) then
        local pX, pY, pZ = getElementPosition(element)
        local rX, rY, rZ = getElementRotation(element)
        self.state.masterObjectRegistry[element] = {
            model = modelId,
            pos = { pX, pY, pZ },
            rot = { rX, rY, rZ },
            scale = scale,
            dimension = getElementDimension(element),
            interior = getElementInterior(element)
        }
        if self.state.isEnabled and _isModelIncluded(modelId, self.state.activeCategory) then
            self.state.objectRegistry[element] = self.state.masterObjectRegistry[element]
            local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
            local gridX = math.floor(pX / cellSize)
            local gridY = math.floor(pY / cellSize)
            local key = gridX .. "_" .. gridY
            if not self.state.spatialGrid[key] then self.state.spatialGrid[key] = {} end
            table.insert(self.state.spatialGrid[key], element)
        end
    end

    if self.state.isEnabled and _isModelIncluded(modelId, self.state.activeCategory) then
        engineSetModelLODDistance(modelId, self.CONFIG.MIN_VIEW_RANGE)
    else
        engineSetModelLODDistance(modelId, 1000)
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
    local clonesToCull = {}
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE

    for sourceElement, cloneInstance in pairs(self.state.activeClones) do
        if not isElement(sourceElement) or not isElement(cloneInstance) then
            table.insert(clonesToCull, sourceElement)
        else
            local sourceData = self.state.masterObjectRegistry[sourceElement]
            if not sourceData or sourceData.dimension ~= playerDim then
                table.insert(clonesToCull, sourceElement)
            else
                local dx, dy, dz = sourceData.pos[1] - camX, sourceData.pos[2] - camY, sourceData.pos[3] - camZ
                local distSq = dx*dx + dy*dy + dz*dz
                
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

function VisionX:_PerformSpawningLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local createdThisCycle = 0
    
    local currentCloneCount = table.size(self.state.activeClones)
    if currentCloneCount >= self.CONFIG.CLONE_LIMIT then
        return 
    end
    
    local minRangeSq = self.CONFIG.MIN_VIEW_RANGE * self.CONFIG.MIN_VIEW_RANGE
    local maxRangeSq = self.CONFIG.MAX_VIEW_RANGE * self.CONFIG.MAX_VIEW_RANGE
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    
    local searchRadius = math.ceil(self.CONFIG.MAX_VIEW_RANGE / cellSize)
    local pGridX = math.floor(camX / cellSize)
    local pGridY = math.floor(camY / cellSize)
    
    local screenWidth, screenHeight = UIManager.Overlay.screenWidth, UIManager.Overlay.screenHeight
    local screenBuffer = 200 
    
    for i = -searchRadius, searchRadius do
        for j = -searchRadius, searchRadius do
            local key = (pGridX + i) .. "_" .. (pGridY + j)
            if self.state.spatialGrid[key] then
                for _, sourceElement in ipairs(self.state.spatialGrid[key]) do
                    if createdThisCycle >= self.CONFIG.CREATION_BATCH_LIMIT then return end
                    
                    if (currentCloneCount + createdThisCycle) >= self.CONFIG.CLONE_LIMIT then
                        return 
                    end
                    
                    local data = self.state.objectRegistry[sourceElement]
                    if data and not self.state.activeClones[sourceElement] and data.dimension == playerDim then
                        local dx, dy, dz = data.pos[1] - camX, data.pos[2] - camY, data.pos[3] - camZ
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq >= minRangeSq and distSq <= maxRangeSq then
                            
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
-- // PUBLIC API METHODS
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:Activate(category, isRefresh)
    if self.state.isEnabled and self.state.activeCategory == category and not isRefresh then return end
    
    if self.state.isEnabled then
        self:Deactivate(true)
    end
    
    self.state.isEnabled = true
    self.state.activeCategory = category
    self:_ResetAllModelsLOD(1000)

    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        if _isModelIncluded(modelId, self.state.activeCategory) then
            engineSetModelLODDistance(modelId, self.CONFIG.MIN_VIEW_RANGE)
        end
    end
    
    self:_BuildTargetedRegistry()
    self:_BuildSpatialGrid()
    self:_PerformSpawningLogic() 
    UIManager:SyncRadioButtons() 
    UIManager:UpdateStats()      
    UIManager:UpdateOverlayText() 

    if isTimer(self.timers.spawn) then killTimer(self.timers.spawn) end
    if isTimer(self.timers.cullDelay) then killTimer(self.timers.cullDelay) end
    if isTimer(self.timers.cull) then killTimer(self.timers.cull) end
    
    self.timers.spawn = setTimer(function() 
        self:_PerformSpawningLogic() 
        UIManager:UpdateOverlayText() 
    end, self.CONFIG.UPDATE_TICK_RATE, 0)
    
    self.timers.cullDelay = setTimer(function()
        self.timers.cull = setTimer(function()
            self:_PerformCullingLogic()
            UIManager:UpdateStats() 
            UIManager:UpdateOverlayText() 
        end, self.CONFIG.UPDATE_TICK_RATE, 0)
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
end

function VisionX:Deactivate(isSwitching)
    if not self.state.isEnabled then return end
    
    for _, timer in pairs(self.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    self.timers = {}
    
    self:_PurgeAllClones()
    self.state.isEnabled = false
    
    if not isSwitching then
        self.state.activeCategory = false
        self.state.spatialGrid = {}
        self.state.gridBounds = { minX = 0, minY = 0, maxX = 0, maxY = 0 }
    end
    
    self:_ResetAllModelsLOD(1000) 
    UIManager:SyncRadioButtons() 
    UIManager:UpdateStats() 
    UIManager:UpdateOverlayText() 
end

function VisionX:Refresh(isHardReset, delay, isSilent)
    local lastCategory = self.state.activeCategory
    
    if self.state.hardRefreshTimer and isTimer(self.state.hardRefreshTimer) then return end

    if isHardReset then
        if not isSilent then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Full refresh triggered. Please wait...", 255, 255, 255, true)
        end
        self:Deactivate(true)
        self.state.masterObjectRegistry = {}
        self.state.uniqueModelIDs = {}
    else
        if not isSilent then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Refreshing system...", 255, 255, 255, true)
        end
        self:Deactivate(true)
    end

    self.state.hardRefreshTimer = setTimer(function()
        if isHardReset then
            self:_BuildMasterObjectRegistry()
            UIManager:UpdateStats() 
        end
        
        if lastCategory then
            self:Activate(lastCategory, true)
            if not isSilent or (isHardReset and VisionX.state.isAdmin) then
                local message = isHardReset and "Hard refresh successful." or "Refresh complete."
                outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaa" .. message .. " Mode '"..lastCategory.."' re-activated.", 255, 255, 255, true)
            end
        else
            self:_ResetAllModelsLOD(1000)
            if not isSilent or (isHardReset and VisionX.state.isAdmin) then
                local message = isHardReset and "Hard refresh successful." or "Refresh complete."
                outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaa" .. message .. " System is inactive.", 255, 255, 255, true)
            end
        end
        self.state.hardRefreshTimer = nil
    end, delay, 1)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // EVENT HANDLERS & INITIALIZATION
-- ////////////////////////////////////////////////////////////////////////////

function VisionX:Initialize()
    if self.state.isInitialized then return end
    self.state.isInitialized = true

    local editor = getResourceFromName("editor_main")
    if editor and getResourceState(editor) == "running" then
        UIManager.isEditorRunning = true
    else
        local race = getResourceFromName("race")
        if race and getResourceState(race) == "running" then
            UIManager.isEditorRunning = false
        end
    end

    UIManager:CreateMainPanel()
    UIManager:CreateSettingsPanel()
    UIManager:CreateExportPanel() -- Initialize the new Export Panel
    
    self:_BuildMasterObjectRegistry()
    
    addEventHandler("onClientElementDestroy", root, function()
        if source and VisionX.state.masterObjectRegistry[source] then
            if VisionX.state.activeClones[source] then
                if isElement(VisionX.state.activeClones[source]) then
                    destroyElement(VisionX.state.activeClones[source])
                end
                VisionX.state.activeClones[source] = nil
            end
            VisionX.state.masterObjectRegistry[source] = nil
            VisionX.state.objectRegistry[source] = nil
        end
    end)

    addEventHandler("onClientObjectCreate", root, function()
        if source and not getElementData(source, "visionx_clone") then
            VisionX:_HandleStreamIn(source)
        end
    end)

    addEventHandler("onClientElementStreamIn", root, function()
        if source then
            VisionX:_HandleStreamIn(source)
        end
    end)

    addEventHandler("onClientRender", root, function()
        UIManager:RenderOverlay()
    end)
    
    addEventHandler("onClientScreenSizeChange", root,
        function (width, height)
            UIManager.Overlay.screenWidth = width
            UIManager.Overlay.screenHeight = height
        end
    )

    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] v3.2 Loaded. Press #aaffaaZ#ffffff to toggle panel. #aaffaa/vx [mode]#ffffff for commands.", 255, 255, 255, true)
    self:_ResetAllModelsLOD(1000)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // RACE MAP READY (AFTER FULL LOAD)
-- ////////////////////////////////////////////////////////////////////////////

local lastMapRefreshTick = 0

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    if VisionX and VisionX.state.isInitialized then
        local now = getTickCount()
        if now - lastMapRefreshTick > 5000 then 
            VisionX:Refresh(true, 2000, true) 
            lastMapRefreshTick = now
        end
    end
end)

-- ////////////////////////////////////////////////////////////////////////////
-- // RESOURCE START / STOP EVENTS
-- ////////////////////////////////////////////////////////////////////////////

addEventHandler("onClientResourceStart", root, function(startedResource)
    if startedResource == getThisResource() then
        triggerServerEvent("visionx:requestInitialData", localPlayer)
        
    elseif getResourceName(startedResource) == "editor_main" then
        UIManager.isEditorRunning = true
        showCursor(false) 
        if UIManager.isPanelVisible and UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, true)
        end
        
    elseif getResourceName(startedResource) == "race" then
        UIManager.isEditorRunning = false
        UIManager.isPanelVisible = false
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, false)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            guiSetVisible(UIManager.Settings.window, false)
        end
        showCursor(false)
    end
end)

addEventHandler("onClientResourceStop", root, function(stoppedResource)
    if stoppedResource == getThisResource() then
        VisionX:Deactivate()
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            destroyElement(UIManager.Main.window)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            destroyElement(UIManager.Settings.window)
        end
        if UIManager.Export.window and isElement(UIManager.Export.window) then
            destroyElement(UIManager.Export.window)
        end
        
    elseif getResourceName(stoppedResource) == "editor_main" then
        UIManager.isEditorRunning = false
        UIManager.isPanelVisible = false
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, false)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            guiSetVisible(UIManager.Settings.window, false)
        end
        showCursor(false)
        print("[VisionX] editor_main stopped. GUI hidden and cursor forced off.")
        
    elseif getResourceName(stoppedResource) == "race" then
        UIManager.isEditorRunning = false
        UIManager:UpdateCursorState()
    end
end)

-- ////////////////////////////////////////////////////////////////////////////
-- // SERVER → CLIENT SYNC
-- ////////////////////////////////////////////////////////////////////////////

addEvent("visionx:receiveInitialData", true)
addEventHandler("visionx:receiveInitialData", root, function(categories, settings, isAdmin) 
    VisionX.state.categoryLookup = categories 
    local newCloneLimit = settings.CLONE_LIMIT or VisionX.CONFIG.CLONE_LIMIT
    VisionX.CONFIG = settings 
    VisionX.CONFIG.CLONE_LIMIT = newCloneLimit
    VisionX.state.isAdmin = isAdmin
    VisionX:Initialize() 
end)

addEvent("visionx:syncSettings", true)
addEventHandler("visionx:syncSettings", root, function(settings)
    local wasEnabled = VisionX.state.isEnabled
    local activeCategory = VisionX.state.activeCategory
    
    if wasEnabled then VisionX:Deactivate(true) end
    
    local newCloneLimit = settings.CLONE_LIMIT or VisionX.CONFIG.CLONE_LIMIT
    VisionX.CONFIG = settings
    VisionX.CONFIG.CLONE_LIMIT = newCloneLimit
    
    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaaGlobal settings have been updated by an admin.", 255, 255, 255, true)
    
    if wasEnabled then 
        VisionX:Activate(activeCategory, true) 
    end
    
    UIManager:UpdateStats()
end)

addEvent("visionx:onSettingsSaved", true)
addEventHandler("visionx:onSettingsSaved", root, function(success, message)
    if success then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaa" .. message, 255, 255, 255, true)
        if VisionX.state.isAdmin then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] --- New Settings ---", 255, 255, 255, true)
            outputChatBox(string.format("  Range: #aaffaa%d - %d#ffffff | Tick: #aaffaa%dms", VisionX.CONFIG.MIN_VIEW_RANGE, VisionX.CONFIG.MAX_VIEW_RANGE, VisionX.CONFIG.UPDATE_TICK_RATE), 255, 255, 255, true)
            outputChatBox(string.format("  Grid: #aaffaa%d#ffffff | Batch: #aaffaa%d | Clone Limit: #aaffaa%d", VisionX.CONFIG.SPATIAL_GRID_CELL_SIZE, VisionX.CONFIG.CREATION_BATCH_LIMIT, VisionX.CONFIG.CLONE_LIMIT), 255, 255, 255, true)
        end
    else
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaa" .. message, 255, 255, 255, true)
    end
end)

addEvent("visionx:receiveGeneratedScript", true)
addEventHandler("visionx:receiveGeneratedScript", root, function(code)
    UIManager.generatedCodeCache = code
    
    -- Show the Export Panel if not visible
    if UIManager.Export.window then
        guiSetVisible(UIManager.Export.window, true)
        guiBringToFront(UIManager.Export.window)
        showCursor(true)
    end
end)

addEvent("visionx:receiveMapList", true)
addEventHandler("visionx:receiveMapList", root, function(mapList)
    if not UIManager.Export.comboMaps then return end
    guiComboBoxClear(UIManager.Export.comboMaps)
    for _, mapName in ipairs(mapList) do
        guiComboBoxAddItem(UIManager.Export.comboMaps, mapName)
    end
end)

addEvent("visionx:onSaveResult", true)
addEventHandler("visionx:onSaveResult", root, function(success, msg)
    if success then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #00FF00" .. msg, 255, 255, 255, true)
        guiSetVisible(UIManager.Export.window, false) -- Close on success
        showCursor(false)
    else
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #FF0000Error: " .. msg, 255, 255, 255, true)
    end
end)

addEvent("visionx:receiveBuildError", true)
addEventHandler("visionx:receiveBuildError", root, function(errMsg)
    outputChatBox("[#"..UIManager.brandColor.."VisionX Builder ERROR#ffffff] " .. errMsg, 255, 100, 100, true)
end)