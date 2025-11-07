--[[
    * VisionX Auto-Updater (©2025)
    * Based on MTP Updater (chris1384) — rewritten for VisionX by Corrupt.
    * Auto-fetches and updates VisionX files from GitHub.
    * Uses VisionX brand colors for all chat outputs.
]]

local autoUpdate = true
local filesFetched = 0
local remoteFiles = {}
local resourceName = getResourceName(getThisResource())

-- Brand colors
local BRAND_COLOR = "#0DBCFF"   -- VisionX blue
local TEXT_COLOR  = "#FFFFFF"   -- white text
local FAIL_COLOR  = "#FF6464"   -- red (failed/important)
local INFO_COLOR  = "#FFA64C"   -- orange (info/warning)

---------------------------------------------------------------------
-- Start-Up: Check ACL permissions and trigger updater
---------------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    if not autoUpdate then return end

    if not hasObjectPermissionTo(resource, "function.fetchRemote") then
        outputChatBox(
            string.format("%s[%sVisionX%s] %s Missing %sfetchRemote%s permission.",
            TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, TEXT_COLOR, FAIL_COLOR, TEXT_COLOR),
            root, 255, 255, 255, true
        )
        outputChatBox(
            string.format("%sUse %s/aclrequest allow %s all%s then restart VisionX.",
            TEXT_COLOR, INFO_COLOR, resourceName, TEXT_COLOR),
            root, 255, 255, 255, true
        )
        outputDebugString("[VisionX Updater] Missing ACL permissions (fetchRemote). Waiting for manual grant.")
        return
    end

    VisionX_QueueRepo()
end)

---------------------------------------------------------------------
-- Fetch Repo Files
---------------------------------------------------------------------
function VisionX_QueueRepo()
    fetchRemote("https://api.github.com/repos/Sheputy/visionx/contents", function(response, err)
        if response == "ERROR" or err ~= 0 then
            outputChatBox(
                string.format("%s[%sVisionX%s] %s Failed to connect to GitHub (Error %s%s%s).",
                TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR, INFO_COLOR, tostring(err), TEXT_COLOR),
                root, 255, 255, 255, true
            )
            return
        end

        local repo = fromJSON(response)
        if not repo or type(repo) ~= "table" then
            outputChatBox(
                string.format("%s[%sVisionX%s] %s Invalid GitHub response.",
                TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR),
                root, 255, 255, 255, true
            )
            return
        end

        remoteFiles = {}
        filesFetched = 0

        for _, v in ipairs(repo) do
            if v.download_url then
                remoteFiles[v.name] = v.download_url
                filesFetched = filesFetched + 1
            end
        end

        if filesFetched > 0 then
            outputChatBox(
                string.format("%s[%sVisionX%s] %s Downloading latest update...",
                TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR),
                root, 255, 255, 255, true
            )
            VisionX_DownloadFiles()
        else
            outputChatBox(
                string.format("%s[%sVisionX%s] %s VisionX is already up to date.",
                TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR),
                root, 255, 255, 255, true
            )
        end
    end)
end

---------------------------------------------------------------------
-- Download Updated Files
---------------------------------------------------------------------
function VisionX_DownloadFiles()
    local updated = {}
    local count = 0
    for name, url in pairs(remoteFiles) do
        fetchRemote(url, function(data, err)
            count = count + 1
            if err == 0 and data and data ~= "" then
                if fileExists(name) then fileDelete(name) end
                local f = fileCreate(name)
                if f then
                    fileWrite(f, data)
                    fileClose(f)
                    table.insert(updated, name)
                end
            end

            if count == filesFetched then
                VisionX_FinishUpdate(updated)
            end
        end)
    end
end

---------------------------------------------------------------------
-- Complete Update
---------------------------------------------------------------------
function VisionX_FinishUpdate(updated)
    if #updated == 0 then
        outputChatBox(
            string.format("%s[%sVisionX%s] %s No updates found.",
            TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR),
            root, 255, 255, 255, true
        )
        return
    end

    outputChatBox(
        string.format("%s[%sVisionX%s] %s Updated %s%s%s file(s).",
        TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, INFO_COLOR, BRAND_COLOR, tostring(#updated), TEXT_COLOR),
        root, 255, 255, 255, true
    )
    outputDebugString("[VisionX Updater] Updated " .. tostring(#updated) .. " file(s). Restarting...")

    if hasObjectPermissionTo(resource, "function.restartResource") then
        restartResource(resource)
    else
        outputChatBox(
            string.format("%s[%sVisionX%s] %s Update complete. Restart manually to apply changes.",
            TEXT_COLOR, BRAND_COLOR, TEXT_COLOR, FAIL_COLOR),
            root, 255, 255, 255, true
        )
    end
end
