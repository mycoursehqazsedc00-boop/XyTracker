-- Place at top of file
function XyButton_UpdatePosition()
    if XyButtonFrame then
        XyButtonFrame:SetPoint(
            "TOPLEFT", "Minimap", "TOPLEFT",
            54 - (78 * cos(200)),
            (78 * sin(200)) - 55
        );
    end
end

-- Plugin constants and global variables
local XyInProgress, NewDKP, IsLeader, Xys, NoXyList, curItem, rollEndTime, rollData, isRolling, LeaderName
local WasInRaid  -- tracks whether we were in a raid last time we checked (locale-independent join/leave detection)
local XyItemCount = {}  -- Tracks SR count per item
XY_BUTTON_HEIGHT = 25;
Xy_SortOptions = { ["method"] = "", ["itemway"] = "" };
UnitPopupButtons["GET_XY"]    = { text = "Look up SR", dist = 0 };
UnitPopupButtons["ADD_DKP"]   = { text = "+DKP", dist = 0, nested = 1 };
UnitPopupButtons["Minus_DKP"] = { text = "-DKP", dist = 0, nested = 1 };

-- DKP submenu buttons
UnitPopupButtons["ADD_DKP_1"]   = { text = "+1dkp", dist = 0 };
UnitPopupButtons["ADD_DKP_2"]   = { text = "+2dkp", dist = 0 };
UnitPopupButtons["ADD_DKP_3"]   = { text = "+3dkp", dist = 0 };
UnitPopupButtons["ADD_DKP_4"]   = { text = "+4dkp", dist = 0 };
UnitPopupButtons["MINUS_DKP_1"] = { text = "-1dkp", dist = 0 };
UnitPopupButtons["MINUS_DKP_2"] = { text = "-2dkp", dist = 0 };
UnitPopupButtons["MINUS_DKP_3"] = { text = "-3dkp", dist = 0 };
UnitPopupButtons["MINUS_DKP_4"] = { text = "-4dkp", dist = 0 };

NewDKP = false

-- Declaration variable
local playerDeclaration = ""

-- Open the declaration editor window
function XyTracker_OnDeclarationButtonClick()
    local declarationWindow  = getglobal("XyTrackerDeclarationFrame")
    local declarationEditBox = getglobal("XyTrackerDeclarationLargeEditBox")

    -- Load saved declaration, prefer XyTrackerOptions value
    if XyTrackerOptions and XyTrackerOptions.Declaration and XyTrackerOptions.Declaration ~= "" then
        declarationEditBox:SetText(XyTrackerOptions.Declaration)
    elseif playerDeclaration and playerDeclaration ~= "" then
        declarationEditBox:SetText(playerDeclaration)
    else
        declarationEditBox:SetText("")
    end

    declarationEditBox:SetFocus()
    declarationWindow:Show()
    DEFAULT_CHAT_FRAME:AddMessage("Declaration window opened")
end

-- Save the declaration text
function XyTracker_SaveDeclaration()
    local declarationEditBox = getglobal("XyTrackerDeclarationLargeEditBox")
    local declarationWindow  = getglobal("XyTrackerDeclarationFrame")
    local newDeclaration = declarationEditBox:GetText()

    playerDeclaration = newDeclaration

    if not XyTrackerOptions then XyTrackerOptions = {} end
    XyTrackerOptions.Declaration = newDeclaration

    if newDeclaration and newDeclaration ~= "" then
        DEFAULT_CHAT_FRAME:AddMessage("Declaration saved: " .. newDeclaration)
    end
    DEFAULT_CHAT_FRAME:AddMessage("Declaration saved to playerDeclaration and XyTrackerOptions.Declaration")
    declarationWindow:Hide()
end

-- Announce the declaration to raid warning channel, line by line
function XyTracker_OnAnnounceDeclarationButtonClick()
    local declarationText = playerDeclaration

    if declarationText and declarationText ~= "" then
        local lineCount  = 0
        local startPos   = 1
        local textLength = string.len(declarationText)

        while startPos <= textLength do
            local endPos = string.find(declarationText, "\n", startPos)
            if not endPos then endPos = textLength + 1 end

            local line = string.sub(declarationText, startPos, endPos - 1)
            if line and line ~= "" then
                lineCount = lineCount + 1
                if lineCount == 1 then
                    SendChatMessage("[Raid Declaration] " .. line, "RAID_WARNING", nil, nil)
                else
                    SendChatMessage(line, "RAID_WARNING", nil, nil)
                end
            end
            startPos = endPos + 1
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("No declaration set. Please write one first.")
    end
end

-- Roll monitor feature
function RollStart()
    rollData    = {}
    isRolling   = true
    rollEndTime = GetTime() + tonumber(XyTrackerOptions.rollTime);
    SendChatMessage(curItem .. " roll started, ends in " .. XyTrackerOptions.rollTime .. " seconds", "RAID", this.language, nil)
end

function RollEnd()
    rollEndTime = GetTime()
    isRolling   = false
    if getn(rollData) > 0 then
        SendChatMessage(curItem .. " Winner: " .. rollData[1]["name"] .. " rolled [" .. rollData[1]["roll"] .. "]", "RAID", this.language, nil)
    else
        SendChatMessage(curItem .. " No one rolled.", "RAID", this.language, nil)
    end
end

function RollMonitor_Clear()
    rollData = {}
    RollMonitor_UpdateList()
    getglobal("RollMonitorFrame"):Hide();
end

-- Stores per-player raid chat messages (used for auto-deduct)
local raidMessages = {}

-- Checkbox callbacks
function autoMin_OnClick()        XyTrackerOptions.autoMinDkp      = this:GetChecked() end
function greenMode_OnClick()      XyTrackerOptions.greenModeEnabled = this:GetChecked() end
function blueMode_OnClick()       XyTrackerOptions.blueModeEnabled  = this:GetChecked() end
function purpleMode_OnClick()     XyTrackerOptions.purpleModeEnabled = this:GetChecked() end
function autoClearOnLeave_OnClick() XyTrackerOptions.autoClearOnLeave = this:GetChecked() end

function autoMode_OnClick()
    XyTrackerOptions.XyOnlyMode = this:GetChecked() and 1 or 0
end

function autoAnnounce_OnClick()
    XyTrackerOptions.AutoAnnounce = this:GetChecked() and true or false
end

-- Load default DKP value into the input box
function printDefaultDKP()
    getglobal("allDKPFrameTXT"):SetText(DefaultDKP);
end

-- Apply a new default DKP to all members
function NEWDefaultDKP()
    DefaultDKP = getglobal("allDKPFrameTXT"):GetNumber();
    NewDKP     = true
    XyTracker_OnRefreshButtonClick()
    XyTracker_UpdateList()
    SendChatMessage("Info: All members defaulted to " .. DefaultDKP .. " DKP", "RAID", this.language, nil)
end

-- Check if list l contains value v
function contain(v, l)
    if not l then return false end
    local n = getn(l)
    if n > 0 then
        for i = 1, n do
            if v == l[i] then return true end
        end
    end
    return false
end

-- Strip color codes, spaces, lowercase — used for item name matching
function safeCleanString(str)
    if not str or type(str) ~= "string" then return "" end
    local s = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "%s+", "")
    s = string.lower(s)
    return s
end

-- Mark a specific item as completed in a player's SR string
function MarkItemAsCompleted(originalWish, completedItemName)
    if not originalWish or not completedItemName or
       type(originalWish) ~= "string" or type(completedItemName) ~= "string" then
        return originalWish
    end

    local cleanedCompleted = safeCleanString(completedItemName)
    local foundMatch       = false
    local remainingItems   = {}

    -- Handle item link format: |Hitem:...|h[Name]|h
    if string.find(originalWish, "|Hitem:") then
        local linkPattern = "|c%x%x%x%x%x%x%x%x|Hitem:.-|h%[.-%]|h|r"
        local namePattern = "|h%[(.-)%]|h"
        local startPos    = 1

        while true do
            local s, e = string.find(originalWish, linkPattern, startPos)
            if not s then
                s, e = string.find(originalWish, "|Hitem:.-|h%[.-%]|h", startPos)
                if not s then break end
            end
            local link     = string.sub(originalWish, s, e)
            local _, _, itemName = string.find(link, namePattern)
            if itemName then
                local cleanName = safeCleanString(itemName)
                if cleanName == cleanedCompleted or
                   string.find(cleanName, cleanedCompleted) or
                   string.find(cleanedCompleted, cleanName) then
                    foundMatch = true
                else
                    table.insert(remainingItems, link)
                end
            else
                table.insert(remainingItems, link)
            end
            startPos = e + 1
        end

        if foundMatch then
            if table.getn(remainingItems) > 0 then
                return "|cFF00FFFFPartial SR Done|r" .. table.concat(remainingItems)
            else
                return "|cFF00FFFFAll SR Done|r"
            end
        end
    else
        -- Handle plain [Item1][Item2] format
        if string.find(originalWish, "%[(.-)%]") then
            for item in string.gmatch(originalWish, "%[(.-)%]") do
                if item and item ~= "" then
                    local cleanName = safeCleanString(item)
                    if cleanName == cleanedCompleted or
                       string.find(cleanName, cleanedCompleted) or
                       string.find(cleanedCompleted, cleanName) then
                        foundMatch = true
                    else
                        table.insert(remainingItems, "[" .. item .. "]")
                    end
                end
            end
            if foundMatch then
                if table.getn(remainingItems) > 0 then
                    return "|cFF00FFFFPartial SR Done|r" .. table.concat(remainingItems)
                else
                    return "|cFF00FFFFAll SR Done|r"
                end
            end
        end
    end

    return originalWish
end

-- (Deprecated — kept to avoid errors if called elsewhere)
--[[
function RemoveItemFromXy(xyString, itemId, isComplete)
    if not xyString or xyString == "" or xyString == "---NOSR---" then return xyString end
    if xyString == "|cFF00FFFFAll SR Done|r" then return xyString end
    local pattern = "|Hitem:" .. itemId .. ":.-|h%[.-%]|h"
    local newXy = string.gsub(xyString, pattern, "")
    newXy = string.gsub(newXy, "%s+", " ")
    newXy = string.gsub(newXy, "^%s*(.-)%s*$", "%1")
    if newXy == "" then
        return "|cFF00FFFFAll SR Done|r"
    else
        return isComplete and ("|cFF00FFFFPartial SR Done|r " .. newXy) or newXy
    end
end
--]]

-- Addon initialization
function XyTracker_OnLoad()
    LeaderName = ""  -- Initialize SR manager name

    this:RegisterEvent("VARIABLES_LOADED")

    -- Add SR/DKP options to the party right-click menu
    if UnitPopupMenus["PARTY"] then
        if not contain("GET_XY",    UnitPopupMenus["PARTY"]) then table.insert(UnitPopupMenus["PARTY"], "GET_XY")    end
        if not contain("ADD_DKP",   UnitPopupMenus["PARTY"]) then table.insert(UnitPopupMenus["PARTY"], "ADD_DKP")   end
        if not contain("Minus_DKP", UnitPopupMenus["PARTY"]) then table.insert(UnitPopupMenus["PARTY"], "Minus_DKP") end
    end

    -- Add SR/DKP options to the raid right-click menu
    if UnitPopupMenus["RAID"] then
        if not contain("GET_XY",    UnitPopupMenus["RAID"]) then table.insert(UnitPopupMenus["RAID"], "GET_XY")    end
        if not contain("ADD_DKP",   UnitPopupMenus["RAID"]) then table.insert(UnitPopupMenus["RAID"], "ADD_DKP")   end
        if not contain("Minus_DKP", UnitPopupMenus["RAID"]) then table.insert(UnitPopupMenus["RAID"], "Minus_DKP") end
    end

    -- Load saved declaration
    if XyTrackerOptions and XyTrackerOptions.Declaration and XyTrackerOptions.Declaration ~= "" then
        playerDeclaration = XyTrackerOptions.Declaration
    elseif XyTrackerDeclaration and XyTrackerDeclaration ~= "" then
        playerDeclaration = XyTrackerDeclaration  -- Fall back to old storage
    else
        playerDeclaration = " "
        if not XyTrackerOptions then XyTrackerOptions = {} end
        XyTrackerOptions.Declaration = playerDeclaration
    end

    if playerDeclaration and playerDeclaration ~= "" then
        DEFAULT_CHAT_FRAME:AddMessage("Declaration content loaded")
    end

    -- Slash commands
    SlashCmdList["XYTRACKER"] = XyTracker_OnSlashCommand
    SLASH_XYTRACKER1 = "/xyt"
    SLASH_XYTRACKER2 = "/Xytrack"

    -- Register events
    this:RegisterEvent("CHAT_MSG_SYSTEM")
    this:RegisterEvent("CHAT_MSG_PARTY")
    this:RegisterEvent("CHAT_MSG_RAID")
    this:RegisterEvent("CHAT_MSG_RAID_LEADER")
    this:RegisterEvent("CHAT_MSG_RAID_WARNING")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("CHAT_MSG_WHISPER")
    this:RegisterEvent("CHAT_MSG_LOOT")
    -- Fires on any raid roster change (join/leave/promote/etc). Unlike the
    -- CHAT_MSG_SYSTEM strings below, this event is the same regardless of
    -- client locale, so it reliably catches join/leave on both zhCN and
    -- enUS clients. See XyTracker_OnRaidRosterUpdate().
    this:RegisterEvent("RAID_ROSTER_UPDATE")
    this:RegisterForDrag("LeftButton");

    -- Frame style
    this:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b);
    this:SetBackdropBorderColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);

    -- Hook unit popup
    ori_unitpopup1  = UnitPopup_OnClick;
    UnitPopup_OnClick = ple_unitpopup1;

    -- Initialize saved options
    if not XyTrackerOptions then
        XyTrackerOptions = {
            AutoAnnounce     = false,
            greenModeEnabled = false,
            blueModeEnabled  = false,
            purpleModeEnabled = true,   -- Purple enabled by default
            XyOnlyMode       = 0,
            rollTime         = 60,
            autoMinDkp       = false,
            autoClearOnLeave = true,    -- Auto-clear on leave enabled by default
        }
    end

    if XyArray == nil then XyArray = {} end
    XyInProgress = false
    NoXyList     = ""
    Xys          = 0
    WasInRaid    = GetNumRaidMembers() > 0  -- avoid firing a false join/leave transition on load

    getglobal("autoModeButtons"):SetChecked(XyTrackerOptions.XyOnlyMode);
    getglobal("autoAnnounceButton"):SetChecked(XyTrackerOptions.AutoAnnounce);
    XyTracker_UpdateList()
    SendAddonMessage("XY_SYNC_NEW", "", "RAID")

    -- Load DKP from DB
    if XyTrackerDB then
        for name, data in pairs(XyTrackerDB) do
            local info = getXyInfo(name)
            if info then
                info.dkp = tonumber(data.dkp) or DefaultDKP  -- [FIX] Ensure number
            end
        end
    end

    -- Register DKP submenus
    if not UnitPopupMenus["ADD_DKP"] then
        UnitPopupMenus["ADD_DKP"] = { "ADD_DKP_1", "ADD_DKP_2", "ADD_DKP_3", "ADD_DKP_4" };
    end
    if not UnitPopupMenus["Minus_DKP"] then
        UnitPopupMenus["Minus_DKP"] = { "MINUS_DKP_1", "MINUS_DKP_2", "MINUS_DKP_3", "MINUS_DKP_4" };
    end

-- Enhanced CML Loot Master integration (disabled)
-- 	if CML_Vars and CML_Vars.Enabled then
-- 		...
-- 	end
end

function XYT_InitDropDown()
    XTY_ORGGROUPLOOTDROPDOWN();
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        UIDropDownMenu_AddButton { text = "SR Addon Enhanced", notCheckable = 1, isTitle = 1 }
        UIDropDownMenu_AddButton { text = "Bid",  func = xytShowDKP }
        UIDropDownMenu_AddButton { text = "Roll", func = xytRoll    }
    end
end

function xytShowDKP()
    local item = ITEM_QUALITY_COLORS[LootFrame.selectedQuality].hex .. LootFrame.selectedItemName .. FONT_COLOR_CODE_CLOSE;
    SendChatMessage(item .. " Bid if needed", "RAID", this.language, nil)
end

function xytRoll()
    curItem = ITEM_QUALITY_COLORS[LootFrame.selectedQuality].hex .. LootFrame.selectedItemName .. FONT_COLOR_CODE_CLOSE;
    getglobal("RollMonitorFrameTitle"):SetText("Roll Monitor: " .. curItem);
    getglobal("xytRollTime"):SetText(XyTrackerOptions.rollTime);
    getglobal("RollMonitorFrame"):Show();
end

-- Replacement unit popup click handler
function ple_unitpopup1()
    local dropdownFrame = getglobal(UIDROPDOWNMENU_INIT_MENU);
    local button = this.value;
    local name   = dropdownFrame.name;

    if     button == "GET_XY"    then XyQuery(name);
    elseif button == "ADD_DKP_1" then XyAddDkp(name, 1);
    elseif button == "ADD_DKP_2" then XyAddDkp(name, 2);
    elseif button == "ADD_DKP_3" then XyAddDkp(name, 3);
    elseif button == "ADD_DKP_4" then XyAddDkp(name, 4);
    elseif button == "MINUS_DKP_1" then XyMinusDkp(name, 1);
    elseif button == "MINUS_DKP_2" then XyMinusDkp(name, 2);
    elseif button == "MINUS_DKP_3" then XyMinusDkp(name, 3);
    elseif button == "MINUS_DKP_4" then XyMinusDkp(name, 4);
    else return ori_unitpopup1();
    end

    PlaySound("UChatScrollButton");
end

-- Get or create the SR record for a player
function getXyInfo(name)
    local n = getn(XyArray)
    if n > 0 then
        for i = 1, n do
            local info = XyArray[i]
            if info["name"] == name then
                info["dkp"] = tonumber(info["dkp"]) or DefaultDKP  -- [FIX] Ensure number
                return info
            end
        end
    end
    -- New raid member: create record
    local totalMembers = GetNumRaidMembers()
    if totalMembers then
        for i = 1, totalMembers do
            -- 6th return value is GetRaidRosterInfo's locale-independent
            -- class token (e.g. "HUNTER"); the 5th ("class") is localized
            -- to whichever client is running this code, so we store the
            -- token instead -- see the note above ClassDisplayName().
            local player, rank, subgroup, level, class, fileName = GetRaidRosterInfo(i);
            if name == player then
                local info = { name = name, class = fileName or class, xy = "---NOSR---", dkp = DefaultDKP }
                table.insert(XyArray, info)
                NoXyList = NoXyList .. name .. " "
                return info;
            end
        end
    end
    return nil
end

-- Update the roll monitor display
function RollMonitor_UpdateList()
    FauxScrollFrame_Update(RollListScrollFrame, 10, 10, 25);
    table.sort(rollData, Xy_CompareRolls);
    for i = 1, 10 do
        if i > getn(rollData) then
            getglobal("RollFrameListButton" .. i):Hide();
        else
            local v = rollData[i]
            getglobal("RollFrameListButton" .. i .. "Name"):SetText(v["name"]);
            getglobal("RollFrameListButton" .. i .. "Class"):SetText(ClassDisplayName(v["class"]));
            getglobal("RollFrameListButton" .. i .. "Xy"):SetText(v["xy"]);
            getglobal("RollFrameListButton" .. i .. "DKP"):SetText(v["dkp"]);
            getglobal("RollFrameListButton" .. i .. "Roll"):SetText(v["roll"]);
            getglobal("RollFrameListButton" .. i):Show();
        end
    end
end

function Xy_CompareRolls(a1, a2)
    return tonumber(a1["roll"]) > tonumber(a2["roll"]);
end

-- Rebuild and display the SR list
function XyTracker_UpdateList()
    NoXyList = ""
    Xys      = 0
    local totalMembers       = GetNumRaidMembers()
    local currentRaidMembers = {}

    if totalMembers then
        -- Build member lookup table
        for i = 1, totalMembers do
            currentRaidMembers[GetRaidRosterInfo(i)] = true
        end

        -- Build name-to-index map for fast lookups
        local nameToIndex = {}
        for i = 1, getn(XyArray) do nameToIndex[XyArray[i]["name"]] = i end

        for i = 1, totalMembers do
            -- 6th return value ("fileName") is locale-independent (e.g.
            -- "HUNTER"); the 5th ("class") is localized to whichever
            -- client is running this code. We always store/refresh the
            -- token so an English viewer never ends up displaying class
            -- text that was localized on a Chinese leader's client (or
            -- vice versa) via the XY_SYNC payload. See ClassDisplayName().
            local name, rank, subgroup, level, class, fileName = GetRaidRosterInfo(i);
            local classToken = fileName or class
            local info

            if nameToIndex[name] then
                info = XyArray[nameToIndex[name]]
                info["class"] = classToken  -- keep it current / self-heal old contaminated data
            else
                -- New player, add record
                info = { name = name, class = classToken, xy = "---NOSR---", dkp = DefaultDKP }
                table.insert(XyArray, info)
                nameToIndex[name] = getn(XyArray)
            end

            if info then
                if IsLeader and NewDKP then info["dkp"] = DefaultDKP end
                if info["xy"] and info["xy"] ~= "---NOSR---" and info["xy"] ~= "" then
                    Xys = Xys + 1
                else
                    NoXyList = NoXyList .. name .. " "
                end
            end
        end

        if IsLeader then NewDKP = false end
    end

    -- Status text
    if totalMembers then
        XyTrackerFrameStatusText:SetText(
            XyTracker_If(Xys == totalMembers,
                "All members have SR",
                string.format("%d without SR", totalMembers - Xys)))
    else
        XyTrackerFrameStatusText:SetText("Not in a raid group")
    end
    if XyTrackerFrameStatusText:IsVisible() == false then
        XyTrackerFrameStatusText:Show()
    end

    -- Build display array (current raid members only)
    local displayArray = {}
    if getn(XyArray) > 0 and totalMembers then
        for i = 1, getn(XyArray) do
            if currentRaidMembers[XyArray[i]["name"]] then
                table.insert(displayArray, XyArray[i])
            end
        end
    end

    FauxScrollFrame_Update(XyListScrollFrame, getn(displayArray), 18, 25);

    if getn(displayArray) > 0 then
        local offset = FauxScrollFrame_GetOffset(XyListScrollFrame);
        for i = 1, 18 do
            local k = offset + i;
            if k > getn(displayArray) then
                getglobal("XyFrameListButton" .. i):Hide();
            else
                local v = displayArray[k]
                getglobal("XyFrameListButton" .. i .. "Name"):SetText(v["name"]);
                getglobal("XyFrameListButton" .. i .. "Class"):SetText(ClassDisplayName(v["class"]));
                getglobal("XyFrameListButton" .. i .. "Xy"):SetText(v["xy"]);
                getglobal("XyFrameListButton" .. i .. "DKP"):SetText(v["dkp"]);
                if IsLeader then
                    getglobal("XyFrameListButton" .. i .. "AddDkp"):Show();
                    getglobal("XyFrameListButton" .. i .. "MinusDkp"):Show();
                else
                    getglobal("XyFrameListButton" .. i .. "AddDkp"):Hide();
                    getglobal("XyFrameListButton" .. i .. "MinusDkp"):Hide();
                end
                getglobal("XyFrameListButton" .. i):Show();
            end
        end
    else
        for i = 1, 18 do getglobal("XyFrameListButton" .. i):Hide(); end
    end
end

function XyTracker_If(expr, a, b)
    return expr and a or b
end

-- Locale-independent replacement/companion for the "you come into a raid
-- group" / "you left this raid group" CHAT_MSG_SYSTEM checks further down:
-- those only match one client language, so on the "wrong" locale the old
-- SR list from last raid would silently stick around until the new leader
-- manually hit Start. RAID_ROSTER_UPDATE fires the same way on every
-- client, so we drive the actual clear/resync off the GetNumRaidMembers()
-- transition instead. This only touches local state and the existing
-- XY_SYNC_NEW / XY_SYNC addon-message protocol, so it stays fully
-- compatible with older client-side copies of this addon.
function XyTracker_OnRaidRosterUpdate()
    local nowInRaid = GetNumRaidMembers() > 0

    if WasInRaid and not nowInRaid then
        -- Just left the raid group
        IsLeader   = false
        LeaderName = ""
        XyTracker_UpdateLeaderText()
        EnableLeaderOperation()
        if XyTrackerOptions.autoClearOnLeave then
            if not StaticPopup_Visible("XYTRACKER_CONFIRM_RESET") then
                StaticPopup_Show("XYTRACKER_CONFIRM_RESET")
            end
        else
            XyTracker_DoActualClear()
        end
    elseif (not WasInRaid) and nowInRaid then
        -- Just joined a (new) raid group. Drop whatever the previous raid
        -- left behind and pull the authoritative list from the current
        -- leader instead of showing stale SR data until someone hits Start.
        XyTracker_DoActualClear()
        SendAddonMessage("XY_SYNC_NEW", "", "RAID")
    end

    WasInRaid = nowInRaid
    XyTracker_UpdateList()
end

function XyTracker_OnSlashCommand(msg)
    if XyTrackerFrame:IsVisible() then XyTracker_HideXyWindow()
    else XyTracker_ShowXyWindow() end
end

function XyTracker_ShowXyWindow()
    if DefaultDKP == nil then DefaultDKP = 4 end
    getglobal("autoModeButtons"):SetChecked(XyTrackerOptions.XyOnlyMode);
    getglobal("autoAnnounceButton"):SetChecked(XyTrackerOptions.AutoAnnounce);
    getglobal("autoMinButtons"):SetChecked(XyTrackerOptions.autoMinDkp);
    getglobal("greenModeButtons"):SetChecked(XyTrackerOptions.greenModeEnabled);
    getglobal("blueModeButtons"):SetChecked(XyTrackerOptions.blueModeEnabled);
    getglobal("purpleModeButtons"):SetChecked(XyTrackerOptions.purpleModeEnabled);
    getglobal("clearOnLeaveButton"):SetChecked(XyTrackerOptions.autoClearOnLeave);

    if not playerDeclaration or playerDeclaration == "" then
        playerDeclaration = XyTrackerDeclaration or ""
    end

    -- Show/hide declaration buttons based on leader status
    if IsLeader then
        getglobal("XyTrackerFrameDeclarationButton"):Show()
        getglobal("XyTrackerFrameAnnounceDeclarationButton"):Show()
    else
        getglobal("XyTrackerFrameDeclarationButton"):Hide()
        getglobal("XyTrackerFrameAnnounceDeclarationButton"):Hide()
    end

    XyTracker_UpdateLeaderText()
    ShowUIPanel(XyTrackerFrame)
end

function XyTracker_HideXyWindow()
    HideUIPanel(XyTrackerFrame)
end

function XyButton_UpdatePosition()
    XyButtonFrame:SetPoint("TOPLEFT", "Minimap", "TOPLEFT",
        54 - (78 * cos(200)), (78 * sin(200)) - 55);
end

-- Announce SR info when an item link appears in raid chat (outside SR phase)
-- [FIX] Previously used `return` inside this loop, which aborted the whole
-- function the moment ONE item in the message didn't qualify (wrong color,
-- or GetItemInfo not cached yet) -- silently dropping any later item link
-- in the same message, e.g. a leader pasting multiple drops at once. Now
-- each item link is evaluated independently so the rest still get announced.
function CheckItemAndAnnounceWish(msg, sender)
    if not XyTrackerOptions.AutoAnnounce then return end
    if string.find(msg, "%*%*") then return end
	if not IsLeader then return end

    for itemLink in string.gmatch(msg, "|Hitem:.-|h.-|h") do
        local _, _, targetID   = string.find(itemLink, "|Hitem:(%d+):")
        local _, _, targetName = string.find(itemLink, "|h%[(.-)%]|h")

        if targetID then
            -- Only announce for purple/orange (and optionally blue/green) items
            local itemName, itemRank, itemQuality = GetItemInfo(targetID)
            local shouldAnnounce = false
            if itemQuality == 5 then shouldAnnounce = true end  -- Orange (legendary): always announce
            if itemQuality == 4 and XyTrackerOptions.purpleModeEnabled then shouldAnnounce = true end
            if itemQuality == 3 and XyTrackerOptions.blueModeEnabled  then shouldAnnounce = true end
            if itemQuality == 2 and XyTrackerOptions.greenModeEnabled  then shouldAnnounce = true end

            if shouldAnnounce then
                local wishPlayers = {}

                for i = 1, getn(XyArray) do
                    local info = XyArray[i]
                    local xy   = info["xy"] or ""
                    if xy ~= "---NOSR---" and xy ~= "|cFF00FFFFAll SR Done|r" then
                        -- 用itemID匹配，不依赖名字
                        for srID in string.gmatch(xy, "|Hitem:(%d+):") do
                            if srID == targetID then
                                table.insert(wishPlayers, { name = info["name"], dkp = info["dkp"] })
                                break
                            end
                        end
                    end
                end

                if getn(wishPlayers) > 0 then
                    local msg2 = "*" .. (targetName or targetID) .. "* total " .. getn(wishPlayers) .. " SR: "
                    for idx = 1, getn(wishPlayers) do
                        local p = wishPlayers[idx]
                        msg2 = msg2 .. p.name .. " (" .. p.dkp .. "dkp)"
                        if idx < getn(wishPlayers) then msg2 = msg2 .. ", " end
                    end
                    SendChatMessage(msg2, "RAID", nil, nil)
                else
                    -- 无SR，播报提示
                    SendChatMessage("*" .. (targetName or targetID) .. "* no SR, open for bids (1-4) or /roll", "RAID", nil, nil)
                end
            end
        end
    end
end

-- Helper: deprecated, replaced by MarkItemAsCompleted
-- function RemoveItemFromXy(xyString, itemId, isComplete) ... end

function XyTracker_OnEvent(event)
    if event == "VARIABLES_LOADED" then
        -- Declaration edit box starts hidden
    end

    if isRolling and GetTime() > rollEndTime then RollEnd() end

    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        -- Track numeric bids (1-4) for auto-deduct
        local number = tonumber(arg1)
        if number and number >= 1 and number <= 4 then
            raidMessages[arg2] = { message = number, timestamp = GetTime() }
            -- Announce current DKP
            if IsLeader then
                local info = getXyInfo(arg2)
                if info then
                    local current = tonumber(info["dkp"]) or 0
                    SendChatMessage(arg2 .. " bids " .. number .. "dkp, current: [" .. current .. "]", "RAID", nil, nil)
                end
            end
        end
        XyTracker_OnSystemMessage()
    end

    -- Auto-deduct DKP when loot is received
    -- NOTE: The pattern below matches the Chinese locale loot message.
    -- Update if your server uses a different language.
    if event == "CHAT_MSG_LOOT" and XyTrackerOptions.autoMinDkp then
        local _, _, player, itemLink = string.find(arg1, "(.+) receives item: (.+)%.")
        if player and itemLink then
            local currentTime   = GetTime()
            local playerMessage = raidMessages[player]

            if playerMessage and (currentTime - playerMessage.timestamp) <= 60 then
                local _, _, itemColor = string.find(itemLink, "|c(%x+)|H")
                local shouldDeduct    = false

                if   itemColor == "ffa335ee" and XyTrackerOptions.purpleModeEnabled then shouldDeduct = true
                elseif itemColor == "ff0070dd" and XyTrackerOptions.blueModeEnabled  then shouldDeduct = true
                elseif itemColor == "ff1eff00" and XyTrackerOptions.greenModeEnabled  then shouldDeduct = true
                end

                if shouldDeduct and IsLeader then
                    local info   = getXyInfo(player)
                    local number = playerMessage.message

                    if info then
                        -- Deduct DKP based on bid number
                        if     number == 0 then -- No deduct, just remove item
                        elseif number == 5 then -- No deduct (SR fulfilled at cost)
                        elseif number <= 4 then
                            info["dkp"] = tonumber(info["dkp"]) - number
                            SendChatMessage(player .. " -" .. number .. "dkp, remaining: [" .. info["dkp"] .. "]", "RAID", this.language, nil)
                        else
                            local deduct = number - 5
                            info["dkp"]  = tonumber(info["dkp"]) - deduct
                            SendChatMessage(player .. " -" .. deduct .. "dkp (bid " .. number .. "dkp - 5dkp), remaining: [" .. info["dkp"] .. "]", "RAID", this.language, nil)
                        end

                        -- Remove obtained item from SR
                        if info["xy"] and info["xy"] ~= "---NOSR---" and info["xy"] ~= "|cFF00FFFFAll SR Done|r" then
                            local _, _, itemName = string.find(itemLink, "|h%[(.-)%]|h")
                            if not itemName then
                                _, _, itemName = string.find(itemLink, "%[(.-)%]")
                            end
                            if itemName and itemName ~= "" then
                                local oldXy = info["xy"]
                                info["xy"]  = MarkItemAsCompleted(oldXy, itemName)
                                if info["xy"] ~= oldXy then
                                    if info["xy"] == "|cFF00FFFFAll SR Done|r" then
                                        SendChatMessage(player .. " has completed all SR items", "RAID", this.language, nil)
                                    elseif string.find(info["xy"], "^|cFF00FFFFPartial SR Done|r") then
                                        local remaining = string.gsub(info["xy"], "^|cFF00FFFFPartial SR Done|r", "")
                                        SendChatMessage(player .. " received an SR item, remaining SR: " .. remaining, "RAID", this.language, nil)
                                    end
                                end
                            end
                        end

                        XyTracker_UpdateList()
                        syncXy()
                        raidMessages[player] = nil
                    end
                end
            end
        end
    end

    -- Announce SR when item links appear in raid chat
    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
        CheckItemAndAnnounceWish(arg1, arg2)
    end

    -- Whisper "cxxy" to look up your SR
    if event == "CHAT_MSG_WHISPER" and arg1 == "cxxy" then
        XyQuery(arg2)
    end

    -- SR started by leader: disable leader controls on members
    if event == "CHAT_MSG_ADDON" and arg1 == "XY_START" and not IsLeader then
        DisableLeaderOperation()
        LeaderName = arg4
        XyTracker_UpdateLeaderText()
    end

    -- Member requests sync: leader sends data
    if event == "CHAT_MSG_ADDON" and arg1 == "XY_SYNC_NEW" and IsLeader then
        syncXy()
    end

    -- Receive sync data from leader
    if event == "CHAT_MSG_ADDON" and arg1 == "XY_SYNC" and not IsLeader then
        receiveXySync(arg2, arg4)
    end

    -- Primary, locale-independent join/leave + refresh handling. Fires on
    -- any raid roster change; XyTracker_OnRaidRosterUpdate() only acts on
    -- the actual in-raid/out-of-raid edge, so mid-raid roster churn (people
    -- joining/leaving around you) doesn't re-trigger a clear.
    if event == "RAID_ROSTER_UPDATE" then
        XyTracker_OnRaidRosterUpdate()
    end

    -- Legacy locale-specific fallback (enUS wording only). Left in place in
    -- case RAID_ROSTER_UPDATE is ever unavailable, but WasInRaid guards
    -- XyTracker_OnRaidRosterUpdate() above so on a matching client both
    -- checks firing for the same transition is harmless.
    if event == "CHAT_MSG_SYSTEM" and arg1 == "you come into a raid group" then
        SendAddonMessage("XY_SYNC_NEW", "", "RAID")
    end

    if event == "CHAT_MSG_SYSTEM" and arg1 == "you left this raid group" then
        IsLeader   = false
        LeaderName = ""
        XyTracker_UpdateLeaderText()
        EnableLeaderOperation()
        if XyTrackerOptions.autoClearOnLeave then
            if not StaticPopup_Visible("XYTRACKER_CONFIRM_RESET") then
                StaticPopup_Show("XYTRACKER_CONFIRM_RESET")
            end
        else
            XyTracker_DoActualClear()
        end
    end

    -- Roll monitor: capture /roll results while rolling is active
    if event == "CHAT_MSG_SYSTEM" and isRolling and rollEndTime > GetTime() then
        local pattern = "(.+)rolled(%d+)（(%d+)-(%d+)）"
        if string.find(arg1, pattern) then
            local _, _, player, roll, min_roll, max_roll = string.find(arg1, pattern)
            if min_roll == "1" and max_roll == "100" then
                local exis = false
                for i = 1, getn(rollData) do
                    if rollData[i]["name"] == player then exis = true end
                end
                if not exis then
                    local xyInfo = getXyInfo(player)
                    table.insert(rollData, {
                        name  = player,
                        roll  = roll,
                        class = xyInfo["class"],
                        xy    = xyInfo["xy"],
                        dkp   = xyInfo["dkp"]
                    })
                    RollMonitor_UpdateList()
                end
            end
        end
    end
end

-- Parse raid messages and update SR data
function XyTracker_OnSystemMessage()
    if not XyInProgress then return end

    if arg1 and string.find(arg1, "|Hitem:") then
        local links = ""
        for link in string.gmatch(arg1, "|c%x+|Hitem:.-|h%[.-%]|h|r") do
            local _, _, itemID = string.find(link, "|Hitem:(%d+):")
            local _, _, itemQuality = GetItemInfo(itemID)
            if itemQuality and itemQuality >= 3 then
                links = links .. link
            end
        end
        if links ~= "" then
            XyTracker_OnXy(arg2, links)
            XyTracker_UpdateList()
            syncXy()
        end
    end
end

function receiveXySync(msg, sender)
    DisableLeaderOperation()
    LeaderName = sender or ""
    XyTracker_UpdateLeaderText()

    -- Sync header packet
    for n, x in string.gfind(msg, "n=(.+),x=(.+)") do
        Xys     = x
        XyArray = {}
        XyTracker_UpdateList()
        return
    end

    -- Player data packets
    for p, c, x, s in string.gfind(msg, "p=(.+),c=(.+),x=(.+),s=(.+)") do
        local found = false
        for i = 1, getn(XyArray) do
            if XyArray[i]["name"] == p then
                found             = true
                XyArray[i]["class"] = c
                XyArray[i]["xy"]    = (x == "---NOSR---") and "" or x
                XyArray[i]["dkp"]   = tonumber(s) or DefaultDKP  -- [FIX] Ensure number
                break
            end
        end
        if not found then
            table.insert(XyArray, {
                name  = p,
                class = c,
                xy    = (x == "---NOSR---") and "" or x,
                dkp   = tonumber(s) or DefaultDKP  -- [FIX] Ensure number
            })
        end
        XyTracker_UpdateList()
    end
end

function syncXy()
    local n = getn(XyArray)
    if n > 0 then
        SendAddonMessage("XY_SYNC", "n=" .. n .. ",x=" .. Xys, "RAID")
        for i = 1, n do
            local info  = XyArray[i]
            local xy    = info["xy"]    or "---NOSR---"
            local dkp   = info["dkp"]   or 4
            local class = info["class"] or "none"
            SendAddonMessage("XY_SYNC", "p=" .. info["name"] .. ",c=" .. class .. ",x=" .. xy .. ",s=" .. dkp, "RAID")
        end
    end
end

function DisableLeaderOperation()
    -- Must be kept: prevents members who were leaders before joining from retaining access
    XyInProgress = false
    getglobal("XyTrackerFrameStartButton"):Hide();
    getglobal("XyTrackerFrameStopButton"):Hide();
    getglobal("XyTrackerFrameResetButton"):Hide();
    -- NOSR count and export buttons remain visible for members
    getglobal("XyTrackerFrameChuShiHua_DKP"):Hide();
    getglobal("XyTrackerFrameDeclarationButton"):Hide();
    getglobal("XyTrackerFrameAnnounceDeclarationButton"):Hide();
    getglobal("XyTrackerDeclarationLargeEditBox"):Hide();
end

function EnableLeaderOperation()
    XyInProgress = false
    getglobal("XyTrackerFrameStartButton"):Show();
    getglobal("XyTrackerFrameResetButton"):Show();
    getglobal("XyTrackerFrameAnnounceButton"):Show();
    getglobal("XyTrackerFrameExportButton"):Show();
    getglobal("XyTrackerFrameChuShiHua_DKP"):Show();
    getglobal("XyTrackerFrameDeclarationButton"):Show();
    getglobal("XyTrackerFrameAnnounceDeclarationButton"):Show();
end

function XyQuery(player, dkpnumber)
    for i = 1, getn(XyArray) do
        local name = XyArray[i]["name"]
        if player == name then
            local xy         = XyArray[i]["xy"] or ""
            local currentDKP = XyArray[i]["dkp"]
            if dkpnumber and dkpnumber ~= 0 then
                if dkpnumber > 0 then
                    SendChatMessage(player .. " +[" .. dkpnumber .. "]dkp, remaining: [" .. currentDKP .. "]", "RAID", this.language, nil);
                else
                    SendChatMessage(player .. " -[" .. (0 - dkpnumber) .. "]dkp, remaining: [" .. currentDKP .. "]", "RAID", this.language, nil);
                end
            else
                SendChatMessage(player .. " SR: [" .. xy .. "], remaining dkp: [" .. currentDKP .. "]", "RAID", this.language, nil);
            end
            break
        end
    end
end

function XyTracker_OnXy(name, Xy)
    local info = getXyInfo(name)
    info["xy"] = Xy

    if IsLeader then XyTracker_ShowXyWindow() end

    -- Alert if multiple players SR the same item
    if XyTrackerOptions.AutoAnnounce then
        for itemName in string.gmatch(Xy, "|h%[(.-)%]|h") do
            local count = 0
            for i = 1, getn(XyArray) do
                for otherItem in string.gmatch(XyArray[i]["xy"] or "", "|h%[(.-)%]|h") do
                    if otherItem == itemName then count = count + 1; break end
                end
            end
            if count >= 2 then
                SendChatMessage("*" .. itemName .. "* already has " .. count .. " ppl SR", "RAID", this.language, nil)
            end
        end
    end
end

function XyTracker_OnStartButtonClick()
    if GetNumRaidMembers() > 1 then
        IsLeader   = true
        LeaderName = UnitName("player")
        XyTracker_UpdateLeaderText()
        SendChatMessage("Welcome to the raid! Say [itemlink] in raid chat to submit your SR", "RAID", this.language, nil);
        XyInProgress = true
        XyTracker_ShowXyWindow()
        SendAddonMessage("XY_START", "", "RAID")  -- Notify members SR has started
    end
end

function XyTracker_OnStopButtonClick()
    SendChatMessage("SR phase ended. SR is now locked.", "RAID", this.language, nil)
    XyInProgress = false
end

function XyTracker_OnClearButtonClick()
    StaticPopup_Show("XYTRACKER_CONFIRM_RESET")
end

-- Reset confirmation popup
StaticPopupDialogs["XYTRACKER_CONFIRM_RESET"] = {
    text      = "Reset all member SR data?",
    button1   = "OK",
    button2   = "Cancel",
    OnAccept  = function() XyTracker_DoActualClear() end,
    timeout   = 0,
    whileDead = true,
    hideOnEscape = true
}

function XyTracker_DoActualClear()
    XyArray    = {}
    XyItemCount = {}  -- Clear SR item counts
    local totalMembers = GetNumRaidMembers()
    if totalMembers then
        for i = 1, totalMembers do
            local name, rank, subgroup, level, class, fileName = GetRaidRosterInfo(i);
            info = { name = name, class = fileName or class, dkp = 4, xy = "---NOSR---" }
            table.insert(XyArray, info)
            NoXyList = NoXyList .. name .. " "
        end
    end
    XyTracker_UpdateList()
    if IsLeader then syncXy() end
end

function XyTracker_OnRefreshButtonClick()
    local totalMembers = GetNumRaidMembers()
    if totalMembers then
        -- Index existing data by player name
        local existingWishes = {}
        for i = 1, getn(XyArray) do
            local info = XyArray[i]
            existingWishes[info["name"]] = { index = i, xy = info["xy"], dkp = info["dkp"] or DefaultDKP, class = info["class"] }
        end

        -- Ensure all current raid members have a record
        for i = 1, totalMembers do
            local name, rank, subgroup, level, class, fileName = GetRaidRosterInfo(i)
            local classToken = fileName or class
            if existingWishes[name] then
                XyArray[existingWishes[name].index]["class"] = classToken  -- Update class
            else
                table.insert(XyArray, { name = name, class = classToken, xy = "---NOSR---", dkp = DefaultDKP or 4 })
            end
        end

        if IsLeader then syncXy() end
    end
    XyTracker_UpdateList()
end

function XyTracker_OnAnnounceButtonClick()
if not IsLeader then return end
    if NoXyList == "" then
        SendChatMessage("Everyone has submitted their SR!", "RAID", this.language, nil);
    else
        SendChatMessage("The following players have NOT submitted SR, please do so ASAP: " .. NoXyList, "RAID", this.language, nil);
    end
end

-- Broadcast timer for reading out the full SR list
XyBroadcastTimer        = nil
XyCurrentBroadcastIndex = 0
XyBroadcastList         = {}

function XyTracker_OnBroadcastWishesButtonClick()
if not IsLeader then return end
    if XyBroadcastTimer then XyBroadcastTimer:Cancel(); XyBroadcastTimer = nil; end

    local currentLanguage    = this.language
    local totalMembers       = GetNumRaidMembers()
    local currentRaidMembers = {}

    if totalMembers then
        for i = 1, totalMembers do currentRaidMembers[GetRaidRosterInfo(i)] = true end

        XyBroadcastList = {}
        for i = 1, getn(XyArray) do
            if currentRaidMembers[XyArray[i]["name"]] then
                table.insert(XyBroadcastList, XyArray[i])
            end
        end

        XyCurrentBroadcastIndex = 1

        -- Describe sort order
        local sortText = Xy_SortOptions.method ~= "" and Xy_SortOptions.method or "name"
        sortText = sortText .. (Xy_SortOptions.itemway == "desc" and " (desc)" or " (asc)")
        SendChatMessage("Sorted by |cffff0000" .. sortText .. "|r - SR report:", "RAID", currentLanguage, nil);

        -- Send one message every 0.5 seconds
        XyBroadcastTimer = CreateFrame("Frame");
        XyBroadcastTimer.elapsed = 0;
        XyBroadcastTimer:SetScript("OnUpdate", function()
            this.elapsed = this.elapsed + arg1;
            if this.elapsed >= 0.5 then
                this.elapsed = 0;
                if XyCurrentBroadcastIndex <= getn(XyBroadcastList) then
                    local info = XyBroadcastList[XyCurrentBroadcastIndex]
                    if info and info["xy"] and info["xy"] ~= "---NOSR---" then
                        SendChatMessage(string.format("*SR* %s (%s): %s [%sdkp]",
                            info["name"], ClassDisplayName(info["class"]), info["xy"], info["dkp"]),
                            "RAID", currentLanguage, nil);
                    end
                    XyCurrentBroadcastIndex = XyCurrentBroadcastIndex + 1;
                else
                    SendChatMessage("SR report complete.", "RAID", currentLanguage, nil);
                    this:Cancel();
                end
            end
        end);
        XyBroadcastTimer.Cancel = function(self)
            self:SetScript("OnUpdate", nil); XyBroadcastTimer = nil;
        end;
    else
        SendChatMessage("You must be in a raid group.", "RAID", currentLanguage, nil);
    end
end

function XyTracker_OnExportButtonClick()
    local totalMembers       = GetNumRaidMembers()
    local currentRaidMembers = {}
    local displayArray       = {}

    if totalMembers then
        for i = 1, totalMembers do currentRaidMembers[GetRaidRosterInfo(i)] = true end
        for i = 1, getn(XyArray) do
            if currentRaidMembers[XyArray[i]["name"]] then
                table.insert(displayArray, XyArray[i])
            end
        end
    end
    if getn(displayArray) == 0 then displayArray = XyArray end

    local csvText = ""
    for i = 1, getn(displayArray) do
        local xy = displayArray[i]["xy"] or ""
        csvText = csvText .. ClassDisplayName(displayArray[i]["class"]) .. "-" .. displayArray[i]["name"] .. "-" .. xy .. "-remaining:[" .. displayArray[i]["dkp"] .. "]dkp\n"
    end

    getglobal("XyExportEdit"):SetText(csvText);
    getglobal("XyExportFrame"):Show();
end

function Xy_FixZero(num)
    return (num < 10) and ("0" .. num) or num
end

function Xy_Date()
    local t = date("*t");
    return strsub(t.year,3) .. "-" .. Xy_FixZero(t.month) .. "-" .. Xy_FixZero(t.day) .. " " ..
           Xy_FixZero(t.hour) .. ":" .. Xy_FixZero(t.min) .. ":" .. Xy_FixZero(t.sec);
end

function XyAddDkp(player, score)
    if not player or not score then return end
    local info = getXyInfo(player)
    if info then
        info["dkp"] = tonumber(info["dkp"]) + score
        XyTracker_UpdateList(); XyQuery(player, score); syncXy()
    end
end

function XyMinusDkp(player, score)
    if not player or not score then return end
    local info = getXyInfo(player)
    if info then
        info["dkp"] = tonumber(info["dkp"]) - score
        XyTracker_UpdateList(); XyQuery(player, -score); syncXy()
    end
end

function XySortOptions(method)
    if Xy_SortOptions.method == method then
        Xy_SortOptions.itemway = (Xy_SortOptions.itemway == "asc") and "desc" or "asc"
    else
        Xy_SortOptions.method  = method
        Xy_SortOptions.itemway = "asc"
    end
    Xy_SortDkp(); XyTracker_UpdateList();
end

function Xy_SortDkp()
    table.sort(XyArray, Xy_CompareDkps);
end

function Xy_CompareDkps(a1, a2)
    local method = Xy_SortOptions["method"]
    local way    = Xy_SortOptions["itemway"]
    local c1, c2 = a1[method], a2[method]
    if method == "dkp" then  -- [FIX] Ensure numeric comparison
        c1 = tonumber(c1) or 0
        c2 = tonumber(c2) or 0
    end
    return (way == "asc") and (c1 < c2) or (c1 > c2)
end

function ExtractItemName(xy)
    if string.find(xy, "|Hitem:") then
        local _, _, name = string.find(xy, "|h%[(.-)%]|h")
        return name or xy
    end
    return xy
end

-- Show a real item tooltip when hovering a row's SR column, instead of the
-- plain colored item-name text. Reads the full raw link straight back off
-- the FontString (SetText/GetText round-trips it unchanged, escape codes
-- and all), so no separate storage is needed.
--
-- When ClassicAPI is installed, GameTooltip:SetItemByID + C_Item's cache
-- check/request avoid the "Retrieving item information" placeholder for
-- items the client hasn't seen yet; without ClassicAPI this degrades to
-- the plain vanilla GameTooltip:SetHyperlink path, so it still works on a
-- client running none of the referenced mods.
function XyTracker_RowOnEnter(self)
    local id     = self:GetID()
    local xyText = getglobal("XyFrameListButton" .. id .. "Xy")
    local xy     = xyText and xyText:GetText()
    if not xy or xy == "" or xy == "---NOSR---" then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    local shownFirst = false
    for hyperlink, itemName in string.gmatch(xy, "|H(item:[%-%d:]+)|h%[(.-)%]|h") do
        if not shownFirst then
            local _, _, itemID = string.find(hyperlink, "^item:(%d+)")
            itemID = tonumber(itemID)

            if itemID and C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
                C_Item.RequestLoadItemDataByID(itemID)  -- warms the cache for next hover; this pass may still show name-only
            end

            if itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(itemID)
            else
                GameTooltip:SetHyperlink(hyperlink)
            end
            shownFirst = true
        else
            -- Tooltip can only show full stats for one item; list any
            -- additional SR'd items by name underneath it.
            GameTooltip:AddLine(itemName, 1, 1, 1)
        end
    end

    if shownFirst then GameTooltip:Show() end
end

-- Return SR list string for an item, matched by itemID rather than display
-- name. Name-based matching (XYLIST1 below) can't tell apart two items that
-- happen to share a name (recolors, different-tier items with the same
-- title, enchanted/suffixed variants) -- itemID can't collide that way.
-- Used when the tooltip hooks below can get a real itemID (ClassicAPI's
-- GameTooltip:GetItem()); falls back to XYLIST1(name) when they can't.
function XYLIST1byID(itemID)
    if XyArray == nil or not itemID then return nil end
    itemID = tostring(itemID)
    local num = 0; local p = 0; local itemname = ""; local NOW
    for i = 1, getn(XyArray) do
        local info = XyArray[i]
        local xy   = info["xy"] or ""
        for srID, item_name in string.gmatch(xy, "|Hitem:(%d+):.-|h%[(.-)%]|h") do
            if srID == itemID then
                num = num + 1
                local color = ClasstoColor(info["class"])
                if p == 3 then
                    itemname = itemname .. "\n " .. color .. info["name"] .. "|r(" .. info["dkp"] .. "dkp)"
                    p = 0
                else
                    itemname = itemname .. " " .. color .. info["name"] .. "|r(" .. info["dkp"] .. "dkp)"
                end
                p = p + 1; NOW = item_name
            end
        end
    end
    if itemname ~= "" and NOW then
        return "\n SR: " .. itemname .. "|cff9FFFA0\n  --total (" .. num .. ") ppl SR--\n|r"
    end
    return nil
end

-- AtlasLoot tooltip: show SR players when hovering items
if AtlasLootTooltip then
    Xytooltip = CreateFrame("Frame", "Xytooltip", AtlasLootTooltip)
    Xytooltip:SetScript("OnShow", function(self)
        local namelist
        if AtlasLootTooltip.GetItem then  -- ClassicAPI extension: real itemID, no name collisions
            local _, _, itemID = AtlasLootTooltip:GetItem()
            namelist = itemID and XYLIST1byID(itemID)
        end
        if not namelist then
            local Itemname = getglobal("AtlasLootTooltipTextLeft1"):GetText()
            namelist = Itemname and XYLIST1(Itemname)
        end
        if namelist then AtlasLootTooltip:AddLine(namelist) end
        AtlasLootTooltip:Show()
    end)
    Xytooltip:SetScript("OnHide", function() AtlasLootTooltip:Hide() end)
end

-- GameTooltip: show SR players when hovering items in world
if GameTooltip then
    Xytooltip2 = CreateFrame("Frame", "Xytooltip2", GameTooltip)
    Xytooltip2:SetScript("OnShow", function(self)
        local namelist
        if GameTooltip.GetItem then  -- ClassicAPI extension: real itemID, no name collisions
            local _, _, itemID = GameTooltip:GetItem()
            namelist = itemID and XYLIST1byID(itemID)
        end
        if not namelist then
            local Itemname = getglobal("GameTooltipTextLeft1"):GetText() or ""
            -- Try as item name, then as player name
            namelist = Itemname and (XYLIST1(Itemname) or XYLISTbyPlayer(Itemname))
        end
        if namelist then GameTooltip:AddLine(namelist) end
        GameTooltip:Show()
    end)
    Xytooltip2:SetScript("OnHide", function() GameTooltip:Hide() end)
end

-- ItemRefTooltip: show SR players when clicking item links in chat
if ItemRefTooltip then
    Xytooltip3 = CreateFrame("Frame", "Xytooltip3", ItemRefTooltip)
    Xytooltip3:SetScript("OnShow", function(self)
        local namelist
        if ItemRefTooltip.GetItem then  -- ClassicAPI extension: real itemID, no name collisions
            local _, _, itemID = ItemRefTooltip:GetItem()
            namelist = itemID and XYLIST1byID(itemID)
        end
        if not namelist then
            local Itemname = getglobal("ItemRefTooltipTextLeft1"):GetText()
            namelist = Itemname and XYLIST1(Itemname)
        end
        if namelist then ItemRefTooltip:AddLine(namelist) end
        ItemRefTooltip:Show()
    end)
    Xytooltip3:SetScript("OnHide", function() ItemRefTooltip:Hide() end)
end

-- Returns a WoW color code for the given class name.
-- [FIX] Added else fallback to prevent nil concatenation crash when class is unknown.
-- [FIX] class is now stored as GetRaidRosterInfo's locale-independent token
-- (e.g. "HUNTER", uppercase) rather than the localized display name, so
-- lowercase it before matching -- this still also matches old saved data
-- that has the class stored lowercase from before that change.
function ClasstoColor(class)
    class = class and string.lower(class) or ""
    if     class == 'warrior' then return "|cffC79C6E"
    elseif class == 'shaman'  then return "|cff2773FF"
    elseif class == 'druid'   then return "|cffFF7D0A"
    elseif class == 'rogue'   then return "|cffFFF569"
    elseif class == 'mage'    then return "|cff69CCFF"
    elseif class == 'paladin' then return "|cffF58CBA"
    elseif class == 'priest'  then return "|cffFFFFFF"
    elseif class == 'warlock' then return "|cff9482C9"
    elseif class == 'hunter'  then return "|cffABD473"
    else                           return "|cffFFFFFF"  -- Default white (handles unknown/non-English class names)
    end
end

-- Maps GetRaidRosterInfo's locale-independent class token to a readable
-- English name for the Class column / export / broadcast text. Falls back
-- to returning whatever was passed in unchanged, so old saved data (or a
-- sync packet from someone still on a previous addon version) doesn't
-- break -- it just won't be prettified until it self-heals (see
-- XyTracker_UpdateList, which refreshes every current member's class
-- token from the local client on each update).
local CLASS_TOKEN_TO_DISPLAY = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE   = "Rogue",   PRIEST  = "Priest",   SHAMAN = "Shaman",
    MAGE    = "Mage",    WARLOCK = "Warlock",  DRUID  = "Druid",
}
function ClassDisplayName(class)
    if not class or class == "" then return "" end
    return CLASS_TOKEN_TO_DISPLAY[string.upper(class)] or class
end

-- Return SR list string for an item (single-item SR per player)
function XYLIST(Iname)
    if XyArray == nil then return nil end
    local num = 0; local itemname = ""; local NOW
    for i = 1, getn(XyArray) do
        local name = XyArray[i]["name"]
        local xy   = XyArray[i]["xy"] or ""
        local _, _, xy_name = string.find(xy, "|h%[(.-)%]|h|r")
        if xy_name and xy_name == Iname then
            local color = ClasstoColor(XyArray[i]["class"])
            itemname = itemname .. " " .. color .. name .. "|r(" .. XyArray[i]["dkp"] .. "dkp)"
            NOW = xy_name; num = num + 1
        end
    end
    if itemname ~= "" and NOW then
        return "[" .. NOW .. "]" .. "|cffFFFF00(" .. num .. ")|r ppl sr:" .. itemname
    end
    return nil
end

-- Return SR list string for an item (multi-item SR per player)
function XYLIST1(Iname)
    if XyArray == nil then return nil end
    local num = 0; local p = 0; local itemname = ""; local NOW
    for i = 1, getn(XyArray) do
        local info = XyArray[i]
        local xy   = info["xy"] or ""
        for item_name in string.gmatch(xy, "|h%[(.-)%]|h") do
            if item_name == Iname then
                num = num + 1
                local color = ClasstoColor(info["class"])
                if p == 3 then
                    itemname = itemname .. "\n " .. color .. info["name"] .. "|r(" .. info["dkp"] .. "dkp)"
                    p = 0
                else
                    itemname = itemname .. " " .. color .. info["name"] .. "|r(" .. info["dkp"] .. "dkp)"
                end
                p = p + 1; NOW = item_name
            end
        end
    end
    if itemname ~= "" and NOW then
        return "\n SR: " .. itemname .. "|cff9FFFA0\n  --total (" .. num .. ") ppl SR--\n|r"
    end
    return nil
end

-- Return SR info string for a player by name (tooltip)
local playername
function XYLISTbyPlayer(playername)
    if XyArray == nil then return nil end
    local n = getn(XyArray)
    local num = 0; local NOW; local dkp; local playxy
    local itemtable = {}

    local _, _, extracted = string.find(playername, " (%S+)")
    playername = extracted or playername

    for i = 1, n do
        if XyArray[i]["name"] == playername then
            local _, _, extracted2 = string.find(XyArray[i]["xy"], "|h%[(.-)%]|h")
            playxy = extracted2 or XyArray[i]["xy"]
            NOW    = XyArray[i]["xy"]
            dkp    = XyArray[i]["dkp"]
            break
        end
    end

    for i = 1, n do
        local xy     = XyArray[i]["xy"] or ""
        local _, _, xy_name = string.find(xy, "|h%[(.-)%]|h|r")
        xy_name = xy_name or xy
        if xy_name then
            if xy_name == playxy then
                num = num + 1
            end
            itemtable[xy_name] = (itemtable[xy_name] or 0) + 1
        end
    end

    if NOW and NOW ~= "" then
        return " SR: " .. NOW .. " (" .. dkp .. "dkp)\n   |cff9FFFA0--(" .. num .. ") ppl SR--|r"
    end
    return nil
end

-- Update the SR manager name display at the bottom of the frame
function XyTracker_UpdateLeaderText()
    local leaderText = getglobal("XyTrackerFrameLeaderName")
    if leaderText then
        if LeaderName and LeaderName ~= "" then
            leaderText:SetText("Manager: " .. LeaderName)
            leaderText:Show()
        else
            leaderText:SetText("")
            leaderText:Hide()
        end
    end
end
