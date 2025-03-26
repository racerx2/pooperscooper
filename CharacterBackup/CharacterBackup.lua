CharacterBackupData = CharacterBackupData or {}
CharacterBackupJSON = CharacterBackupJSON or ""

if not dkjson then
    print("Error: dkjson not found! Please ensure dkjson.lua is loaded properly.")
    return
end
local json = dkjson

local function TableToJSON(tbl)
    local jsonString, pos, err = json.encode(tbl, { indent = true })
    if err then
        print("JSON Encode Error: " .. err)
        return ""
    end
    return jsonString
end

local function GetGuildData()
    local guildName, guildRankName = GetGuildInfo("player")
    return {
        name = guildName or "None",
        rank = guildRankName or "None"
    }
end

local function GetEquippedData()
    local equipped = {}
    for slot = 1, 19 do
        local itemLink = GetInventoryItemLink("player", slot)
        equipped[slot] = itemLink or ""
    end
    return equipped
end

local function GetBagItems()
    local bags = {}
    for bag = 0, 4 do
        bags[bag] = {}
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local _, itemCount = GetContainerItemInfo(bag, slot)
                table.insert(bags[bag], { item = itemLink, count = itemCount or 1 })
            end
        end
    end
    return bags
end

local function GetSkillData()
    local skills = {}
    for i = 1, GetNumSkillLines() do
        local skillName, _, _, skillRank = GetSkillLineInfo(i)
        skills[skillName] = skillRank or 0
    end
    return skills
end

local function GetMoneyData()
    local totalCopper = GetMoney()
    return {
        gold = math.floor(totalCopper / 10000),
        silver = math.floor((totalCopper % 10000) / 100),
        copper = totalCopper % 100
    }
end

-- Load the spell ID lookup table (ensure SpellIDs is defined somewhere)
local SpellIDLookup = SpellIDLookup or {}

local function GetLearnedSkills()
    local learnedSkills = {}
    for i = 1, MAX_SKILLLINE_TABS do
        local tabName, _, offset, numSpells = GetSpellTabInfo(i)
        if not tabName then break end
        for j = 1, numSpells do
            local spellIndex = offset + j
            local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)

            -- Lookup the correct spell ID from SpellIDLookup table
            local spellID = SpellIDLookup[spellName] or 0  

            learnedSkills[spellName] = { rank = spellRank or "Passive", spellID = spellID }
        end
    end
    return learnedSkills
end


local function GetMountData()
    local mounts = {}
    for i = 1, GetNumCompanions("MOUNT") do
        local creatureID, creatureName, creatureSpellID, icon = GetCompanionInfo("MOUNT", i)
        table.insert(mounts, { id = creatureID, name = creatureName, spellID = creatureSpellID, icon = icon })
    end
    return mounts
end

local function GetPetData()
    local pets = {}
    for i = 1, GetNumCompanions("CRITTER") do
        local creatureID, creatureName, creatureSpellID, icon = GetCompanionInfo("CRITTER", i)
        table.insert(pets, { id = creatureID, name = creatureName, spellID = creatureSpellID, icon = icon })
    end
    return pets
end

local function GetTalentData()
    local talents = {}
    for tabIndex = 1, GetNumTalentTabs() do
        local tabName, tabIcon, tabPointsSpent = GetTalentTabInfo(tabIndex)
        local tabInfo = { name = tabName, icon = tabIcon, pointsSpent = tabPointsSpent, talents = {} }
        for talentIndex = 1, GetNumTalents(tabIndex) do
            local name, icon, tier, column, currentRank, maxRank = GetTalentInfo(tabIndex, talentIndex)
            tabInfo.talents[name] = { icon = icon, tier = tier, column = column, rank = currentRank, max = maxRank }
        end
        talents[tabIndex] = tabInfo
    end
    return talents
end

local function GetAchievementData()
    local achievements = {}
    for achID = 1, 6000 do
        local name, _, points, completed, month, day, year, _, icon, rewardText = GetAchievementInfo(achID)
        if name then
            achievements[achID] = {
                name = name,
                points = points,
                completed = completed,
                date = completed and string.format("%02d/%02d/%d", month, day, year) or nil,
                icon = icon,
                rewardText = rewardText
            }
        end
    end
    return achievements
end

local function GetReputationData()
    local reputations = {}
    for i = 1, GetNumFactions() do
        local name, _, standingID, bottomValue, topValue, earnedValue, _, _, isHeader = GetFactionInfo(i)
        if name and not isHeader then
            reputations[name] = { standingID = standingID, current = earnedValue, minimum = bottomValue, maximum = topValue }
        end
    end
    return reputations
end

local function ShouldStoreQuest(title, isHeader, questIDTitle, questIDLink)
    if not title or title == "" then return false end
    if (questIDLink and questIDLink > 0) or (questIDTitle and questIDTitle > 0) then
        return true
    end
    return not isHeader
end

local function GetInProgressQuests()
    local inProgressQuests = {}
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, _, _, _, questIDTitle = GetQuestLogTitle(i)
        local questLink = GetQuestLink(i)
        local questIDLink = questLink and tonumber(string.match(questLink, "quest:(%d+):"))
        if ShouldStoreQuest(title, isHeader, questIDTitle, questIDLink) then
            local usedID
            if questIDTitle and questIDTitle > 0 then
                usedID = questIDTitle
            elseif questIDLink and questIDLink > 0 then
                usedID = questIDLink
            else
                usedID = "UnknownID_" .. i
            end
            inProgressQuests[usedID] = title
        end
    end
    return inProgressQuests
end

local function GetGlyphData()
    local glyphs = {}
    for i = 1, 6 do
        local enabled, glyphType, glyphSpellID, icon = GetGlyphSocketInfo(i)
        glyphs[i] = {
            enabled     = enabled,
            glyphType   = glyphType, -- "major"/"minor"
            glyphSpellID= glyphSpellID,
            icon        = icon,
        }
    end
    return glyphs
end

-- Guild Vault Data Function (collects each tab's data and overall vault money)
local function GetGuildVaultData()
    local vault = {}
    if IsInGuild() then
        local numTabs = GetNumGuildBankTabs() or 0
        vault.tabs = {}
        vault.items = {}
        for tab = 1, numTabs do
            local tabName, iconTexture, isViewable, numSlots, isPurchasable, canDeposit, iconFilename, tabMoney = GetGuildBankTabInfo(tab)
            
            -- Add nil checks for numSlots
            numSlots = numSlots or 0
            
            -- Force the slot count to 98 (7 rows × 14 columns) if lower
            if numSlots < 98 then numSlots = 98 end
            
            vault.tabs[tab] = {
                name = tabName or ("Tab" .. tab),
                icon = iconTexture or "",
                canDeposit = canDeposit or 0,
                canView = isViewable or 0,
                numSlots = numSlots,
                money = tabMoney or 0
            }
            
            vault.items[tab] = {}
            for slot = 1, numSlots do
                local itemLink = GetGuildBankItemLink(tab, slot)
                if itemLink then
                    local texture, count, locked = GetGuildBankItemInfo(tab, slot)
                    vault.items[tab][slot] = { item = itemLink, count = count or 1, locked = locked }
                else
                    vault.items[tab][slot] = nil
                end
            end
        end
        vault.money = GetGuildBankMoney() or 0
    end
    return vault
end

-- Character Bank Inventory Function (captures main bank and bank bags)
local function GetBankItems()
    local bankItems = {}
    -- Main bank container is bag -1
    bankItems[-1] = {}
    for slot = 1, GetContainerNumSlots(-1) do
        local itemLink = GetContainerItemLink(-1, slot)
        if itemLink then
            local _, itemCount = GetContainerItemInfo(-1, slot)
            table.insert(bankItems[-1], { item = itemLink, count = itemCount or 1 })
        end
    end
    -- Additional bank bags (there are 7 bank bag slots, typically indices 5 to 11)
    for bag = 5, 11 do
        bankItems[bag] = {}
        local numSlots = GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    local _, itemCount = GetContainerItemInfo(bag, slot)
                    table.insert(bankItems[bag], { item = itemLink, count = itemCount or 1 })
                end
            end
        end
    end
    return bankItems
end

-- Persistent storage for GPS data - must be global to persist between function calls
local capturedGPS = {
    hasData = false,
    x = 0,
    y = 0,
    z = 0,
    facing = 0,
    mapID = 0,
    zone = "",
    subZone = ""
}

-- Create a frame to listen for GPS data globally
local gpsListener = CreateFrame("Frame")
gpsListener:RegisterEvent("CHAT_MSG_SYSTEM")
gpsListener:SetScript("OnEvent", function(self, event, msg)
    if event == "CHAT_MSG_SYSTEM" and (string.find(msg, "X:") or string.find(msg, "Map:")) then
        print("CharacterBackup: GPS message detected")
        
        -- Search for the line that contains Zone information
        -- The format appears like: "Map: 1 (Kalimdor) Zone: 405 (Desolace) Area: 608..."
        if string.find(msg, "Zone:") then
            -- Try to extract using strict pattern matching for this specific format
            local mapID, zoneLine = string.match(msg, "Map:%s*(%d+)%s*%(.-%)%s*Zone:%s*(%d+)")
            
            if not zoneLine and string.find(msg, "Zone:") then
                -- Direct extract - looking at the full message
                zoneLine = string.match(msg, "Zone:%s*(%d+)")
            end
            
            if zoneLine then
                print("CharacterBackup Debug: Direct zone extraction found: " .. zoneLine)
                capturedGPS.zone = tonumber(zoneLine)
            end
        end
        
        -- Extract direct coordinates
        local x = string.match(msg, "X:%s*([%d%.%-]+)")
        local y = string.match(msg, "Y:%s*([%d%.%-]+)")
        local z = string.match(msg, "Z:%s*([%d%.%-]+)")
        local o = string.match(msg, "Orientation:%s*([%d%.%-]+)")
        local mapID = string.match(msg, "Map:%s*(%d+)")
        
        if x and y and z then
            print("CharacterBackup: Found coordinates - X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
            
            -- Store in our global table
            capturedGPS.hasData = true
            capturedGPS.x = tonumber(x)
            capturedGPS.y = tonumber(y)
            capturedGPS.z = tonumber(z)
            capturedGPS.facing = tonumber(o or GetPlayerFacing() or 0)
            capturedGPS.mapID = tonumber(mapID or 1)
            
            -- If we didn't get zone from the special message pattern above, try alternate methods
            if not capturedGPS.zone or capturedGPS.zone == 0 then
                -- Try different pattern that might appear in your specific server's GPS response
                local zoneID = string.match(msg, "Zone:%s*(%d+)") or
                               string.match(msg, "Zone:%s*(%d+)%s*%(") or 
                               string.match(msg, "ZoneY:%s*(%d+)")
                
                if zoneID then
                    capturedGPS.zone = tonumber(zoneID)
                    print("CharacterBackup Debug: Successfully extracted Zone ID: " .. zoneID)
                else
                    -- If we still don't have a zone, check for a specific text pattern in your screenshot
                    local zoneTextMatch = string.match(msg, "Zone:%s*%d+%s*%(([^)]+)%)")
                    if zoneTextMatch and zoneTextMatch == "Desolace" then
                        capturedGPS.zone = 405
                        print("CharacterBackup Debug: Extracted zone=405 from zone name Desolace")
                    else
                        local currentMapZone = GetCurrentMapZone() or 0
                        capturedGPS.zone = currentMapZone
                        print("CharacterBackup Debug: Zone ID not found in message, using current zone: " .. currentMapZone)
                    end
                end
            end
            
            capturedGPS.zoneName = GetZoneText() or "Unknown"
            capturedGPS.subZone = GetSubZoneText() or "Unknown"
            
            -- Now update CharacterBackupData 
            CharacterBackupData.location = {
                x = capturedGPS.x,
                y = capturedGPS.y,
                z = capturedGPS.z,
                facing = capturedGPS.facing,
                mapID = capturedGPS.mapID,
                -- Store zone ID as "zone" (for database compatibility)
                zone = capturedGPS.zone, 
                -- Store zone name separately
                zoneName = capturedGPS.zoneName,
                subZone = capturedGPS.subZone
            }
            
            -- Immediately update the JSON string
            CharacterBackupJSON = TableToJSON(CharacterBackupData)
            
            print("CharacterBackup: GPS coordinates saved directly to CharacterBackupData")
            print("X: " .. capturedGPS.x .. ", Y: " .. capturedGPS.y .. ", Z: " .. capturedGPS.z)
            print("Map ID: " .. capturedGPS.mapID .. ", Zone ID: " .. capturedGPS.zone)
            
            -- Use frame timer for forced update
            local forceSaveFrame = CreateFrame("Frame")
            local timePassed = 0
            forceSaveFrame:SetScript("OnUpdate", function(self, elapsed)
                timePassed = timePassed + elapsed
                if timePassed > 0.5 then
                    -- Force variables update
                    CharacterBackupData.tmp = time()
                    
                    -- Cleanup timer
                    local cleanupFrame = CreateFrame("Frame")
                    local cleanupTime = 0
                    cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
                        cleanupTime = cleanupTime + elapsed
                        if cleanupTime > 0.1 then
                            CharacterBackupData.tmp = nil
                            CharacterBackupJSON = TableToJSON(CharacterBackupData)
                            print("CharacterBackup: Forced SavedVariables update")
                            cleanupFrame:SetScript("OnUpdate", nil)
                        end
                    end)
                    
                    forceSaveFrame:SetScript("OnUpdate", nil)
                end
            end)
        end
    end
end)

local function GetCharacterLocation()
    -- If we have GPS data, use it
    if capturedGPS.hasData then
        print("CharacterBackup: Using previously captured GPS data")
        -- Double-check that it's in CharacterBackupData too
        CharacterBackupData.location = {
            x = capturedGPS.x,
            y = capturedGPS.y,
            z = capturedGPS.z,
            facing = capturedGPS.facing,
            mapID = capturedGPS.mapID,
            zone = capturedGPS.zone,
            subZone = capturedGPS.subZone
        }
        return CharacterBackupData.location
    end
    
    -- Otherwise get basic data
    local locationData = {
        mapID = GetCurrentMapAreaID() or 0,
        x = 0,
        y = 0,
        z = 0,
        facing = GetPlayerFacing() or 0,
        zone = GetZoneText() or "Unknown",
        subZone = GetSubZoneText() or "Unknown"
    }
    
    -- Send GPS command
    print("CharacterBackup: Requesting GPS data from server...")
    SendChatMessage(".gps", "SAY")
    
    return locationData
end

local function SaveData()
    CharacterBackupData.character = {
        name = UnitName("player"),
        guid = UnitGUID("player"),
        class = select(2, UnitClass("player")),
        race = select(2, UnitRace("player")),
        level = UnitLevel("player")
    }
    
    -- Don't call GetCharacterLocation here - use the global data already stored
    
    -- Save the rest of the data
    CharacterBackupData.guild            = GetGuildData()
    CharacterBackupData.guildVault       = GetGuildVaultData()
    CharacterBackupData.bankItems        = GetBankItems()
    CharacterBackupData.glyphs           = GetGlyphData()
    CharacterBackupData.equippedItems    = GetEquippedData()
    CharacterBackupData.bagItems         = GetBagItems()
    CharacterBackupData.skills           = GetSkillData()
    CharacterBackupData.money            = GetMoneyData()
    CharacterBackupData.learnedSkills    = GetLearnedSkills()
    CharacterBackupData.mounts           = GetMountData()
    CharacterBackupData.pets             = GetPetData()
    CharacterBackupData.talents          = GetTalentData()
    CharacterBackupData.achievements     = GetAchievementData()
    CharacterBackupData.reputations      = GetReputationData()
    CharacterBackupData.inProgressQuests = GetInProgressQuests()
    CharacterBackupData.lastUpdated      = time()

    -- Double check that location data is set - use captured GPS if available
    if capturedGPS.hasData then
        CharacterBackupData.location = {
            x = capturedGPS.x,
            y = capturedGPS.y,
            z = capturedGPS.z,
            facing = capturedGPS.facing,
            mapID = capturedGPS.mapID,
            zone = capturedGPS.zone,
            subZone = capturedGPS.subZone
        }
    end

    -- Convert all data to JSON
    CharacterBackupJSON = TableToJSON(CharacterBackupData)
    print("CharacterBackup: All data including Character Information, quests, Equipped Items, Bag Items, Skills, Money, Learned Skills/Spells, Mounts and Pets, Talents, Guild Info, Guild Vault and Bank Inventory saved successfully!")
end

-- New: Save Guild Data Only (for /backupguild)
local function SaveGuildData()
    CharacterBackupData.guild = GetGuildData()
    CharacterBackupData.guildVault = GetGuildVaultData()
    CharacterBackupJSON = TableToJSON(CharacterBackupData)
    print("CharacterBackup: Guild data (Guild Info and Guild Vault) saved successfully!")
end

-- New: Save Bank Data Only (for /backupbank)
local function SaveBankData()
    CharacterBackupData.bankItems = GetBankItems()
    CharacterBackupJSON = TableToJSON(CharacterBackupData)
    print("CharacterBackup: Bank data saved successfully!")
end

-- Create a single frame for all events
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_QUERY_COMPLETE")
frame:RegisterEvent("PLAYER_LOGOUT") -- Add logout event to ensure saving

-- Use a single event handler for all events
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "CharacterBackup" then
        CharacterBackupData.quests = CharacterBackupData.quests or {}
        CharacterBackupData.inProgressQuests = CharacterBackupData.inProgressQuests or {}
        print("CharacterBackup addon loaded successfully!")
    elseif event == "QUEST_QUERY_COMPLETE" then
        local completedQuests = {}
        GetQuestsCompleted(completedQuests)
        CharacterBackupData.quests = completedQuests
        print("CharacterBackup: Completed quests updated!")
    elseif event == "PLAYER_LOGOUT" then
        -- Force update location before logout
        if capturedGPS.hasData then
            CharacterBackupData.location = {
                x = capturedGPS.x,
                y = capturedGPS.y,
                z = capturedGPS.z,
                facing = capturedGPS.facing,
                mapID = capturedGPS.mapID,
                zone = capturedGPS.zone,
                subZone = capturedGPS.subZone
            }
            CharacterBackupJSON = TableToJSON(CharacterBackupData)
        end
    end
end)

SLASH_CHARACTERBACKUP1 = "/backup"
SlashCmdList["CHARACTERBACKUP"] = function()
    QueryQuestsCompleted()
    GetCharacterLocation()  -- This gets the basic location data and requests GPS
    
    -- Call SaveData after a short delay to allow GPS data to be processed
    local saveFrame = CreateFrame("Frame")
    local timeElapsed = 0
    saveFrame:SetScript("OnUpdate", function(self, elapsed)
        timeElapsed = timeElapsed + elapsed
        if timeElapsed >= 2 then -- 2 second delay
            SaveData()  -- Save all data including any updated GPS data
            saveFrame:SetScript("OnUpdate", nil)  -- Stop the timer
        end
    end)
end

SLASH_CHARACTERBACKUPGUILD1 = "/backupguild"
SlashCmdList["CHARACTERBACKUPGUILD"] = function()
    SaveGuildData()
end

SLASH_CHARACTERBACKUPBANK1 = "/backupbank"
SlashCmdList["CHARACTERBACKUPBANK"] = function()
    SaveBankData()
end

-- Add reload command that can be used after capturing GPS data
SLASH_RELOADCHARBACKUP1 = "/savegps"
SlashCmdList["RELOADCHARBACKUP"] = function()
    -- Check if we have GPS data and force an update before reload
    if capturedGPS.hasData then
        CharacterBackupData.location = {
            x = capturedGPS.x,
            y = capturedGPS.y,
            z = capturedGPS.z,
            facing = capturedGPS.facing,
            mapID = capturedGPS.mapID,
            zone = capturedGPS.zone,
            subZone = capturedGPS.subZone
        }
        CharacterBackupJSON = TableToJSON(CharacterBackupData)
    end
    
    print("CharacterBackup: Saving and reloading UI to ensure GPS data is written to disk...")
    ReloadUI()
end