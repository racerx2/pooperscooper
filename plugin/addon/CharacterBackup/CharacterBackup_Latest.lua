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

local function GetLearnedSkills()
    local learnedSkills = {}
    for i = 1, MAX_SKILLLINE_TABS do
        local tabName, _, offset, numSpells = GetSpellTabInfo(i)
        if not tabName then break end
        for j = 1, numSpells do
            local spellIndex = offset + j
            local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
            learnedSkills[spellName] = { rank = spellRank or "Passive", spellID = 0 }
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
        local tabInfo = { name=tabName, icon=tabIcon, pointsSpent=tabPointsSpent, talents={} }
        for talentIndex = 1, GetNumTalents(tabIndex) do
            local name, icon, tier, column, currentRank, maxRank = GetTalentInfo(tabIndex, talentIndex)
            tabInfo.talents[name] = { icon=icon, tier=tier, column=column, rank=currentRank, max=maxRank }
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
            reputations[name] = { standingID=standingID, current=earnedValue, minimum=bottomValue, maximum=topValue }
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

    return inProgressQuests -- Fix applied here
end


-- Get glyphs (up to 6 in WotLK)
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

local function SaveData()
    CharacterBackupData.character = {
        name = UnitName("player"),
        guid = UnitGUID("player"),
        class = select(2, UnitClass("player")),
        race = select(2, UnitRace("player")),
        level = UnitLevel("player")
    }
    CharacterBackupData.guild            = GetGuildData()
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

    CharacterBackupJSON = TableToJSON(CharacterBackupData)
    print("CharacterBackup: All data including Character Information, quests, Equipped Items, Bag Items, Skills, Money, Learned Skills/Spells, Mounts and Pets, Talents, saved successfully!")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_QUERY_COMPLETE")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "QUEST_QUERY_COMPLETE" then
        GetQuestsCompleted(CharacterBackupData.quests)
    end
end)

SLASH_CHARACTERBACKUP1 = "/backup"
SlashCmdList["CHARACTERBACKUP"] = function()
    QueryQuestsCompleted()
    SaveData()
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "CharacterBackup" then
        CharacterBackupData.quests = CharacterBackupData.quests or {}
        CharacterBackupData.inProgressQuests = CharacterBackupData.inProgressQuests or {}

    elseif event == "QUEST_QUERY_COMPLETE" then
        local completedQuests = {}
        GetQuestsCompleted(completedQuests)
        CharacterBackupData.quests = completedQuests
        print("CharacterBackup: Completed quests updated!")
    end
end)
