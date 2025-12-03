--[[
============================================================
--
--  Author: Corrupt
--  VisionX Advanced - GUI & Rendering Logic
--  Version: 3.4.0 (Seperated GUI from Client Logic)
--
--  CHANGELOG: (3.2.8 → 3.4.0)
--  - Split GUI logic into a dedicated module (`gui_client.lua`) for cleaner separation.
--  - Added Build dialog, map selection combo, and export/save UX improvements.
--  - Exposed clone limit and overlay toggles to the UI; improved stats reporting.
--  - Adjusted UI defaults to match updated server/client settings (MIN_VIEW_RANGE, clone limits).
--  - Small bugfixes and layout tweaks for better cross-resolution compatibility.
--
============================================================
]]
-- ////////////////////////////////////////////////////////////////////////////
-- // UI MANAGER
-- ////////////////////////////////////////////////////////////////////////////

UIManager = {
    Main = {},
    Settings = {},
    Overlay = {},
    Export = {},
    brandColor = "0DBCFF",
    isPanelVisible = false,
    isEditorRunning = false,
    generatedCodeCache = nil,
    -- Notification System State
    Notification = {
        message = "",
        type = "info", -- "info", "warning", "error"
        tick = 0,
        duration = 6000,
        isVisible = false,
        alpha = 0,
    },
}

local sx, sy = guiGetScreenSize()

-- ////////////////////////////////////////////////////////////////////////////
-- // DX NOTIFICATION BAR (Bottom of Screen)
-- ////////////////////////////////////////////////////////////////////////////

function UIManager:AddNotification(message, msgType)
    self.Notification.message = message
    self.Notification.type = msgType or "info"
    self.Notification.tick = getTickCount()
    self.Notification.isVisible = true
    self.Notification.alpha = 0

    local prefix = "[VisionX][" .. string.upper(self.Notification.type) .. "] "
    outputConsole(prefix .. message)
end

function UIManager:RenderNotificationBar()
    if not self.Notification.isVisible then
        return
    end

    local now = getTickCount()
    local elapsed = now - self.Notification.tick

    if elapsed < 500 then
        self.Notification.alpha = (elapsed / 500) * 255
    elseif elapsed > (self.Notification.duration - 500) then
        self.Notification.alpha = (
            1 - ((elapsed - (self.Notification.duration - 500)) / 500)
        ) * 255
    else
        self.Notification.alpha = 255
    end

    if elapsed > self.Notification.duration then
        self.Notification.isVisible = false
        self.Notification.alpha = 0
        return
    end

    local r, g, b = 0, 0, 0
    local bgAlpha = 100

    if
        self.Notification.type == "error"
        or self.Notification.type == "critical"
    then
        r, g, b = 220, 40, 40
    elseif self.Notification.type == "warning" then
        r, g, b = 255, 180, 20
    else
        r, g, b = 40, 220, 80
    end

    local barHeight = 30
    local yPos = sy - barHeight

    dxDrawRectangle(
        0,
        yPos,
        sx,
        barHeight,
        tocolor(r, g, b, math.min(bgAlpha, self.Notification.alpha))
    )

    dxDrawText(
        self.Notification.message,
        0,
        yPos,
        sx,
        sy,
        tocolor(255, 255, 255, self.Notification.alpha),
        1.0,
        "default",
        "center",
        "center"
    )
end

-- ////////////////////////////////////////////////////////////////////////////
-- // CLONE OVERLAY (HUD)
-- ////////////////////////////////////////////////////////////////////////////

UIManager.Overlay = {
    text = "Active Clones: 0 / 500",
    font = "default-bold",
    screenWidth = sx,
    screenHeight = sy,
    isVisible = true,
    color = tocolor(0, 255, 0, 255),
}

function UIManager:UpdateOverlayText()
    if not VisionX or not VisionX.state then
        return
    end

    local count = 0
    if VisionX.state.activeClones then
        for _ in pairs(VisionX.state.activeClones) do
            count = count + 1
        end
    end

    local limit = VisionX.CONFIG.CLONE_LIMIT or 500
    self.Overlay.text = string.format("Active Clones: %d / %d", count, limit)

    local percentage = count / limit
    if percentage >= 0.9 then
        self.Overlay.color = tocolor(255, 50, 50, 255)
    elseif percentage >= 0.75 then
        self.Overlay.color = tocolor(255, 165, 0, 255)
    else
        self.Overlay.color = tocolor(50, 255, 50, 255)
    end
end

function UIManager:RenderOverlay()
    self:RenderNotificationBar()

    if not self.Overlay.isVisible then
        return
    end
    if not VisionX or not VisionX.state or not VisionX.state.isEnabled then
        return
    end

    local text = self.Overlay.text
    local x = self.Overlay.screenWidth / 2
    local y = self.Overlay.screenHeight - 40

    if self.Notification.isVisible then
        y = y - 30
    end

    dxDrawText(
        text,
        x + 1,
        y + 1,
        x + 1,
        y + 1,
        tocolor(0, 0, 0, 200),
        1.2,
        self.Overlay.font,
        "center",
        "bottom"
    )
    dxDrawText(
        text,
        x,
        y,
        x,
        y,
        self.Overlay.color,
        1.2,
        self.Overlay.font,
        "center",
        "bottom"
    )
end

-- ////////////////////////////////////////////////////////////////////////////
-- // PANEL CREATION
-- ////////////////////////////////////////////////////////////////////////////

function UIManager:CreateMainPanel()
    local w, h = 230, 425
    local x, y = 10, sy / 2 - h / 2

    local panel = guiCreateWindow(x, y, w, h, "VisionX v3.3.0", false)
    guiWindowSetSizable(panel, false)
    guiWindowSetMovable(panel, true)
    self.Main.window = panel

    guiCreateLabel(10, 30, 80, 20, "Mode:", false, panel)
    self.Main.radioOff =
        guiCreateRadioButton(30, 55, 100, 20, "Off", false, panel)
    self.Main.radioDeco =
        guiCreateRadioButton(30, 80, 100, 20, "Decoration", false, panel)
    self.Main.radioTrack =
        guiCreateRadioButton(120, 55, 100, 20, "Track", false, panel)
    self.Main.radioAll =
        guiCreateRadioButton(120, 80, 100, 20, "All", false, panel)

    local yPos = 115
    guiCreateLabel(10, yPos, 80, 20, "Map Stats:", false, panel)
    yPos = yPos + 25
    self.Main.statCached =
        guiCreateLabel(20, yPos, 200, 20, "Total Cached: 0", false, panel)
    yPos = yPos + 20
    self.Main.statActive =
        guiCreateLabel(20, yPos, 200, 20, "Active Objs (Off): 0", false, panel)
    yPos = yPos + 20
    self.Main.statClones =
        guiCreateLabel(20, yPos, 200, 20, "Active Clones: 0", false, panel)
    yPos = yPos + 25

    guiCreateLabel(10, yPos, 100, 20, "Config Stats:", false, panel)
    yPos = yPos + 25
    self.Main.statRange =
        guiCreateLabel(20, yPos, 200, 20, "View Range: 0 - 0", false, panel)
    yPos = yPos + 20
    self.Main.statGridInfo = guiCreateLabel(
        20,
        yPos,
        200,
        20,
        "Grid Dims: 0x0 (0 Cells)",
        false,
        panel
    )
    yPos = yPos + 35

    local btnY = yPos
    if VisionX.state.isAdmin then
        self.Main.btnSettings =
            guiCreateButton(10, btnY, w - 20, 30, "Settings...", false, panel)
        btnY = btnY + 35
    end
    self.Main.btnBuild =
        guiCreateButton(10, btnY, w - 20, 30, "Build Script...", false, panel)
    btnY = btnY + 35
    self.Main.btnRefresh =
        guiCreateButton(10, btnY, w - 20, 30, "Refresh (L)", false, panel)

    local footerLabel = guiCreateLabel(
        10,
        h - 25,
        w - 20,
        20,
        "© Corrupt | Discord: @sheputy",
        false,
        panel
    )

    local statLabels = {
        self.Main.statCached,
        self.Main.statActive,
        self.Main.statClones,
        self.Main.statRange,
        self.Main.statGridInfo,
    }
    for _, label in ipairs(statLabels) do
        guiLabelSetHorizontalAlign(label, "left", false)
    end
    guiLabelSetHorizontalAlign(footerLabel, "right", false)

    self:SyncRadioButtons()
    self:UpdateStats()
    guiSetVisible(panel, false)
end

function UIManager:CreateSettingsPanel()
    local w, h = 400, 520 -- [UPDATED] Increased height for custom input
    local x, y = sx / 2 - w / 2, sy / 2 - h / 2

    local panel = guiCreateWindow(x, y, w, h, "VisionX Settings", false)
    guiWindowSetSizable(panel, false)
    self.Settings.window = panel

    local labels = {
        "Max View Range (500-3000):",
        "Min View Range (0-300):",
        "Creation Batch (5-1000):",
        "Update Tick (50-9000ms):",
        "Spatial Grid (10-3000):",
        "Active Clone Limit (50-3000):",
    }
    local keys = {
        "MAX_VIEW_RANGE",
        "MIN_VIEW_RANGE",
        "CREATION_BATCH_LIMIT",
        "UPDATE_TICK_RATE",
        "SPATIAL_GRID_CELL_SIZE",
        "CLONE_LIMIT",
    }
    self.Settings.edits = {}

    local yPos = 30
    for i, label in ipairs(labels) do
        guiCreateLabel(10, yPos + 4, 180, 25, label, false, panel)
        local edit = guiCreateEdit(200, yPos, w - 210, 25, "", false, panel)
        self.Settings.edits[keys[i]] = edit
        yPos = yPos + 30
    end

    -- Priority Section
    yPos = yPos + 10
    guiCreateLabel(
        10,
        yPos,
        w - 20,
        20,
        "--- Load Priorities ---",
        false,
        panel
    )
    guiLabelSetHorizontalAlign(
        guiCreateLabel(
            10,
            yPos,
            w - 20,
            20,
            "--- Load Priorities ---",
            false,
            panel
        ),
        "center",
        false
    )
    yPos = yPos + 25

    local function createCombo(label)
        guiCreateLabel(10, yPos + 4, 100, 25, label, false, panel)
        local combo =
            guiCreateComboBox(120, yPos, w - 130, 100, "", false, panel)
        yPos = yPos + 30
        return combo
    end

    self.Settings.comboHigh = createCombo("High Priority:")
    self.Settings.comboMed = createCombo("Med Priority:")
    self.Settings.comboLow = createCombo("Low Priority:")

    -- [NEW] Custom Objects Input
    yPos = yPos + 5
    guiCreateLabel(
        10,
        yPos,
        w - 20,
        20,
        "Custom TOP Priority IDs (comma separated):",
        false,
        panel
    )
    yPos = yPos + 20
    self.Settings.editCustomIDs =
        guiCreateEdit(10, yPos, w - 20, 30, "", false, panel)
    guiEditSetMaxLength(self.Settings.editCustomIDs, 1000)
    yPos = yPos + 40

    self.Settings.btnSave =
        guiCreateButton(10, h - 40, w / 2 - 15, 30, "Save", false, panel)
    self.Settings.btnClose = guiCreateButton(
        w / 2 + 5,
        h - 40,
        w / 2 - 15,
        30,
        "Close",
        false,
        panel
    )

    guiSetVisible(panel, false)
end

function UIManager:CreateExportPanel()
    local w, h = 450, 320
    local x, y = sx / 2 - w / 2, sy / 2 - h / 2

    local panel = guiCreateWindow(x, y, w, h, "VisionX Export Manager", false)
    guiWindowSetSizable(panel, false)
    self.Export.window = panel

    local currentY = 30

    local lblInfo = guiCreateLabel(
        10,
        currentY,
        w - 20,
        35,
        "Select a map resource below to save the standalone script directly, or copy to clipboard.",
        false,
        panel
    )
    guiLabelSetHorizontalAlign(lblInfo, "left", true)
    currentY = currentY + 35

    local lblWarnMap = guiCreateLabel(
        10,
        currentY,
        w - 20,
        60,
        "IMPORTANT: Ensure the target map is currently OPENED in Editor and you have configured the mode [Deco/Track/All] and settings in /vx settings.",
        false,
        panel
    )
    guiLabelSetColor(lblWarnMap, 52, 235, 113)
    guiLabelSetHorizontalAlign(lblWarnMap, "left", true)
    guiSetFont(lblWarnMap, "clear-normal")
    currentY = currentY + 60

    local resName = getResourceName(getThisResource())
    local aclText = string.format(
        "PERMISSIONS: This resource needs Admin rights to save files.\nUse: /aclrequest allow %s all\nOr add 'resource.%s' to the Admin ACL group.",
        resName,
        resName
    )

    local lblWarnACL =
        guiCreateLabel(10, currentY, w - 20, 55, aclText, false, panel)
    guiLabelSetColor(lblWarnACL, 255, 255, 100)
    guiLabelSetHorizontalAlign(lblWarnACL, "left", true)
    guiSetFont(lblWarnACL, "default-bold-small")
    currentY = currentY + 60

    self.Export.comboMaps = guiCreateComboBox(
        10,
        currentY,
        w - 20,
        150,
        "Select Map...",
        false,
        panel
    )
    currentY = currentY + 40

    self.Export.btnSave = guiCreateButton(
        10,
        currentY,
        (w / 2) - 15,
        35,
        "Save to Map",
        false,
        panel
    )
    guiSetProperty(self.Export.btnSave, "NormalTextColour", "FFAAFF00")

    self.Export.btnCopy = guiCreateButton(
        (w / 2) + 5,
        currentY,
        (w / 2) - 15,
        35,
        "Copy to Clipboard",
        false,
        panel
    )
    currentY = currentY + 45

    self.Export.btnClose =
        guiCreateButton(10, currentY, w - 20, 30, "Close", false, panel)

    guiSetVisible(panel, false)
end

-- ////////////////////////////////////////////////////////////////////////////
-- // PANEL STATE UPDATES
-- ////////////////////////////////////////////////////////////////////////////

function UIManager:UpdateCursorState()
    if self.isEditorRunning then
        return
    end

    local settingsVisible = self.Settings.window
        and guiGetVisible(self.Settings.window)
    local exportVisible = self.Export.window
        and guiGetVisible(self.Export.window)

    showCursor(self.isPanelVisible or settingsVisible or exportVisible)
end

function UIManager:UpdateStats()
    if not self.Main.statCached or not isElement(self.Main.statCached) then
        return
    end
    if not VisionX or not VisionX.state then
        return
    end

    local state = VisionX.state
    local config = VisionX.CONFIG

    local cachedCount = 0
    for _ in pairs(state.masterObjectRegistry) do
        cachedCount = cachedCount + 1
    end

    local activeCount = 0
    for _ in pairs(state.objectRegistry) do
        activeCount = activeCount + 1
    end

    local cloneCount = 0
    for _ in pairs(state.activeClones) do
        cloneCount = cloneCount + 1
    end

    guiSetText(
        self.Main.statCached,
        string.format("Total Cached: %d", cachedCount)
    )

    local categoryName = state.activeCategory or "Off"
    guiSetText(
        self.Main.statActive,
        string.format("Active Objs (%s): %d", categoryName, activeCount)
    )

    guiSetText(
        self.Main.statClones,
        string.format("Active Clones: %d / %d", cloneCount, config.CLONE_LIMIT)
    )
    guiSetText(
        self.Main.statRange,
        string.format(
            "View Range: %d - %d",
            config.MIN_VIEW_RANGE,
            config.MAX_VIEW_RANGE
        )
    )

    local gridDims = "0x0 (0 Cells)"
    local cellCount = 0
    for _ in pairs(state.spatialGrid) do
        cellCount = cellCount + 1
    end

    if cellCount > 0 then
        local b = state.gridBounds
        local dimX = (b.maxX - b.minX) + 1
        local dimY = (b.maxY - b.minY) + 1
        gridDims = string.format("%dx%d (%d Cells)", dimX, dimY, cellCount)
    end
    guiSetText(self.Main.statGridInfo, "Grid Dims: " .. gridDims)
end

function UIManager:SyncRadioButtons()
    if not self.Main.radioOff or not isElement(self.Main.radioOff) then
        return
    end
    if not VisionX or not VisionX.state then
        return
    end

    local category = VisionX.state.activeCategory
    guiRadioButtonSetSelected(self.Main.radioOff, category == false)
    guiRadioButtonSetSelected(self.Main.radioDeco, category == "Decoration")
    guiRadioButtonSetSelected(self.Main.radioTrack, category == "Track")
    guiRadioButtonSetSelected(self.Main.radioAll, category == "All")
end

function UIManager:onSettingsOpen()
    if not self.Settings.window or not isElement(self.Settings.window) then
        return
    end

    for key, edit in pairs(self.Settings.edits) do
        guiSetText(edit, tostring(VisionX.CONFIG[key]))
    end

    -- Populate Priority Combos
    local groups = {}
    if VisionX.state.groupTypes then
        for groupName, _ in pairs(VisionX.state.groupTypes) do
            table.insert(groups, groupName)
        end
        table.sort(groups)
    end

    local function populate(combo, currentVal)
        guiComboBoxClear(combo)
        for i, name in ipairs(groups) do
            local id = guiComboBoxAddItem(combo, name)
            if name == currentVal then
                guiComboBoxSetSelected(combo, id)
            end
        end
    end

    populate(self.Settings.comboHigh, VisionX.CONFIG.PRIORITY_HIGH)
    populate(self.Settings.comboMed, VisionX.CONFIG.PRIORITY_MED)
    populate(self.Settings.comboLow, VisionX.CONFIG.PRIORITY_LOW)

    -- [NEW] Populate Custom IDs Input
    if self.Settings.editCustomIDs then
        guiSetText(
            self.Settings.editCustomIDs,
            VisionX.CONFIG.CUSTOM_PRIORITY_IDS or ""
        )
    end

    guiSetVisible(self.Settings.window, true)
end

function UIManager:onSettingsClose()
    if not self.Settings.window or not isElement(self.Settings.window) then
        return
    end
    guiSetVisible(self.Settings.window, false)
end

function UIManager:onSettingsSave()
    local newConfig = {}
    local edits = self.Settings.edits

    local function getClampedValue(key, min, max)
        local num = tonumber(guiGetText(edits[key])) or VisionX.CONFIG[key]
        if num < min then
            num = min
        end
        if num > max then
            num = max
        end
        return num
    end

    newConfig.MAX_VIEW_RANGE = getClampedValue("MAX_VIEW_RANGE", 100, 3000)
    newConfig.MIN_VIEW_RANGE = getClampedValue("MIN_VIEW_RANGE", 0, 600)
    newConfig.CREATION_BATCH_LIMIT =
        getClampedValue("CREATION_BATCH_LIMIT", 1, 1000)
    newConfig.UPDATE_TICK_RATE = getClampedValue("UPDATE_TICK_RATE", 1, 9000)
    newConfig.SPATIAL_GRID_CELL_SIZE =
        getClampedValue("SPATIAL_GRID_CELL_SIZE", 1, 3000)
    newConfig.CLONE_LIMIT = getClampedValue("CLONE_LIMIT", 50, 3000)
    newConfig.DEBUG_MODE = VisionX.CONFIG.DEBUG_MODE

    -- Read Priorities
    local function getCombo(combo)
        local item = guiComboBoxGetSelected(combo)
        if item ~= -1 then
            return guiComboBoxGetItemText(combo, item)
        end
        return nil
    end
    newConfig.PRIORITY_HIGH = getCombo(self.Settings.comboHigh)
        or VisionX.CONFIG.PRIORITY_HIGH
    newConfig.PRIORITY_MED = getCombo(self.Settings.comboMed)
        or VisionX.CONFIG.PRIORITY_MED
    newConfig.PRIORITY_LOW = getCombo(self.Settings.comboLow)
        or VisionX.CONFIG.PRIORITY_LOW

    -- [NEW] Read Custom IDs
    newConfig.CUSTOM_PRIORITY_IDS = guiGetText(self.Settings.editCustomIDs)
        or ""

    triggerServerEvent("visionx:saveSettings", localPlayer, newConfig)

    self:onSettingsClose()
end

function UIManager:onBuildScript()
    if not VisionX or not VisionX.state.isInitialized then
        self:AddNotification(
            "Please wait for the main script to initialize.",
            "error"
        )
        return
    end

    local currentCategory = VisionX.state.activeCategory or "Decoration"

    triggerServerEvent(
        "visionx:buildScript",
        localPlayer,
        VisionX.CONFIG,
        currentCategory,
        VisionX.state.uniqueModelIDs
    )
    triggerServerEvent("visionx:requestMapList", localPlayer)

    self:AddNotification(
        "Generating script for category: " .. currentCategory,
        "info"
    )

    guiSetVisible(self.Main.window, false)
    guiSetVisible(self.Settings.window, false)
    self.isPanelVisible = false
end

function UIManager:onRefresh(isSilent)
    if VisionX and VisionX.state.isInitialized then
        if not isSilent then
            self:AddNotification("Performing HARD REFRESH...", "warning")
        end
        VisionX:Refresh(true, 1000, isSilent)
    else
        self:AddNotification("VisionX is not initialized yet.", "error")
    end
end

-- ////////////////////////////////////////////////////////////////////////////
-- // EVENT HANDLERS
-- ////////////////////////////////////////////////////////////////////////////

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
        -- Mode Radio Buttons
        UIManager:onRefresh()
    elseif source == main.radioOff then
        if VisionX.state.isEnabled then
            VisionX:Deactivate()
            UIManager:AddNotification("Mode set to: OFF", "error")
        end
    elseif source == main.radioDeco then
        VisionX:Activate("Decoration")
        UIManager:AddNotification("Mode set to: Decoration", "info")
    elseif source == main.radioTrack then
        VisionX:Activate("Track")
        UIManager:AddNotification("Mode set to: Track", "info")
    elseif source == main.radioAll then
        -- Settings Panel Buttons
        VisionX:Activate("All")
        UIManager:AddNotification("Mode set to: All", "info")
    elseif source == settings.btnSave then
        UIManager:onSettingsSave()
        UIManager:UpdateCursorState()
    elseif source == settings.btnClose then
        -- Export Panel Buttons
        UIManager:onSettingsClose()
        UIManager:UpdateCursorState()
    elseif source == export.btnCopy then
        if UIManager.generatedCodeCache then
            setClipboard(UIManager.generatedCodeCache)
            UIManager:AddNotification("Code copied to clipboard!", "info")
        end
    elseif source == export.btnSave then
        local item = guiComboBoxGetSelected(export.comboMaps)
        local mapName = guiComboBoxGetItemText(export.comboMaps, item)

        if not mapName or mapName == "" or item == -1 then
            UIManager:AddNotification("Please select a map first.", "error")
            return
        end

        if UIManager.generatedCodeCache then
            triggerServerEvent(
                "visionx:saveToMap",
                localPlayer,
                mapName,
                UIManager.generatedCodeCache
            )
        end
    elseif source == export.btnClose then
        guiSetVisible(export.window, false)
        UIManager:UpdateCursorState()
    end
end)

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

addEventHandler("onClientRender", root, function()
    UIManager:RenderOverlay()
end)

addEventHandler("onClientScreenSizeChange", root, function(width, height)
    sx, sy = width, height
    UIManager.Overlay.screenWidth = width
    UIManager.Overlay.screenHeight = height
end)
