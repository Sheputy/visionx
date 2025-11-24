--[[
============================================================
--  VisionX Auto-Updater (Raw)
--  Repository: https://github.com/Sheputy/visionx
--  Description: Checks raw meta.xml for version changes.
-- Changelog:
--  - v3.2.4 - Improved backup handling and fixed "No update available Error".
============================================================
]]

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
local autoUpdate = true
local AUTO_UPDATE_INTERVAL = 3600000 -- 1 Hour
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/Sheputy/visionx/main/"

local BRAND_COLOR = "#0DBCFF"
local TEXT_COLOR = "#FFFFFF"
local FAIL_COLOR = "#FF6464"
local INFO_COLOR = "#FFA64C"

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local currentVersion = "3.2.4"
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
-- STARTUP
------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    getLocalVersion()
    outputChatBox(string.format("%s[%sVisionX%s] %sUpdater initialized. Current Version: %s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, currentVersion), root, 255, 255, 255, true)
    
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
        outputChatBox(string.format("%s[%sVisionX%s] %sMissing fetchRemote permission.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR), root, 255, 255, 255, true)
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
                if hasObjectPermissionTo(resource, "function.restartResource") then
                    setTimer(function() restartResource(resource) end, 1000, 1)
                else
                    outputChatBox(string.format("%s[%sVisionX%s] %sPlease restart manually.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR), root, 255, 255, 255, true)
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