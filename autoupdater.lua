--[[
============================================================
--  VisionX Auto-Updater (Raw)
--  Repository: https://github.com/Sheputy/visionx
--  Description: Checks raw meta.xml for version changes.
--  Changelog:
--   - v3.2.5 - Added 24h timer & Critical Admin checks for Build/Update.
============================================================
]]

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
local autoUpdate = true
local AUTO_UPDATE_INTERVAL = 24 * 60 * 60 * 1000 -- 24 Hours (in milliseconds)
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/Sheputy/visionx/main/"

local BRAND_COLOR = "#0DBCFF"
local TEXT_COLOR = "#FFFFFF"
local FAIL_COLOR = "#FF6464"
local INFO_COLOR = "#FFA64C"

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local currentVersion = "0.0.0" -- Will be overwritten by getLocalVersion
local resourceName = getResourceName(getThisResource())

------------------------------------------------------------
-- UTILS: GET LOCAL VERSION
------------------------------------------------------------
local function getLocalVersion()
    local meta = xmlLoadFile("meta.xml")
    if meta then
        local info = xmlFindChild(meta, "info", 0)
        if info then
            currentVersion = xmlNodeGetAttribute(info, "version") or "0.0.0"
        end
        xmlUnloadFile(meta)
    end
    return currentVersion
end

------------------------------------------------------------
-- UTILS: VERSION COMPARISON
------------------------------------------------------------
-- Returns true if v1 (remote) is greater than v2 (local)
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

------------------------------------------------------------
-- STARTUP & PERMISSION CHECK
------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    getLocalVersion()
    outputChatBox(string.format("%s[%sVisionX%s] %sUpdater initialized. Current Version: %s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, currentVersion), root, 255, 255, 255, true)
    
    -- 1. CRITICAL PERMISSION CHECK
    -- We check for 'general.ModifyOtherObjects' because the Builder needs to edit other map files.
    local permissionsNeeded = {
        "function.fetchRemote",
        "function.fileCreate",
        "function.fileWrite",
        "function.restartResource", 
        "general.ModifyOtherObjects" -- Required for 'vx build' to save into map resources
    }
    
    local missingPerms = false
    for _, perm in ipairs(permissionsNeeded) do
        if not hasObjectPermissionTo(getThisResource(), perm, false) then
            missingPerms = true
            break
        end
    end

    if missingPerms then
        outputChatBox(string.format("%s[%sVisionX%s] #FF0000CRITICAL ERROR: Missing Admin Rights!", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR), root, 255, 255, 255, true)
        outputChatBox("#FF0000VisionX needs Admin to Update itself AND to Save scripts to your maps.", root, 255, 255, 255, true)
        outputChatBox("#FF0000Please run: #FFFFFF/aclrequest allow " .. resourceName .. " all", root, 255, 255, 255, true)
        outputChatBox("#FF0000Or add 'resource." .. resourceName .. "' to the Admin ACL group manually.", root, 255, 255, 255, true)
        outputServerLog("[VisionX] CRITICAL: Missing permissions. 'vx build' and Auto-Update will fail. Add resource." .. resourceName .. " to Admin ACL.")
    end

    -- 2. START TIMER
    if autoUpdate then
        checkForUpdates()
        setTimer(checkForUpdates, AUTO_UPDATE_INTERVAL, 0)
    end
end)

------------------------------------------------------------
-- UPDATE CHECKER
------------------------------------------------------------
function checkForUpdates(isManual, player)
    if not hasObjectPermissionTo(resource, "function.fetchRemote") then
        if isManual then 
            outputChatBox(string.format("%s[%sVisionX%s] %sCannot check for updates: Missing fetchRemote permission.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR), player, 255, 255, 255, true)
        end
        return
    end

    if isManual then
        outputChatBox(string.format("%s[%sVisionX%s] %sChecking for updates...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player, 255, 255, 255, true)
    end

    -- Fetch remote meta.xml with cache buster
    local metaURL = GITHUB_RAW_URL .. "meta.xml?cb=" .. getTickCount()
    
    fetchRemote(metaURL, function(data, err)
        if err ~= 0 or not data then
            if isManual then
                outputChatBox(string.format("%s[%sVisionX%s] %sFailed to fetch remote meta.xml (Error %d)", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR, err), player, 255, 255, 255, true)
            end
            return
        end

        -- Extract version from remote XML string
        local remoteVer = data:match('version="([^"]+)"')
        
        if remoteVer then
            if isNewer(remoteVer, currentVersion) then
                outputChatBox(string.format("%s[%sVisionX%s] %sUpdate found! (%s -> %s). Downloading...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, currentVersion, remoteVer), root, 255, 255, 255, true)
                processUpdate(data) -- Pass the remote meta content to parse file list
            else
                if isManual then
                    outputChatBox(string.format("%s[%sVisionX%s] %sAlready up to date.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player, 255, 255, 255, true)
                end
            end
        else
            outputDebugString("[VisionX] Could not parse remote version string.")
        end
    end)
end

------------------------------------------------------------
-- DOWNLOAD LOGIC
------------------------------------------------------------
function processUpdate(metaContent)
    local filesToDownload = {}
    
    -- Extract all script/file src paths from the raw meta content
    -- Matches <script src="xyz" /> and <file src="xyz" />
    for path in metaContent:gmatch('src="([^"]+)"') do
        table.insert(filesToDownload, path)
    end
    
    -- Always include meta.xml itself
    table.insert(filesToDownload, "meta.xml")

    if #filesToDownload == 0 then return end

    local downloaded = 0
    local total = #filesToDownload
    
    -- Ensure backup directory exists
    if not fileExists("addons/backups") then
        local dummy = fileCreate("addons/backups/.keep")
        if dummy then fileClose(dummy) end
    end

    for _, fileName in ipairs(filesToDownload) do
        local url = GITHUB_RAW_URL .. fileName .. "?cb=" .. getTickCount()
        
        fetchRemote(url, function(data, err)
            if err == 0 and data then
                -- Backup Logic
                if fileExists(fileName) then
                    if fileExists("addons/backups/"..fileName..".bak") then fileDelete("addons/backups/"..fileName..".bak") end
                    fileRename(fileName, "addons/backups/"..fileName..".bak")
                end

                -- Write New File
                local file = fileCreate(fileName)
                if file then
                    fileWrite(file, data)
                    fileClose(file)
                end
            else
                outputDebugString("[VisionX] Failed to download: " .. fileName)
            end

            downloaded = downloaded + 1
            if downloaded >= total then
                outputChatBox(string.format("%s[%sVisionX%s] %sUpdate complete! Restarting...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), root, 255, 255, 255, true)
                
                -- AUTO-RESTART LOGIC
                if hasObjectPermissionTo(resource, "function.restartResource") then
                    setTimer(function() restartResource(resource) end, 1000, 1)
                else
                    -- This technically shouldn't happen if they listened to the startup warning, but just in case:
                    outputChatBox(string.format("%s[%sVisionX%s] %sRestart manually to apply updates (Missing restart permission).", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR), root, 255, 255, 255, true)
                end
            end
        end)
    end
end

------------------------------------------------------------
-- MANUAL COMMAND
------------------------------------------------------------
addCommandHandler("vx", function(player, cmd, arg)
    if arg and arg:lower() == "update" then
        checkForUpdates(true, player)
    end
end)