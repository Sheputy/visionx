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

-- UX Colors
local BRAND_COLOR = "#0DBCFF"   -- Blue
local TEXT_COLOR  = "#FFFFFF"   -- White
local INFO_COLOR  = "#FFA64C"   -- Orange (feedback)
local ERROR_COLOR = "#FF4C4C"   -- Red (errors)

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

local function isResourceInAdminGroup()
    if not hasObjectPermissionTo(getThisResource(), "function.aclGetGroup", false) then
        return false
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
        outputChatBox(
            string.format(
                "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FFA64CFirst Install Detected.#FFFFFF Run: #FFFF00/aclrequest allow %s all",
                resourceName
            ),
            root, 255, 255, 255, true
        )
        outputChatBox(
            string.format(
                "#FFA64C> #FFFFFFIf that fails, add #FFFF00resource.%s #FFFFFFto the #FFA64CAdmin#FFFFFF group.",
                resourceName
            ),
            root, 255, 255, 255, true
        )
        return
    end

    -- 2. CRITICAL PERMISSIONS CHECK
    local resource = getThisResource()
    local perm = "function.fetchRemote"

    if not hasObjectPermissionTo(resource, perm) then
        outputChatBox(
            string.format(
                "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FF4C4CError:#FFFFFF Missing permission '#FFA64C%s#FFFFFF'. Run: #FFFF00/aclrequest allow %s %s",
                perm, getResourceName(resource), perm
            ),
            root, 255, 255, 255, true
        )
        return
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

    -- Permission check per-call
    local perm = "function.fetchRemote"
    if not hasObjectPermissionTo(getThisResource(), perm) then
        if isManual then
            outputChatBox(
                string.format(
                    "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FF4C4CError:#FFFFFF Missing permission '#FFA64C%s#FFFFFF'. Run: #FFFF00/aclrequest allow %s all",
                    perm, resourceName, perm
                ),
                player, 255, 255, 255, true
            )
        else
            outputChatBox(
                string.format(
                    "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FF4C4CAuto-Update Disabled:#FFFFFF Missing '#FFA64C%s#FFFFFF'.",
                    perm
                ),
                root, 255, 255, 255, true
            )
        end
        return
    end

    -- Prevent running on corrupted meta
    if currentVersion == "0.0.0" then return end

    if isManual then
        outputChatBox(
            "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FFA64CChecking for updates...#FFFFFF",
            player, 255, 255, 255, true
        )
    end

    local metaURL = GITHUB_RAW_URL .. "meta.xml?cb=" .. getTickCount()

    fetchRemote(metaURL, function(data, err)
        if err ~= 0 or not data then
            if isManual then
                outputChatBox(
                    "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FF4C4CUpdate check failed.#FFFFFF",
                    player, 255, 255, 255, true
                )
            end
            return
        end

        local remoteVer = data:match('version="([^"]+)"')
        if remoteVer and isNewer(remoteVer, currentVersion) then
            outputChatBox(
                string.format(
                    "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FFA64CUpdate found:#FFFFFF version %s. Downloading...",
                    remoteVer
                ),
                root, 255, 255, 255, true
            )
            processUpdate(data)
        elseif isManual then
            outputChatBox(
                "#FFFFFF[#0DBCFFVisionX#FFFFFF] #65FF65You're already on the latest version.#FFFFFF",
                player, 255, 255, 255, true
            )
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

------------------------------------------------------------
-- APPLY UPDATE
------------------------------------------------------------
function applyUpdate(fileList, tempPrefix)
    outputServerLog("[VisionX] Download complete. Applying update...")
    
    if not fileExists("addons/backups") then
        local dummy = fileCreate("addons/backups/.keep")
        if dummy then fileClose(dummy) end
    end

    for _, fileName in ipairs(fileList) do
        local tempName = tempPrefix .. fileName:gsub("/", "_")
        
        if fileExists(tempName) then
            if fileExists(fileName) then
                if fileExists("addons/backups/"..fileName..".bak") then
                    fileDelete("addons/backups/"..fileName..".bak")
                end
                fileRename(fileName, "addons/backups/"..fileName..".bak")
            end
            
            if fileExists(fileName) then fileDelete(fileName) end
            fileRename(tempName, fileName)
        end
    end

    outputChatBox(
        "#FFFFFF[#0DBCFFVisionX#FFFFFF] #FFA64CUpdate applied.#FFFFFF Restarting...",
        root, 255, 255, 255, true
    )
    
    if hasObjectPermissionTo(resource, "function.restartResource") then
        setTimer(function() restartResource(resource) end, 2000, 1)
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
