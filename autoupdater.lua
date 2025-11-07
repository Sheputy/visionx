--[[
============================================================
--  VisionX Auto-Updater
--  Repository: https://github.com/Sheputy/visionx
--  Description: Automatically fetches and applies the latest
--  VisionX updates from GitHub. Checks every 24 hours.
--  Requires fetchRemote permissions in ACL:
--      /aclrequest allow visionx all
============================================================
]]

local autoUpdate = true
local REPO_CONTENT_URL = "https://api.github.com/repos/Sheputy/visionx/contents"
local REPO_COMMITS_URL = "https://api.github.com/repos/Sheputy/visionx/commits"
local RESOURCE_NAME = getResourceName(getThisResource())

local filesFetched = 0
local remoteFiles = {}

addEventHandler("onResourceStart", resourceRoot, function()
    queueGitRepo()
    setTimer(queueGitRepo, 24*60*60*1000, 0) -- every 24 hours
end)

function queueGitRepo()
    if not autoUpdate then return end

    filesFetched = 0
    remoteFiles = {}

    if not hasObjectPermissionTo(resource, "function.fetchRemote") then
        setTimer(function()
            outputChatBox("[#64B5FFVisionX#FFFFFF] #FF6464Auto-update disabled. Run #FFD700/aclrequest allow " .. RESOURCE_NAME .. " all#FFFFFF then restart.", root, 255, 255, 255, true)
            outputDebugString("[VisionX Updater] Missing ACL permissions for fetchRemote. Use /aclrequest allow " .. RESOURCE_NAME .. " all", 2, 255, 100, 100)
        end, 1000, 1)
        return
    end

    outputDebugString("[VisionX Updater] Checking GitHub for updates...", 4, 100, 255, 100)

    fetchRemote(REPO_CONTENT_URL, function(response, err)
        if err ~= 0 or response == "ERROR" then
            outputDebugString("[VisionX Updater] Failed to fetch GitHub content. Error code: " .. tostring(err), 2, 255, 100, 100)
            return
        end

        local data = fromJSON(response)
        if type(data) ~= "table" then
            outputDebugString("[VisionX Updater] Invalid JSON response.", 2, 255, 100, 100)
            return
        end

        local dataToSave = {}
        for _, v in ipairs(data) do
            if v.download_url and v.name then
                -- only update script/config files
                if v.name:match("%.lua$") or v.name:match("%.json$") or v.name:match("%.xml$") or v.name:match("%.md$") or v.name:match("%.txt$") then
                    remoteFiles[v.name] = {url = v.download_url, sha = v.sha}
                    dataToSave[v.name] = {sha = v.sha}
                    filesFetched = filesFetched + 1
                end
            end
        end

        if filesFetched == 0 then
            outputDebugString("[VisionX Updater] No valid files to update found.", 4, 255, 255, 100)
            return
        end

        setTimer(function() downloadRepoFiles(dataToSave) end, 1000, 1)
    end)
end

function downloadRepoFiles(data2save)
    for k, v in pairs(remoteFiles) do
        fetchRemote(v.url, function(response)
            if response and response ~= "ERROR" then
                remoteFiles[k].data = response
            end
            filesFetched = filesFetched - 1
            if filesFetched <= 0 then
                processFiles(data2save)
            end
        end)
    end
end

function processFiles(data2save)
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
            -- backup old version
            if not fileExists("addons/backups") then
                fileCreate("addons/backups/test.tmp")
                fileDelete("addons/backups/test.tmp")
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

    saveDirectoryData(toJSON(data2save, true))

    if #modifiedFiles > 0 then
        fetchRemote(REPO_COMMITS_URL, function(response, err)
            local commits = response and fromJSON(response)
            local title = commits and commits[1] and commits[1].commit and commits[1].commit.message or "Unknown Update"
            outputDebugString("[VisionX Updater] Updated files: " .. table.concat(modifiedFiles, ", "), 4, 100, 255, 100)
            outputDebugString("[VisionX Updater] Latest commit: " .. title, 4, 100, 255, 100)
            outputChatBox("[#64B5FFVisionX#FFFFFF] Updated successfully! #FFD700"..#modifiedFiles.."#FFFFFF files changed. Commit: #64B5FF"..title, root, 255, 255, 255, true)

            if hasObjectPermissionTo(resource, "function.restartResource") then
                restartResource(resource)
            else
                outputDebugString("[VisionX Updater] No restart permission. Please restart manually.", 2, 255, 100, 100)
            end
        end)
    else
        outputDebugString("[VisionX Updater] No updates found. VisionX is up to date.", 4, 255, 255, 100)
    end
end

function saveDirectoryData(data)
    if fileExists("addons/autoupdater.json") then fileDelete("addons/autoupdater.json") end
    local file = fileCreate("addons/autoupdater.json")
    if file then
        fileWrite(file, data)
        fileClose(file)
    end
end

function loadDirectoryData()
    if not fileExists("addons/autoupdater.json") then return nil end
    local file = fileOpen("addons/autoupdater.json")
    local data = fileRead(file, fileGetSize(file))
    fileClose(file)
    return data
end
