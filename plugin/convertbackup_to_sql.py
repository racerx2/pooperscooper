import json
import re
import csv
import time

def extract_item_id(item_link):
    """
    Extracts the numeric item id from an item link string.
    Example:
      "|cffffffff|Hitem:3890:0:0:0:0:0:0:0:60|h[Studded Hat]|h|r" -> 3890
    """
    match = re.search(r"\|Hitem:(\d+):", item_link)
    return int(match.group(1)) if match else 0

def load_json_from_lua(filename):
    """
    Loads the Lua file and extracts the JSON data stored in the variable 
    CharacterBackupJSON.
    
    This function searches for the marker "CharacterBackupJSON =" and then 
    finds the first double quote. It then reads until it finds an unescaped 
    closing quote. The extracted string is decoded from Lua escape sequences 
    and parsed as JSON.
    """
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    marker = "CharacterBackupJSON ="
    start = content.find(marker)
    if start == -1:
        raise ValueError("CharacterBackupJSON not found in file.")
    
    first_quote = content.find('"', start)
    if first_quote == -1:
        raise ValueError("Starting quote for CharacterBackupJSON not found.")
    
    i = first_quote + 1
    extracted = ""
    while i < len(content):
        ch = content[i]
        if ch == '"' and content[i-1] != '\\':
            break
        extracted += ch
        i += 1
    decoded = bytes(extracted, "utf-8").decode("unicode_escape")
    return json.loads(decoded)

def load_faction_mapping(csv_filename):
    """
    Loads faction mappings from a CSV file.
    The CSV file is expected to have headers: FactionID,FactionName
    Returns a dictionary mapping faction name (stripped and case-sensitive)
    to faction id (as an integer).
    """
    mapping = {}
    with open(csv_filename, "r", encoding="utf-8") as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            try:
                faction_id = int(row["FactionID"])
                faction_name = row["FactionName"].strip()
                mapping[faction_name] = faction_id
            except Exception as e:
                print("Error processing row:", row, e)
    return mapping

# Mappings for race and class as used in WoW 3.3.5a / ChromieCraft.
race_mapping = {
    "Human": 1,
    "Orc": 2,
    "Dwarf": 3,
    "NightElf": 4,
    "Undead": 5,
    "Tauren": 6,
    "Gnome": 7,
    "Troll": 8,
    "Goblin": 9,
    "BloodElf": 10,
    "Draenei": 11,
}

class_mapping = {
    "WARRIOR": 1,
    "PALADIN": 2,
    "HUNTER": 3,
    "ROGUE": 4,
    "PRIEST": 5,
    "DEATHKNIGHT": 6,
    "SHAMAN": 7,
    "MAGE": 8,
    "WARLOCK": 9,
    "DRUID": 11,
}

# Load faction mapping from the CSV file.
faction_mapping = load_faction_mapping("extracted_factions.csv")

# Load JSON data from CharacterBackup.lua via CharacterBackupJSON.
backup = load_json_from_lua('CharacterBackup.lua')

# We'll track which (bag, slot) pairs we have inserted to avoid duplicates.
inserted_inventory = set()

with open('character_backup.sql', 'w', encoding='utf-8') as sqlfile:
    # 1. Replace main character info in the 'characters' table.
    char = backup.get("character", {})
    location = backup.get("location", {})
    money_data = backup.get("money", {})
    total_copper = (money_data.get("gold", 0) * 10000 +
                   money_data.get("silver", 0) * 100 +
                   money_data.get("copper", 0))
    
    guid_str = char.get("guid", "0")
    try:
        guid = int(guid_str, 16)
    except ValueError:
        guid = 0
    # To avoid duplicate GUID conflicts, generate a new guid.
    new_guid = guid + 1000

    race_str = char.get("race", "Unknown")
    race_id = race_mapping.get(race_str, 0)
    class_str = char.get("class", "Unknown").upper()
    class_id = class_mapping.get(class_str, 0)
    
    # Get location data directly from the saved variables
    map_id = location.get("mapID", 1)  # Use the mapID from data
    zone_id = location.get("zone")     # Get the numeric zone value

    # If zone value is a string (zone name) rather than a number, try to convert it
    if isinstance(zone_id, str):
        try:
            # Try to convert to a number first - it might be a numeric string
            zone_id = int(zone_id)
        except ValueError:
            # If it's a text name, try to find it in faction mapping
            zone_id = faction_mapping.get(zone_id, 0)
    elif zone_id is None:
        # If zone is missing, use a sensible default
        zone_id = 0

    # Use the exact coordinates directly without any conversions
    position_x = location.get("x", 0)
    position_y = location.get("y", 0)
    position_z = location.get("z", 0)
    orientation = location.get("facing", 0)
    
    # Create equipmentCache string with the bag data correctly included
    equipment_cache = "3890 0 0 0 0 0 20897 0 2463 0 2464 0 2465 0 2467 0 2468 0 2469 0 0 0 0 0 0 0 0 0 0 0 4454 0 776 0 29009 0 5976 0 4499 0 4499 0 4499 0 0 0"
    
    # Update with actual item IDs from saved variables
    equipped = backup.get("equippedItems", [])
    if equipped:
        pairs = equipment_cache.split()
        for slot, item_link in enumerate(equipped):
            if slot * 2 < len(pairs) and item_link and item_link.strip():
                item_id = extract_item_id(item_link)
                pairs[slot * 2] = str(item_id)
        
        # Reconstruct the equipment cache string
        equipment_cache = " ".join(pairs)
    
    # Define character_sql with the proper format
    character_sql = f"""INSERT INTO `characters` 
    (`guid`, `name`, `race`, `class`, `level`, `money`, `equipmentCache`, `taximask`, `innTriggerId`, `position_x`, `position_y`, `position_z`, `orientation`, `map`, `zone`) 
    VALUES 
    ({new_guid}, '{char.get("name", "Unknown")}', {race_id}, {class_id}, {char.get("level", 1)}, {total_copper}, '{equipment_cache}', '', 0, 
    {position_x}, {position_y}, {position_z}, {orientation}, {map_id}, {zone_id})
    ON DUPLICATE KEY UPDATE
    `guid` = VALUES(`guid`), `name` = VALUES(`name`), `race` = VALUES(`race`), `class` = VALUES(`class`), 
    `level` = VALUES(`level`), `money` = VALUES(`money`), `equipmentCache` = VALUES(`equipmentCache`), 
    `taximask` = VALUES(`taximask`), `innTriggerId` = VALUES(`innTriggerId`), 
    `position_x` = VALUES(`position_x`), `position_y` = VALUES(`position_y`), `position_z` = VALUES(`position_z`), 
    `orientation` = VALUES(`orientation`), `map` = VALUES(`map`), `zone` = VALUES(`zone`);"""
            
    sqlfile.write(character_sql + "\n\n")

    # 2. Create and add bags as item instances with proper SQL format
    # Extract bag items from the equipment cache
    bag_ids = []
    parts = equipment_cache.split()
    for i in range(19, 23):  # Bag slots 19-22
        if i * 2 < len(parts):
            bag_id = int(parts[i * 2])
            if bag_id > 0:
                bag_ids.append(bag_id)
            else:
                bag_ids.append(0)  # Empty bag slot
    
    # Create bag instances and add them to inventory
    for i, bag_id in enumerate(bag_ids):
        if bag_id > 0:  # Only process non-empty bag slots
            bag_guid = new_guid * 100 + 75 + i  # Unique GUID for bag
            bag_slot = 19 + i  # Slots 19-22
            
            # Create the bag item instance
            item_instance_sql = f"""INSERT INTO `item_instance` (`guid`, `itemEntry`, `owner_guid`, `creatorGuid`, `giftCreatorGuid`, `count`, `duration`, `charges`, `flags`, `enchantments`, `randomPropertyId`, `durability`, `playedTime`, `text`)
VALUES ({bag_guid}, {bag_id}, {new_guid}, 0, 0, 1, 0, '0 0 0 0 0', 0, '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 0, 0, 0, '')
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `itemEntry` = VALUES(`itemEntry`), `owner_guid` = VALUES(`owner_guid`), `creatorGuid` = VALUES(`creatorGuid`), 
`giftCreatorGuid` = VALUES(`giftCreatorGuid`), `count` = VALUES(`count`), `duration` = VALUES(`duration`), `charges` = VALUES(`charges`), 
`flags` = VALUES(`flags`), `enchantments` = VALUES(`enchantments`), `randomPropertyId` = VALUES(`randomPropertyId`), 
`durability` = VALUES(`durability`), `playedTime` = VALUES(`playedTime`), `text` = VALUES(`text`);"""
            sqlfile.write(item_instance_sql + "\n")
            
            # Add the bag to character inventory
            inv_sql = f"""INSERT INTO `character_inventory` (`guid`, `bag`, `slot`, `item`)
VALUES ({new_guid}, 0, {bag_slot}, {bag_guid})
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `bag` = VALUES(`bag`), `slot` = VALUES(`slot`), `item` = VALUES(`item`);"""
            sqlfile.write(inv_sql + "\n\n")

    # 3. Replace in-progress quests into 'character_queststatus'.
    quests = backup.get("inProgressQuests", {})
    for quest_id_str, quest_name in quests.items():
        try:
            quest_id = int(quest_id_str)
        except ValueError:
            quest_id = 0
        quest_sql = f"""INSERT INTO `character_queststatus` (`guid`, `quest`, `status`)
VALUES ({new_guid}, {quest_id}, 1)
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `quest` = VALUES(`quest`), `status` = VALUES(`status`);"""
        sqlfile.write(quest_sql + "\n")
    sqlfile.write("\n")
    
    # 4. Replace reputations into 'character_reputation'.
    reputations = backup.get("reputations", {})
    for faction_name, rep in reputations.items():
        faction_id = faction_mapping.get(faction_name)
        if faction_id is None:
            print(f"Warning: Faction '{faction_name}' not found in mapping. Skipping.")
            continue
        standing = rep.get("standingID", 0)
        rep_sql = f"""INSERT INTO `character_reputation` (`guid`, `faction`, `standing`, `flags`)
VALUES ({new_guid}, {faction_id}, {standing}, 0)
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `faction` = VALUES(`faction`), `standing` = VALUES(`standing`), `flags` = VALUES(`flags`);"""
        sqlfile.write(rep_sql + "\n")
    sqlfile.write("\n")
    
    # 5. Replace mounts into the 'character_spell' table as mount spells.
    mounts = backup.get("mounts", [])
    for mount in mounts:
        spell_id = mount.get("spellID", 0)
        mount_sql = f"""INSERT INTO `character_spell` (`guid`, `spell`)
VALUES ({new_guid}, {spell_id})
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `spell` = VALUES(`spell`);"""
        sqlfile.write(mount_sql + "\n")
    sqlfile.write("\n")
    
    # 6. Replace guild data into the 'guild' table.
    guild = backup.get("guild")
    if guild:
        guild_id = 1  # Adjust as needed.
        guild_name = guild.get("name", "Unknown")
        if guild.get("rank", "").lower() == "guild master":
            leaderguid = new_guid
        else:
            leaderguid = 0
        guild_vault = backup.get("guildVault")
        vault_money = guild_vault.get("money", 0) if guild_vault else 0
        guild_sql = f"""INSERT INTO `guild` (`guildid`, `name`, `leaderguid`, `EmblemStyle`, `EmblemColor`, `BorderStyle`, `BorderColor`, `BackgroundColor`, `bankMoney`, `MOTD`)
VALUES ({guild_id}, '{guild_name}', {leaderguid}, 0, 0, 0, 0, 0, {vault_money}, '')
ON DUPLICATE KEY UPDATE
`guildid` = VALUES(`guildid`), `name` = VALUES(`name`), `leaderguid` = VALUES(`leaderguid`), 
`EmblemStyle` = VALUES(`EmblemStyle`), `EmblemColor` = VALUES(`EmblemColor`), 
`BorderStyle` = VALUES(`BorderStyle`), `BorderColor` = VALUES(`BorderColor`), 
`BackgroundColor` = VALUES(`BackgroundColor`), `bankMoney` = VALUES(`bankMoney`), `MOTD` = VALUES(`MOTD`);"""
        sqlfile.write(guild_sql + "\n\n")
        
        # Add character to guild in guild_member table
        rank_id = 0 if guild.get("rank", "").lower() == "guild master" else 1
        guild_member_sql = f"""INSERT INTO `guild_member` (`guildid`, `guid`, `rank`, `pnote`, `offnote`)
VALUES ({guild_id}, {new_guid}, {rank_id}, '', '')
ON DUPLICATE KEY UPDATE
`guildid` = VALUES(`guildid`), `guid` = VALUES(`guid`), `rank` = VALUES(`rank`), 
`pnote` = VALUES(`pnote`), `offnote` = VALUES(`offnote`);"""
        sqlfile.write(guild_member_sql + "\n\n")

        # 7. Replace guild vault items into the 'guild_bank_item' table.
        if guild_vault:
            vault_items = guild_vault.get("items", [])
            
            # First, make sure the guild_bank_tabs are set up
            tabs = guild_vault.get("tabs", [])
            for tab_index, tab_data in enumerate(tabs):
                tab_name = tab_data.get("name", f"Tab{tab_index+1}")
                tab_icon = tab_data.get("icon", "")
                tab_sql = f"""INSERT INTO `guild_bank_tab` (`guildid`, `TabId`, `TabName`, `TabIcon`, `TabText`)
VALUES ({guild_id}, {tab_index}, '{tab_name}', '{tab_icon}', '')
ON DUPLICATE KEY UPDATE
`guildid` = VALUES(`guildid`), `TabId` = VALUES(`TabId`), `TabName` = VALUES(`TabName`), 
`TabIcon` = VALUES(`TabIcon`), `TabText` = VALUES(`TabText`);"""
                sqlfile.write(tab_sql + "\n")
            sqlfile.write("\n")
            
            # Now handle the items
            for tab_index, tab_items in enumerate(vault_items):
                if not tab_items:
                    continue
                    
                if isinstance(tab_items, list):
                    for slot, item_data in enumerate(tab_items):
                        if not item_data:
                            continue
                        item_link = item_data.get("item", "")
                        if item_link.strip() == "":
                            continue
                            
                        item_id = extract_item_id(item_link)
                        item_count = item_data.get("count", 1)
                        
                        # Create a unique item instance
                        item_guid = new_guid * 10000 + tab_index * 100 + slot
                        item_instance_sql = f"""INSERT INTO `item_instance` (`guid`, `itemEntry`, `owner_guid`, `creatorGuid`, `giftCreatorGuid`, `count`, `duration`, `charges`, `flags`, `enchantments`, `randomPropertyId`, `durability`, `playedTime`, `text`)
VALUES ({item_guid}, {item_id}, {guild_id}, 0, 0, {item_count}, 0, '0 0 0 0 0', 0, '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 0, 100, 0, '')
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `itemEntry` = VALUES(`itemEntry`), `owner_guid` = VALUES(`owner_guid`), `creatorGuid` = VALUES(`creatorGuid`), 
`giftCreatorGuid` = VALUES(`giftCreatorGuid`), `count` = VALUES(`count`), `duration` = VALUES(`duration`), `charges` = VALUES(`charges`), 
`flags` = VALUES(`flags`), `enchantments` = VALUES(`enchantments`), `randomPropertyId` = VALUES(`randomPropertyId`), 
`durability` = VALUES(`durability`), `playedTime` = VALUES(`playedTime`), `text` = VALUES(`text`);"""
                        sqlfile.write(item_instance_sql + "\n")
                        
                        # Link item to guild bank
                        guild_item_sql = f"""INSERT INTO `guild_bank_item` (`guildid`, `TabId`, `SlotId`, `item_guid`)
VALUES ({guild_id}, {tab_index}, {slot}, {item_guid})
ON DUPLICATE KEY UPDATE
`guildid` = VALUES(`guildid`), `TabId` = VALUES(`TabId`), `SlotId` = VALUES(`SlotId`), `item_guid` = VALUES(`item_guid`);"""
                        sqlfile.write(guild_item_sql + "\n")
                        
                elif isinstance(tab_items, dict):
                    for slot_str, item_data in tab_items.items():
                        try:
                            slot = int(slot_str)
                        except ValueError:
                            continue
                            
                        if not item_data:
                            continue
                            
                        item_link = item_data.get("item", "")
                        if item_link.strip() == "":
                            continue
                            
                        item_id = extract_item_id(item_link)
                        item_count = item_data.get("count", 1)
                        
                        # Create a unique item instance
                        item_guid = new_guid * 10000 + tab_index * 100 + slot
                        item_instance_sql = f"""INSERT INTO `item_instance` (`guid`, `itemEntry`, `owner_guid`, `creatorGuid`, `giftCreatorGuid`, `count`, `duration`, `charges`, `flags`, `enchantments`, `randomPropertyId`, `durability`, `playedTime`, `text`)
VALUES ({item_guid}, {item_id}, {guild_id}, 0, 0, {item_count}, 0, '0 0 0 0 0', 0, '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 0, 100, 0, '')
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `itemEntry` = VALUES(`itemEntry`), `owner_guid` = VALUES(`owner_guid`), `creatorGuid` = VALUES(`creatorGuid`), 
`giftCreatorGuid` = VALUES(`giftCreatorGuid`), `count` = VALUES(`count`), `duration` = VALUES(`duration`), `charges` = VALUES(`charges`), 
`flags` = VALUES(`flags`), `enchantments` = VALUES(`enchantments`), `randomPropertyId` = VALUES(`randomPropertyId`), 
`durability` = VALUES(`durability`), `playedTime` = VALUES(`playedTime`), `text` = VALUES(`text`);"""
                        sqlfile.write(item_instance_sql + "\n")
                        
                        # Link item to guild bank
                        guild_item_sql = f"""INSERT INTO `guild_bank_item` (`guildid`, `TabId`, `SlotId`, `item_guid`)
VALUES ({guild_id}, {tab_index}, {slot}, {item_guid})
ON DUPLICATE KEY UPDATE
`guildid` = VALUES(`guildid`), `TabId` = VALUES(`TabId`), `SlotId` = VALUES(`SlotId`), `item_guid` = VALUES(`item_guid`);"""
                        sqlfile.write(guild_item_sql + "\n")
    
    # 8. Add character's bank items
    bank_items = backup.get("bankItems", {})
    for bag_id_str, items in bank_items.items():
        try:
            bag_id = int(bag_id_str)
        except ValueError:
            continue
            
        if not items or not isinstance(items, list):
            continue
            
        for slot, item_data in enumerate(items):
            if not item_data:
                continue
                
            item_link = item_data.get("item", "")
            if item_link.strip() == "":
                continue
                
            item_id = extract_item_id(item_link)
            item_count = item_data.get("count", 1)
            
            # Create a unique item instance for bank item
            bank_item_guid = new_guid * 10000 + (bag_id + 100) * 100 + slot
            bank_instance_sql = f"""INSERT INTO `item_instance` (`guid`, `itemEntry`, `owner_guid`, `creatorGuid`, `giftCreatorGuid`, `count`, `duration`, `charges`, `flags`, `enchantments`, `randomPropertyId`, `durability`, `playedTime`, `text`)
VALUES ({bank_item_guid}, {item_id}, {new_guid}, 0, 0, {item_count}, 0, '0 0 0 0 0', 0, '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 0, 100, 0, '')
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `itemEntry` = VALUES(`itemEntry`), `owner_guid` = VALUES(`owner_guid`), `creatorGuid` = VALUES(`creatorGuid`), 
`giftCreatorGuid` = VALUES(`giftCreatorGuid`), `count` = VALUES(`count`), `duration` = VALUES(`duration`), `charges` = VALUES(`charges`), 
`flags` = VALUES(`flags`), `enchantments` = VALUES(`enchantments`), `randomPropertyId` = VALUES(`randomPropertyId`), 
`durability` = VALUES(`durability`), `playedTime` = VALUES(`playedTime`), `text` = VALUES(`text`);"""
            sqlfile.write(bank_instance_sql + "\n")
            
            # The main bank is special - it's container ID -1
            if bag_id == -1:
                bank_slot = slot + 39  # Bank slots typically start after inventory slots
                bank_sql = f"""INSERT INTO `character_inventory` (`guid`, `bag`, `slot`, `item`)
VALUES ({new_guid}, 0, {bank_slot}, {bank_item_guid})
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `bag` = VALUES(`bag`), `slot` = VALUES(`slot`), `item` = VALUES(`item`);"""
                sqlfile.write(bank_sql + "\n")
            else:
                # For bank bags, first make sure the bag itself exists
                if bag_id >= 5 and bag_id <= 11:  # Bank bags are typically 5-11
                    # Create bank bag instance if it doesn't exist yet
                    bank_bag_guid = new_guid * 100 + 90 + (bag_id - 5)
                    bank_bag_id = item_id  # Use the first item's ID as the bag ID
                    bank_bag_slot = bag_id - 5 + 63  # Convert to AzerothCore bank bag slot numbering
                    
                    bank_bag_sql = f"""INSERT INTO `item_instance` (`guid`, `itemEntry`, `owner_guid`, `creatorGuid`, `giftCreatorGuid`, `count`, `duration`, `charges`, `flags`, `enchantments`, `randomPropertyId`, `durability`, `playedTime`, `text`)
VALUES ({bank_bag_guid}, {bank_bag_id}, {new_guid}, 0, 0, 1, 0, '0 0 0 0 0', 0, '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 0, 100, 0, '')
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `itemEntry` = VALUES(`itemEntry`), `owner_guid` = VALUES(`owner_guid`), `creatorGuid` = VALUES(`creatorGuid`), 
`giftCreatorGuid` = VALUES(`giftCreatorGuid`), `count` = VALUES(`count`), `duration` = VALUES(`duration`), `charges` = VALUES(`charges`), 
`flags` = VALUES(`flags`), `enchantments` = VALUES(`enchantments`), `randomPropertyId` = VALUES(`randomPropertyId`), 
`durability` = VALUES(`durability`), `playedTime` = VALUES(`playedTime`), `text` = VALUES(`text`);"""
                    sqlfile.write(bank_bag_sql + "\n")
                    
                    # Add bank bag to inventory
                    bank_bag_inv_sql = f"""INSERT INTO `character_inventory` (`guid`, `bag`, `slot`, `item`)
VALUES ({new_guid}, 0, {bank_bag_slot}, {bank_bag_guid})
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `bag` = VALUES(`bag`), `slot` = VALUES(`slot`), `item` = VALUES(`item`);"""
                    sqlfile.write(bank_bag_inv_sql + "\n")
                    
                    # Add item to the bank bag
                    bank_item_sql = f"""INSERT INTO `character_inventory` (`guid`, `bag`, `slot`, `item`)
VALUES ({new_guid}, {bank_bag_guid}, {slot}, {bank_item_guid})
ON DUPLICATE KEY UPDATE
`guid` = VALUES(`guid`), `bag` = VALUES(`bag`), `slot` = VALUES(`slot`), `item` = VALUES(`item`);"""
                    sqlfile.write(bank_item_sql + "\n")

print("SQL conversion completed. Output written to character_backup.sql")