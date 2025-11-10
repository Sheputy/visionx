--[[
============================================================
--  VisionX Auto-Updater
--  Repository: https://github.com/Sheputy/visionx
--  Description: Automatically fetches and applies the latest
--  VisionX updates from GitHub. Checks every 24 hours.
--  Manual update: /vx update
--  Brand Color: #0DBCFF
--  Requires fetchRemote permissions in ACL:
--      /aclrequest allow visionx32 all
============================================================
]]

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
local autoUpdate = true
local REPO_CONTENT_URL = "https://api.github.com/repos/Sheputy/visionx/contents"
local REPO_COMMITS_URL = "https://api.github.com/repos/Sheputy/visionx/commits"
local RESOURCE_NAME = getResourceName(getThisResource())

local BRAND_COLOR = "#0DBCFF"
local TEXT_COLOR = "#FFFFFF"
local FAIL_COLOR = "#FF6464"
local INFO_COLOR = "#FFA64C"

local filesFetched = 0
local remoteFiles = {}

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    outputChatBox(string.format("%s[%sVisionX%s] %sUpdater initialized.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), root, 255, 255, 255, true)
    if autoUpdate then
        queueGitRepo()
        setTimer(queueGitRepo, 24 * 60 * 60 * 1000, 0) -- every 24 hours
    end
end)

------------------------------------------------------------
-- MANUAL UPDATE COMMAND (/vx update)
------------------------------------------------------------
addCommandHandler("vx", function(player, cmd, arg)
    if arg and arg:lower() == "update" then
        outputChatBox(string.format("%s[%sVisionX%s] %sManual update triggered...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player, 255, 255, 255, true)
        queueGitRepo(true, player)
    elseif player and isElement(player) then
        outputChatBox(string.format("%s[%sVisionX%s] %sUsage: /vx update%s — manually check for updates.", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR), player, 255, 255, 255, true)
    end
end)

------------------------------------------------------------
-- FETCH GITHUB CONTENT
------------------------------------------------------------
function queueGitRepo(isManual, player)
    if not hasObjectPermissionTo(resource, "function.fetchRemote") then
        outputChatBox(string.format("%s[%sVisionX%s] %sMissing%s fetchRemote %spermission.%s Run %s/aclrequest allow %s all%s then restart.", 
            TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR, TEXT_COLOR, FAIL_COLOR, TEXT_COLOR, INFO_COLOR, RESOURCE_NAME, TEXT_COLOR), root, 255, 255, 255, true)
        return
    end

    outputChatBox(string.format("%s[%sVisionX%s] %sChecking GitHub for updates...", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR), player or root, 255, 255, 255, true)
    fetchRemote(REPO_CONTENT_URL, function(response, err)
        if err ~= 0 or response == "ERROR" then
            outputChatBox(string.format("%s[%sVisionX%s] %sFailed%s to connect to GitHub (%sError %d%s).", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR, TEXT_COLOR, FAIL_COLOR, err, TEXT_COLOR), player or root, 255, 255, 255, true)
            return
        end

        local data = fromJSON(response)
        if type(data) ~= "table" then
            outputChatBox(string.format("%s[%sVisionX%s] %sInvalid GitHub response.%s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR, TEXT_COLOR), player or root, 255, 255, 255, true)
            return
        end

        local dataToSave = {}
        filesFetched = 0
        remoteFiles = {}

        for _, v in ipairs(data) do
            if v.download_url and v.name then
                if v.name:match("%.lua$") or v.name:match("%.json$") or v.name:match("%.xml$") or v.name:match("%.md$") or v.name:match("%.txt$") then
                    remoteFiles[v.name] = {url = v.download_url, sha = v.sha}
                    dataToSave[v.name] = {sha = v.sha}
                    filesFetched = filesFetched + 1
                end
            end
        end

        if filesFetched == 0 then
            outputChatBox(string.format("%s[%sVisionX%s] %sNo updates found.%s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR), player or root, 255, 255, 255, true)
            return
        end

        setTimer(function() downloadRepoFiles(dataToSave, player) end, 1000, 1)
    end)
end

------------------------------------------------------------
-- DOWNLOAD FILES FROM GITHUB
------------------------------------------------------------
function downloadRepoFiles(dataToSave, player)
    for k, v in pairs(remoteFiles) do
        fetchRemote(v.url, function(response)
            if response and response ~= "ERROR" then
                remoteFiles[k].data = response
            end
            filesFetched = filesFetched - 1
            if filesFetched <= 0 then
                processFiles(dataToSave, player)
            end
        end)
    end
end

------------------------------------------------------------
-- PROCESS DOWNLOADED FILES
------------------------------------------------------------
function processFiles(dataToSave, player)
    local modifiedFiles = {}
    local localData = loadDirectoryData()
    local parsedData = localData and fromJSON(localData) or {}

    for fileName, remoteData in pairs(remoteFiles) do
        local updateRequired = false
        remoteData.sha = remoteData.sha:upper()

        if parsedData[fileName] and fileExists(fileName) then
            if parsedData[fileName].sha:upper() ~= remoteData.sha then
                updateRequired = true
            end
        else
            updateRequired = true
        end

        if updateRequired then
            if fileExists("addons/backups/"..fileName..".bak") then
                fileDelete("addons/backups/"..fileName..".bak")
            end
            if fileExists(fileName) then
                fileRename(fileName, "addons/backups/"..fileName..".bak")
            end

            local file = fileCreate(fileName)
            if file then
                fileWrite(file, remoteData.data)
                fileClose(file)
                table.insert(modifiedFiles, fileName)
            end
        end
    end

    saveDirectoryData(toJSON(dataToSave, true))

    if #modifiedFiles > 0 then
        fetchRemote(REPO_COMMITS_URL, function(response)
            local commits = response and fromJSON(response)
            local title = commits and commits[1] and commits[1].commit and commits[1].commit.message or "Unknown Update"

            outputChatBox(string.format("%s[%sVisionX%s] %sUpdated successfully!%s (%d files changed)", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR, #modifiedFiles), player or root, 255, 255, 255, true)
            outputChatBox(string.format("%s[%sVisionX%s] %sCommit:%s %s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR, title), player or root, 255, 255, 255, true)

            if hasObjectPermissionTo(resource, "function.restartResource") then
                restartResource(resource)
            else
                outputChatBox(string.format("%s[%sVisionX%s] %sRestart manually to apply updates.%s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR), player or root, 255, 255, 255, true)
            end
        end)
    else
        outputChatBox(string.format("%s[%sVisionX%s] %sVisionX is already up to date.%s", TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, TEXT_COLOR), player or root, 255, 255, 255, true)
    end
end

------------------------------------------------------------
-- SAVE / LOAD (auto-create addons folder if missing)
------------------------------------------------------------

-- Helper function to ensure 'addons' folder exists
local function ensureAddonsFolder()
    if not fileExists("addons") then
        fileCreate("addons/.keep")  -- creates folder via placeholder file
        fileDelete("addons/.keep")
    end
end

function saveDirectoryData(data)
    ensureAddonsFolder()
    if fileExists("addons/autoupdater.json") then fileDelete("addons/autoupdater.json") end
    local file = fileCreate("addons/autoupdater.json")
    if file then
        fileWrite(file, data)
        fileClose(file)
    else
        outputDebugString("[VisionX] Failed to create addons/autoupdater.json", 1)
    end
end

function loadDirectoryData()
    ensureAddonsFolder()
    if not fileExists("addons/autoupdater.json") then return nil end
    local file = fileOpen("addons/autoupdater.json")
    if not file then return nil end
    local data = fileRead(file, fileGetSize(file))
    fileClose(file)
    return data
end
