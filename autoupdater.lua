--[[
============================================================
--  VisionX Auto-Updater (Final Safe Version)
--  Repository: https://github.com/Sheputy/visionx
--  Description: 
--    1. Waits 5 mins on start (Anti-Loop).
--    2. Downloads to .temp files first (Anti-Corruption).
--    3. Aborts if local version is 0.0.0 (Anti-Death-Loop).
============================================================
]]

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
local autoUpdate = true
local STARTUP_DELAY = 5 * 60 * 1000      -- 5 Minutes
local AUTO_UPDATE_INTERVAL = 24 * 60 * 60 * 1000 -- 24 Hours
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/Sheputy/visionx/main/"

local BRAND_COLOR = "#0DBCFF"
local TEXT_COLOR = "#FFFFFF"
local INFO_COLOR = "#FFA64C"

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local currentVersion = "0.0.0"
local resourceName = getResourceName(getThisResource())

------------------------------------------------------------
-- UTILS
------------------------------------------------------------
local function getLocalVersion()
    local meta = xmlLoadFile("meta.xml")
    if meta then
        local info = xmlFindChild(meta, "info", 0)
        if info then
            currentVersion = xmlNodeGetAttribute(info, "version") or "0.0.0"
        end
        xmlUnloadFile(meta)
    else
        currentVersion = "0.0.0" -- Meta is missing or corrupt
    end
    return currentVersion
end

local function isNewer(v1, v2)
    if v1 == v2 then return false end
    local v1parts, v2parts = {}, {}
    for p in v1:gmatch("%d+") do table.insert(v1parts, tonumber(p)) end
    for p in v2:gmatch("%d+") do table.insert(v2parts, tonumber(p)) end
    for i = 1, math.max(#v1parts, #v2parts) do
        local p1, p2 = v1parts[i] or 0, v2parts[i] or 0
        if p1 > p2 then return true end
        if p1 < p2 then return false end
    end
    return false
end

-- Helper to safely check Admin Group status
local function isResourceInAdminGroup()
    if not hasObjectPermissionTo(getThisResource(), "function.aclGetGroup", false) then
        return false -- We can't even check, so assume 'no'
    end
    
    local adminGroup = aclGetGroup("Admin")
    if adminGroup and isObjectInACLGroup("resource."..resourceName, adminGroup) then
        return true
    end
    return false
end

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    getLocalVersion()
    
    -- === LOOP PROTECTION ===
    if currentVersion == "0.0.0" then
        outputServerLog("[VisionX] CRITICAL ERROR: Version detected as 0.0.0 (meta.xml corrupt). Updater DISABLED to prevent loops.")
        outputChatBox("[VisionX] #FF0000CRITICAL: meta.xml is corrupt. Please reinstall resource manually.", root, 255, 255, 255, true)
        return
    end

    -- 1. GENERAL ADMIN CHECK (Soft Warning)
    if not isResourceInAdminGroup() then
        outputChatBox(string.format("%s[%sVisionX%s] #FF0000Missing admin permission, some features may be unavailable.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR), root, 255, 255, 255, true)
    end

    -- 2. CRITICAL PERMISSIONS CHECK (Updater Functionality)
    local permissionsNeeded = { "function.fetchRemote", "function.fileCreate", "function.fileWrite", "function.restartResource", "function.fileRename", "function.fileDelete" }
    local missingPerms = false
    for _, perm in ipairs(permissionsNeeded) do
        if not hasObjectPermissionTo(getThisResource(), perm, false) then
            missingPerms = true
            break
        end
    end

    if missingPerms then
        -- Tell them exactly how to fix it
        outputChatBox(string.format("%s[%sVisionX%s] #FFA64CUpdater disabled. Please run: #FFFFFF/aclrequest allow %s all", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, resourceName), root, 255, 255, 255, true)
        return -- Stop here, updater cannot run
    end

    if autoUpdate then
        outputServerLog("[VisionX] Updater armed. Waiting "..(STARTUP_DELAY/1000/60).." mins to check.")
        setTimer(checkForUpdates, STARTUP_DELAY, 1)
        setTimer(checkForUpdates, AUTO_UPDATE_INTERVAL, 0)
    end
end)

------------------------------------------------------------
-- UPDATE CHECKER
------------------------------------------------------------
function checkForUpdates(isManual, player)
    -- Double Check: Never run if corrupt
    if currentVersion == "0.0.0" then return end

    if isManual then
        outputChatBox(string.format("%s[%sVisionX%s] %sChecking for updates...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player, 255, 255, 255, true)
    end

    local metaURL = GITHUB_RAW_URL .. "meta.xml?cb=" .. getTickCount()
    fetchRemote(metaURL, function(data, err)
        if err ~= 0 or not data then
            if isManual then outputChatBox("[VisionX] Check failed. Error: "..err, player, 255, 100, 100, true) end
            return
        end

        local remoteVer = data:match('version="([^"]+)"')
        if remoteVer and isNewer(remoteVer, currentVersion) then
            outputChatBox(string.format("%s[%sVisionX%s] %sUpdate found (%s). Downloading...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, remoteVer), root, 255, 255, 255, true)
            processUpdate(data)
        elseif isManual then
            outputChatBox(string.format("%s[%sVisionX%s] %sUp to date.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player, 255, 255, 255, true)
        end
    end)
end

------------------------------------------------------------
-- SAFE DOWNLOAD LOGIC
------------------------------------------------------------
function processUpdate(metaContent)
    local filesToDownload = {}
    for path in metaContent:gmatch('src="([^"]+)"') do table.insert(filesToDownload, path) end
    table.insert(filesToDownload, "meta.xml")

    if #filesToDownload == 0 then return end

    local downloadedCount = 0
    local total = #filesToDownload
    local tempPrefix = "temp_update_"

    for _, fileName in ipairs(filesToDownload) do
        local url = GITHUB_RAW_URL .. fileName .. "?cb=" .. getTickCount()
        
        fetchRemote(url, function(data, err)
            if err == 0 and data then
                -- DOWNLOAD TO TEMP FILE FIRST
                local tempName = tempPrefix .. fileName:gsub("/", "_") 
                if fileExists(tempName) then fileDelete(tempName) end
                
                local file = fileCreate(tempName)
                if file then
                    fileWrite(file, data)
                    fileClose(file)
                    downloadedCount = downloadedCount + 1
                end
            end

            if downloadedCount >= total then
                applyUpdate(filesToDownload, tempPrefix)
            end
        end)
    end
end

function applyUpdate(fileList, tempPrefix)
    outputServerLog("[VisionX] Download complete. Applying update...")
    
    if not fileExists("addons/backups") then
        local dummy = fileCreate("addons/backups/.keep")
        if dummy then fileClose(dummy) end
    end

    for _, fileName in ipairs(fileList) do
        local tempName = tempPrefix .. fileName:gsub("/", "_")
        
        if fileExists(tempName) then
            -- Create Backup
            if fileExists(fileName) then
                if fileExists("addons/backups/"..fileName..".bak") then fileDelete("addons/backups/"..fileName..".bak") end
                fileRename(fileName, "addons/backups/"..fileName..".bak")
            end
            
            -- Replace File
            if fileExists(fileName) then fileDelete(fileName) end
            fileRename(tempName, fileName)
        end
    end

    outputChatBox(string.format("%s[%sVisionX%s] %sUpdate applied. Restarting...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), root, 255, 255, 255, true)
    
    if hasObjectPermissionTo(resource, "function.restartResource") then
        setTimer(function() restartResource(resource) end, 2000, 1)
    end
end

-- Manual command
addCommandHandler("vx", function(player, cmd, arg)
    if arg and arg:lower() == "update" then checkForUpdates(true, player) end
end)