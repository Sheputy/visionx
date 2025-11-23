--[[
============================================================
--
--  Author: Corrupt
--  VisionX Advanced - Client-Side Logic
--  Version: 3.2.3 (Automatic Save & UI Integration)
--
--  CHANGELOG:
--  - Added GUI for Map Selection in Build Script dialog.
--  - Modified 'Build Script' logic to send map name to server 
--    for automatic file saving and meta.xml update.
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
    availableMapResources = {}, -- ADDED: For map selection
}

-- ////////////////////////////////////////////////////////////////////////////
-- // UI MANAGER (Native GUI)
-- ////////////////////////////////////////////////////////////////////////////
UIManager = {
    Main = {},
    Settings = {},
    Overlay = {}, 
    BuildDialog = {}, -- NEW: For map selection before build
    brandColor = "0DBCFF", 
    isPanelVisible = false,
    isEditorRunning = false,
}

-- === UI CREATION ===

-- ADDED: Initialize the overlay settings
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

-- This function is called once to build the main panel
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
    UIManager.Main.btnBuild = guiCreateButton(10, btnY, w - 20, 30, "Build & Save Script...", false, panel) -- MODIFIED TEXT
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
    
    -- Set initial state
    UIManager:SyncRadioButtons()
    UIManager:UpdateStats()
    -- Panel starts hidden by default
    guiSetVisible(panel, false)
end

-- ADDED: New dialog for map selection
function UIManager:CreateBuildDialog()
    local w, h = 350, 150
    local sx, sy = guiGetScreenSize()
    local x, y = sx / 2 - w / 2, sy / 2 - h / 2
    
    local panel = guiCreateWindow(x, y, w, h, "VisionX Standalone Builder", false)
    guiWindowSetSizable(panel, false)
    UIManager.BuildDialog.window = panel
    
    guiCreateLabel(10, 30, w - 20, 20, "Select the map resource to save the script to:", false, panel)
    
    UIManager.BuildDialog.mapCombo = guiCreateComboBox(10, 55, w - 20, 25, "Choose Map...", false, panel)
    
    UIManager.BuildDialog.btnSave = guiCreateButton(10, h - 40, (w / 2) - 15, 30, "Save Script", false, panel)
    UIManager.BuildDialog.btnClose = guiCreateButton((w / 2) + 5, h - 40, (w / 2) - 15, 30, "Cancel", false, panel)
    
    guiSetVisible(panel, false)
end


-- This function is called once to build the settings panel
function UIManager:CreateSettingsPanel()
    local w, h = 400, 310 -- MODIFIED: Increased height for new option
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
        "Active Clone Limit (50-3000) Recommended (800):", -- ADDED
    }
    local keys = { "MAX_VIEW_RANGE", "MIN_VIEW_RANGE", "CREATION_BATCH_LIMIT", "UPDATE_TICK_RATE", "SPATIAL_GRID_CELL_SIZE", "CLONE_LIMIT" } -- ADDED
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


-- === UI EVENT HANDLERS ===

-- This single handler processes all GUI clicks
addEventHandler("onClientGUIClick", root, function()
    local main = UIManager.Main
    local settings = UIManager.Settings
    local build = UIManager.BuildDialog

    -- Main Panel Buttons
    if source == main.btnSettings then
        UIManager:onSettingsOpen()
        UIManager:UpdateCursorState()
    elseif source == main.btnBuild then
        UIManager:onBuildOpen() -- MODIFIED: Opens map selection dialog
        UIManager:UpdateCursorState()
    elseif source == main.btnRefresh then
        UIManager:onRefresh()
    
    -- Build Dialog Buttons (NEW)
    elseif source == build.btnSave then
        UIManager:onBuildSave()
        UIManager:UpdateCursorState()
    elseif source == build.btnClose then
        UIManager:onBuildClose()
        UIManager:UpdateCursorState()

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
    end
end)

-- Handle window close 'X' button
addEventHandler("onClientGUIClose", root, function()
    if source == UIManager.Main.window then
        UIManager.isPanelVisible = false -- Set state to hidden
        guiSetVisible(UIManager.Main.window, false)
        UIManager:UpdateCursorState()
    elseif source == UIManager.Settings.window then
        guiSetVisible(UIManager.Settings.window, false)
        UIManager:UpdateCursorState()
    elseif source == UIManager.BuildDialog.window then -- NEW
        guiSetVisible(UIManager.BuildDialog.window, false)
        UIManager:UpdateCursorState()
    end
end)


-- === UI ACTION FUNCTIONS ===

--
-- *** THIS IS THE KEY FUNCTION FOR CURSOR LOGIC ***
--
function UIManager:UpdateCursorState()
    -- If the editor resource is running, do NOTHING.
    if UIManager.isEditorRunning then
        return
    end
    
    -- Check if any panels are visible
    local settingsVisible = UIManager.Settings.window and guiGetVisible(UIManager.Settings.window)
    local buildVisible = UIManager.BuildDialog.window and guiGetVisible(UIManager.BuildDialog.window) -- NEW
    
    -- Show cursor if EITHER the main panel OR the settings panel OR the build dialog is visible.
    showCursor(UIManager.isPanelVisible or settingsVisible or buildVisible)
end

-- ADDED: Opens the build dialog and requests map list
function UIManager:onBuildOpen()
    if not VisionX.state.isAdmin then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaOnly administrators can build and save scripts.", 255, 255, 255, true)
        return
    end
    if not UIManager.BuildDialog.window or not isElement(UIManager.BuildDialog.window) then return end
    
    guiSetVisible(UIManager.BuildDialog.window, true)
    
    -- Request the list of available map resources from the server
    triggerServerEvent("visionx:requestMapResources", localPlayer)
end

-- ADDED: Closes the build dialog
function UIManager:onBuildClose()
    if not UIManager.BuildDialog.window or not isElement(UIManager.BuildDialog.window) then return end
    guiSetVisible(UIManager.BuildDialog.window, false)
end

-- ADDED: Handles the map selection and initiates the script generation/save on server
function UIManager:onBuildSave()
    if not VisionX or not VisionX.state.isInitialized then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaPlease wait for the main script to initialize before building.", 255, 255, 255, true)
        return
    end

    local combo = UIManager.BuildDialog.mapCombo
    local comboNum = guiComboBoxGetSelected(combo)
    
    if comboNum == -1 then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaError: Please select a map resource from the list.", 255, 255, 255, true)
        return
    end

    local mapName = guiComboBoxGetItemText(combo, comboNum)
    local currentCategory = VisionX.state.activeCategory or "Decoration"
    
    -- Send settings, map name, active category, and unique model IDs
    triggerServerEvent("visionx:buildScript", localPlayer, VisionX.CONFIG, currentCategory, VisionX.state.uniqueModelIDs, mapName)
    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] Generating and saving script to resource: #aaffaa" .. mapName, 255,255,255, true)
    
    -- Close all UI
    guiSetVisible(UIManager.Main.window, false)
    guiSetVisible(UIManager.Settings.window, false)
    guiSetVisible(UIManager.BuildDialog.window, false) -- NEW
    UIManager.isPanelVisible = false 
    UIManager:UpdateCursorState()
end

function UIManager:UpdateStats()
    if not UIManager.Main.statCached or not isElement(UIManager.Main.statCached) then return end
    
    local state = VisionX.state
    local config = VisionX.CONFIG
    
    guiSetText(UIManager.Main.statCached, string.format("Total Cached: %d", table.size(state.masterObjectRegistry)))
    local categoryName = state.activeCategory or "Off"
    guiSetText(UIManager.Main.statActive, string.format("Active Objs (%s): %d", categoryName, table.size(state.objectRegistry)))
    -- MODIFIED: Show clone limit in GUI stats
    guiSetText(UIManager.Main.statClones, string.format("Active Clones: %d / %d", table.size(state.activeClones), config.CLONE_LIMIT))
    guiSetText(UIManager.Main.statRange, string.format("View Range: %d - %d", config.MIN_VIEW_RANGE, config.MAX_VIEW_RANGE))
    
    -- Calculate grid dimensions
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
    
    -- Load current config into edit boxes
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
    
    -- Convert text values back to numbers and sanitize
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
    
    -- Send new settings to the server for validation and saving
    triggerServerEvent("visionx:saveSettings", localPlayer, newConfig)
    
    -- Close the panel. The server will send a `syncSettings` event
    UIManager:onSettingsClose()
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

-- ADDED: Updates the text for the on-screen overlay
function UIManager:UpdateOverlayText()
    local count = table.size(VisionX.state.activeClones)
    local limit = VisionX.CONFIG.CLONE_LIMIT
    UIManager.Overlay.text = string.format("Active Clones: %d / %d", count, limit)
    
    -- ADDED: Color-coding logic
    local percentage = count / limit
    if percentage >= 0.9 then
        UIManager.Overlay.color = tocolor(255, 50, 50, 255) -- Red
    elseif percentage >= 0.75 then
        UIManager.Overlay.color = tocolor(255, 165, 0, 255) -- Orange
    else
        UIManager.Overlay.color = tocolor(50, 255, 50, 255) -- Green
    end
end

-- ADDED: Renders the on-screen overlay
function UIManager:RenderOverlay()
    -- ADDED: Check if overlay is toggled on
    if not UIManager.Overlay.isVisible then
        return
    end
    
    -- Only render if VisionX is active (not "Off")
    if not VisionX.state.isEnabled then
        return
    end
    
    local text = UIManager.Overlay.text -- Get the cached text
    -- MODIFIED: Position to middle-bottom
    local x = UIManager.Overlay.screenWidth / 2 -- Center horizontally
    local y = UIManager.Overlay.screenHeight - 40 -- 40px padding from bottom
    
    -- Draw shadow/outline
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 200), 1.2, UIManager.Overlay.font, "center", "bottom")
    -- Draw main text
    dxDrawText(text, x, y, x, y, UIManager.Overlay.color, 1.2, UIManager.Overlay.font, "center", "bottom")
end

-- === KEYBINDS & COMMANDS ===

-- This 'Z' keybind works with the UpdateCursorState function
bindKey("z", "down", function()
    -- Only toggle if not typing in chat or console
    if isChatBoxInputActive() or isConsoleActive() then return end
    
    if UIManager.Main.window and isElement(UIManager.Main.window) then
        -- Toggle the desired visibility state
        UIManager.isPanelVisible = not UIManager.isPanelVisible
        -- Apply the new state
        guiSetVisible(UIManager.Main.window, UIManager.isPanelVisible)
        
        -- If we are hiding the main panel, also hide other panels
        if not UIManager.isPanelVisible then 
            if UIManager.Settings.window and isElement(UIManager.Settings.window) then
                guiSetVisible(UIManager.Settings.window, false)
            end
            if UIManager.BuildDialog.window and isElement(UIManager.BuildDialog.window) then -- NEW
                guiSetVisible(UIManager.BuildDialog.window, false)
            end
        end
        
        -- Update cursor
        UIManager:UpdateCursorState()
    end
end)

bindKey("l", "down", function()
    -- Only refresh if not typing in chat or console
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
            UIManager:UpdateCursorState() -- Update cursor
        else
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaaYou do not have permission to open settings.", 255, 255, 255, true)
        end
    elseif arg == "build" then
        UIManager:onBuildOpen() -- MODIFIED
        UIManager:UpdateCursorState() -- Update cursor
    elseif arg == "stats" then
        -- This is the only command that outputs stats to chat
        UIManager:UpdateStats() -- Make sure stats are fresh
        local state = VisionX.state
        local config = VisionX.CONFIG
        local b = state.gridBounds
        local cellCount = table.size(state.spatialGrid)
        local dimX = (b.maxX - b.minX) + 1
        local dimY = (b.maxY - b.minY) + 1
        local gridDims = (cellCount > 0) and string.format("%dx%d (%d Cells)", dimX, dimY, cellCount) or "0x0 (0 Cells)"

        outputChatBox("[#"..UIManager.brandColor.."VisionX Stats#ffffff] ----------------", 255, 255, 255, true)
        outputChatBox(string.format("  Mode: #aaffaa%s#ffffff | Clones: #aaffaa%d / %d", state.activeCategory or "Off", table.size(state.activeClones), config.CLONE_LIMIT), 255, 255, 255, true)
        outputChatBox(string.format("  Cached Objs: #aaffaa%d#ffffff | Active Objs: #aaffaa%d", table.size(state.masterObjectRegistry), table.size(state.objectRegistry)), 255, 255, 255, true)
        outputChatBox(string.format("  Range: #aaffaa%d - %d#ffffff | Grid Dims: #aaffaa%s", config.MIN_VIEW_RANGE, config.MAX_VIEW_RANGE, gridDims), 255, 255, 255, true)

    elseif arg == "refresh" then
        UIManager:onRefresh()
    elseif arg == "clones" then -- ADDED: Toggle for clone overlay
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

-- Checks if a model ID belongs to the currently active category.
local function _isModelIncluded(modelId, activeCategory)
    if not activeCategory then return false end
    local objectCategory = VisionX.state.categoryLookup[modelId] or "OTHER"
    if activeCategory == "All" then
        return objectCategory == "Decoration" or objectCategory == "Track"
    else
        -- Fixed typo from v3.5.0 (was activeCatenogory)
        return objectCategory == activeCategory
    end
end

-- Performs the initial scan of all map objects to build a master cache.
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

    -- Calculate and display statistics about unique models.
    local categoryCounts = { Decoration = 0, Track = 0, OTHER = 0 }
    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        local category = self.state.categoryLookup[modelId] or "OTHER"
        categoryCounts[category] = (categoryCounts[category] or 0) + 1
    end
    self.state.categoryCounts = categoryCounts
    -- Stats are now only in the GUI
end

-- Filters the master registry to create a targeted registry based on the active category.
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

-- Builds the spatial grid from the targeted object registry for fast spatial lookups.
function VisionX:_BuildSpatialGrid()
    self.state.spatialGrid = {}
    self.state.gridBounds = { minX = 9999, minY = 9999, maxX = -9999, maxY = -9999 }
    local cellSize = self.CONFIG.SPATIAL_GRID_CELL_SIZE
    if not cellSize or cellSize <= 0 then cellSize = 250 end -- Safety check

    for entity, data in pairs(self.state.objectRegistry) do
        local gridX = math.floor(data.pos[1] / cellSize)
        local gridY = math.floor(data.pos[2] / cellSize)
        
        -- Update grid bounds
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
    
    -- Update stats panel with new cell count
    UIManager:UpdateStats()
end

-- Resets the LOD distance for all unique models found on the map.
function VisionX:_ResetAllModelsLOD(distance)
    for modelId, _ in pairs(self.state.uniqueModelIDs) do
        engineSetModelLODDistance(modelId, distance)
    end
end

-- Handles newly streamed-in objects, adding them to the registries if necessary.
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

-- Spawning Logic: Creates new clones for objects that enter the view range.
function VisionX:_PerformSpawningLogic()
    local camX, camY, camZ = getCameraMatrix()
    local playerDim = getElementDimension(localPlayer)
    local createdThisCycle = 0
    
    -- ADDED: Check current clone count against the new limit
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
    
    -- ADDED: Get screen size once for frustum culling
    local screenWidth, screenHeight = UIManager.Overlay.screenWidth, UIManager.Overlay.screenHeight
    local screenBuffer = 200 -- Spawn objects 200px off-screen to avoid "pop-in"
    
    for i = -searchRadius, searchRadius do
        for j = -searchRadius, searchRadius do
            local key = (pGridX + i) .. "_" .. (pGridY + j)
            if self.state.spatialGrid[key] then
                for _, sourceElement in ipairs(self.state.spatialGrid[key]) do
                    -- Check batch limit
                    if createdThisCycle >= self.CONFIG.CREATION_BATCH_LIMIT then return end
                    
                    -- ADDED: Check if adding this clone would exceed the limit
                    if (currentCloneCount + createdThisCycle) >= self.CONFIG.CLONE_LIMIT then
                        return -- Stop spawning this cycle
                    end
                    
                    local data = self.state.objectRegistry[sourceElement]
                    if data and not self.state.activeClones[sourceElement] and data.dimension == playerDim then
                        local dx, dy, dz = data.pos[1] - camX, data.pos[2] - camY, data.pos[3] - camZ
                        local distSq = dx*dx + dy*dy + dz*dz
                        if distSq >= minRangeSq and distSq <= maxRangeSq then
                            
                            -- OPTIMIZED: This is the new, stricter frustum culling logic
                            local sX, sY = getScreenFromWorldPosition(data.pos[1], data.pos[2], data.pos[3])
                            
                            -- sX and sY are non-nil if in front of camera
                            -- We also check if they are within the screen bounds (+ buffer)
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
    self:_PerformSpawningLogic() -- Run once immediately
    UIManager:SyncRadioButtons() -- Update UI
    UIManager:UpdateStats()      -- Update Stats
    UIManager:UpdateOverlayText() -- ADDED: Update overlay

    -- Start the main update loops.
    if isTimer(self.timers.spawn) then killTimer(self.timers.spawn) end
    if isTimer(self.timers.cullDelay) then killTimer(self.timers.cullDelay) end
    if isTimer(self.timers.cull) then killTimer(self.timers.cull) end
    
    self.timers.spawn = setTimer(function() 
        self:_PerformSpawningLogic() 
        UIManager:UpdateOverlayText() -- ADDED: Update overlay after spawn
    end, self.CONFIG.UPDATE_TICK_RATE, 0)
    
    self.timers.cullDelay = setTimer(function()
        self.timers.cull = setTimer(function()
            self:_PerformCullingLogic()
            UIManager:UpdateStats() -- Update clone count
            UIManager:UpdateOverlayText() -- ADDED: Update overlay after cull
        end, self.CONFIG.UPDATE_TICK_RATE, 0)
    end, self.CONFIG.UPDATE_TICK_RATE / 2, 1)
end

function VisionX:Deactivate(isSwitching)
    if not self.state.isEnabled then return end
    
    -- Stop all timers.
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
    
    self:_ResetAllModelsLOD(1000) -- Reset all LODs to default.
    UIManager:SyncRadioButtons() -- Update UI
    UIManager:UpdateStats() -- Update clone count
    UIManager:UpdateOverlayText() -- ADDED: Update overlay
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
            UIManager:UpdateStats() -- Stats will have changed
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

    -- Check if editor is *already* running on script start
    local editor = getResourceFromName("editor_main")
    if editor and getResourceState(editor) == "running" then
        UIManager.isEditorRunning = true
    else
        -- If editor isn't running, check if 'race' is
        local race = getResourceFromName("race")
        if race and getResourceState(race) == "running" then
            UIManager.isEditorRunning = false
        end
    end

    -- Create the GUI
    UIManager:CreateMainPanel()
    UIManager:CreateSettingsPanel()
    UIManager:CreateBuildDialog() -- NEW
    
    -- Build the registry
    self:_BuildMasterObjectRegistry()
    
    -- Core event handlers
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

    -- ADDED: Handle overlay rendering
    addEventHandler("onClientRender", root, function()
        UIManager:RenderOverlay()
    end)
    
    -- ADDED: Keep overlay screen size in sync
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
        if now - lastMapRefreshTick > 5000 then -- avoid double refresh
            -- Perform a hard refresh, silently for non-admins.
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
        -- This handles the user *entering* the editor
        UIManager.isEditorRunning = true
        
        -- Hide our game cursor, as the editor will take over.
        showCursor(false) 

        -- Re-show the panel if it was meant to be visible
        if UIManager.isPanelVisible and UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, true)
        end
        
    elseif getResourceName(startedResource) == "race" then
        -- This handles the user *entering* a race
        UIManager.isEditorRunning = false
        
        -- Force the panel state to hidden
        UIManager.isPanelVisible = false
        
        -- Unconditionally hide all GUI
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, false)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            guiSetVisible(UIManager.Settings.window, false)
        end
        
        -- We are now IN PLAY MODE. Force the cursor off.
        showCursor(false)
    end
end)

addEventHandler("onClientResourceStop", root, function(stoppedResource)
    if stoppedResource == getThisResource() then
        VisionX:Deactivate()
        -- Also destroy the GUI if the main resource stops
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            destroyElement(UIManager.Main.window)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            destroyElement(UIManager.Settings.window)
        end
        if UIManager.BuildDialog.window and isElement(UIManager.BuildDialog.window) then
            destroyElement(UIManager.BuildDialog.window)
        end
        
    elseif getResourceName(stoppedResource) == "editor_main" then
        -- This handles the user *leaving* the editor
        UIManager.isEditorRunning = false
        
        -- Force the panel state to hidden
        UIManager.isPanelVisible = false
        
        -- Unconditionally hide all GUI
        if UIManager.Main.window and isElement(UIManager.Main.window) then
            guiSetVisible(UIManager.Main.window, false)
        end
        if UIManager.Settings.window and isElement(UIManager.Settings.window) then
            guiSetVisible(UIManager.Settings.window, false)
        end
        
        -- We are now IN PLAY MODE. Force the cursor off.
        showCursor(false)
        
    elseif getResourceName(stoppedResource) == "race" then
        -- This handles the user *leaving* a race (e.g., back to menu)
        -- We are NOT in the editor.
        UIManager.isEditorRunning = false
        
        -- Re-evaluate cursor state just in case.
        -- If panel was visible, cursor will show. If not, it won't.
        UIManager:UpdateCursorState()
    end
end)

-- ////////////////////////////////////////////////////////////////////////////
-- // SERVER → CLIENT SYNC (Updated)
-- ////////////////////////////////////////////////////////////////////////////

addEvent("visionx:receiveInitialData", true)
addEventHandler("visionx:receiveInitialData", root, function(categories, settings, isAdmin) 
    VisionX.state.categoryLookup = categories 
    -- IMPORTANT: Ensure our new default doesn't get wiped out if server is older
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
    
    -- IMPORTANT: Ensure our new default doesn't get wiped out if server is older
    local newCloneLimit = settings.CLONE_LIMIT or VisionX.CONFIG.CLONE_LIMIT
    VisionX.CONFIG = settings
    VisionX.CONFIG.CLONE_LIMIT = newCloneLimit
    
    outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaaGlobal settings have been updated by an admin.", 255, 255, 255, true)
    
    if wasEnabled then 
        VisionX:Activate(activeCategory, true) 
    end
    
    -- Update the stats panel with the new config values
    UIManager:UpdateStats()
end)

addEvent("visionx:onSettingsSaved", true)
addEventHandler("visionx:onSettingsSaved", root, function(success, message)
    if success then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaa" .. message, 255, 255, 255, true)
        -- Show the new settings to the admin who saved them
        if VisionX.state.isAdmin then
            outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] --- New Settings ---", 255, 255, 255, true)
            outputChatBox(string.format("  Range: #aaffaa%d - %d#ffffff | Tick: #aaffaa%dms", VisionX.CONFIG.MIN_VIEW_RANGE, VisionX.CONFIG.MAX_VIEW_RANGE, VisionX.CONFIG.UPDATE_TICK_RATE), 255, 255, 255, true)
            outputChatBox(string.format("  Grid: #aaffaa%d#ffffff | Batch: #aaffaa%d | Clone Limit: #aaffaa%d", VisionX.CONFIG.SPATIAL_GRID_CELL_SIZE, VisionX.CONFIG.CREATION_BATCH_LIMIT, VisionX.CONFIG.CLONE_LIMIT), 255, 255, 255, true)
        end
    else
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #ffaaaa" .. message, 255, 255, 255, true)
    end
end)

-- ADDED: Receive generated script status (for automatic saving)
addEvent("visionx:receiveGeneratedScript", true)
addEventHandler("visionx:receiveGeneratedScript", root, function(success, mapName, message)
    if success then
        outputChatBox("[#"..UIManager.brandColor.."VisionX#ffffff] #aaffaaSuccess!#ffffff Standalone script saved to '"..mapName.."'!", 255,255,255, true)
        outputChatBox("#ffff00WARNING: You must restart the '"..mapName.."' resource for changes to take effect.", 255,255,255, true)
    else
        outputChatBox("[#"..UIManager.brandColor.."VisionX Builder ERROR#ffffff] #ffaaaa" .. message, 255,100,100, true)
    end
end)

-- ADDED: Receive list of map resources from server
addEvent("visionx:receiveMapResources", true)
addEventHandler("visionx:receiveMapResources", root, function(mapNames)
    VisionX.state.availableMapResources = mapNames or {}
    
    local combo = UIManager.BuildDialog.mapCombo
    guiComboBoxClear(combo)

    if table.size(mapNames) == 0 then
        guiComboBoxAddItem(combo, "No map resources found.")
        guiComboBoxSetSelected(combo, 0)
        guiSetEnabled(UIManager.BuildDialog.btnSave, false)
        return
    end

    for _, name in ipairs(mapNames) do
        guiComboBoxAddItem(combo, name)
    end
    
    guiComboBoxSetSelected(combo, 0)
    guiSetEnabled(UIManager.BuildDialog.btnSave, true)
end)