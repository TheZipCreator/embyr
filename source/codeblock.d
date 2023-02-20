module codeblock;

import std.json, std.algorithm, std.string;

import compiler;

/// A codeblock inside a declaration
interface CodeBlock {
	JSONValue toJSON(); /// Convert this codeblock to json
	int size();
}

struct TagValue {
	string name;
	string option;
}

class Else : CodeBlock {
	this() {}
	JSONValue toJSON() {
		return JSONValue([
			"block": "else",
			"id": "block"
		]);
	}
	int size() {
		return 1;
	}
}

class Piston : CodeBlock {
	bool dir; /// false = open, true = close
	bool type; /// false = norm, true = repeat

	this(bool dir, bool type) {
		this.dir = dir;
		this.type = type;
	}

	JSONValue toJSON() {
		return JSONValue([
			"direct": dir ? "close" : "open",
			"id": "bracket",
			"type": type ? "repeat" : "norm"
		]);
	}

	int size() {
		return dir ? 2 : 1;
	}
}

class CallFunction : CodeBlock {
	string func;

	this(string func) {
		this.func = func;
	}

	JSONValue toJSON() {
		auto val = JSONValue([
			"id": "block",
			"block": "call_func",
			"data": func
		]);
		val["args"] = ["items": emptyArray];
		return val;
	}

	int size() {
		return 2;
	}
}

class StartProcess : CodeBlock {
	string process;

	static tags = [
		Tag("Local Variables", ["Don't copy", "Copy", "Share"]),
		Tag("Target Mode", ["With current targets", "With current selection", "With no targets", "For each in selection"])
	];

	JSONValue[] items;

	this(JSONValue[] items, TagValue[] tagvs, string process) {
		this.process = process;
		this.items = items;
		validateTags(this, "start process", "start_process", "dynamic", tagvs, tags);
	}

	JSONValue toJSON() {
		auto val = JSONValue([
			"block": "start_process",
			"data": process,
			"id": "block"
		]);
		val["args"] = ["items": items];
		return val;
	}

	int size() {
		return 2;
	}
}

// TODO: move this somewhere else
/// Checks and validates tags
void validateTags(T)(T bl, string name, string block, string action, TagValue[] tagvs, Tag[] tags) {
	bool[string] found; // tags that have been found 
	// find largest slot (important for detecting value/tag overlap)
	int slot = 0;
	foreach(i; bl.items) {
		int s = cast(int)(i["slot"].integer);
		if(s > slot)
			slot = s;
	}
	// make sure all tags are present and valid
	foreach(t; tagvs) {
		if(!tags.canFind(t.name))
			throw new CompilerException("Invalid tag '"~t.name~"' for "~name~".");
		if(t.name in found)
			throw new CompilerException("Duplicate tag '"~t.name~"'.");
		auto opts = tags.find!(a => a.name == t.name)[0].options;
		if(!opts.canFind(t.option))
			throw new CompilerException("Invalid option '"~t.option~"' for tag '"~t.name~"'. Valid options are:\n"~opts.join("\n"));
		found[t.name] = true;
	}
	foreach(tag; tags) 
		if(tag.name !in found) { 
			if(!addtags) 
				throw new CompilerException("Missing tag '"~tag.name~"'. Add argument --addtags to automatically generate missing tags. Valid options for this tag are:\n"~tag.options.join("\n"));
			tagvs ~= TagValue(tag.name, tag.options[0]);
		}
	// add tags to items
	foreach(t; tagvs) {
		auto o = emptyObject;
		int s = cast(int)(tags.countUntil!(a => a.name == t.name)+27-tags.length);
		if(slot >= s)
			throw new CompilerException("Overlapping values and tags.");
		auto item = emptyObject;
		item["data"] = [
			"block": block,
			"action": action,
			"tag": t.name,
			"option": t.option
		];
		item["id"] = "bl_tag";
		o["item"] = item;
		o["slot"] = s;
		bl.items ~= o;
	}

}

/// Represents a tag
struct Tag {
	string name;
	string[] options;
	bool opEquals(string s) {
		return s == name;
	}
}

/// Represents actions and setvars
abstract class Action : CodeBlock {	
	JSONValue[] items;
	

	/// Possible actions. Each key corresponds with a map of each tag. 
	Tag[][string] actions() { return null; }
	
	string action;
	string target;

	string block() { return ""; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		this.items = items;
		this.action = action;
		if(action !in actions)
			throw new CompilerException("Invalid action '"~action~"'.");
		if(!targets.canFind(target))
			throw new CompilerException("Invalid target '"~target~"'.");
		this.target = target;
		auto tags = actions[action];
		validateTags(this, "action '"~action~"'", block, action, tagvs, tags);
	}

	JSONValue toJSON() {
		auto v = emptyObject;
		v["args"] = [
			"items": items
		];
		v["action"] = action;
		v["id"] = "block";
		v["block"] = block;
		if(target != "")
			v["target"] = target;
		return v;
	}

	int size() {
		return 2;
	}
}

/// A player action
class PlayerAction : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			// Item Management
			"GiveItems": [], "SetHotbar": [], "SetInventory": [], "SetSlotItem": [], 
			"SetEquipment": [Tag("Equipment Slot", ["Main hand", "Off hand", "Head", "Chest", "Legs", "Feet"])],
			"SetArmor": [], "ReplaceItems": [], "RemoveItems": [], "ClearItems": [],
			"ClearInv": [Tag("Clear Crafting and Cursor", ["True", "False"]), Tag("Clear Mode", ["Entire inventory", "Main inventory", "Upper inventory", "Hotbar", "Armor"])],
			"SetCursorItem": [], "SaveInv": [], "LoadInv": [], "SetItemCooldown": [],
			// Communication
			"SendMessage": [Tag("Text Value Merging", ["Add spaces", "No spaces"]), Tag("Alignment Mode", ["Regular", "Centered"])],
			"SendMessageSeq": [], "SendHover": [], "SendTitle": [], "ActionBar": [Tag("Text Value Merging", ["Add spaces", "No spaces"])],
			"OpenBook": [],
			"SetBossBar": [Tag("Sky Effect", ["[]", "Create fog", "Darken sky", "Both"]), Tag("Bar Style", ["Solid", "6 segments", "10 segments", "12 segments", "20 segments"]), Tag("Bar Color", ["Red", "Purple", "Pink", "Blue", "Green", "Yellow", "White"])],
			"RemoveBossBar": [], "SendAdvancement": [], "SetPlayerListInfo": [Tag("Player List Field", ["Header", "Footer"])], 
			"PlaySound": [Tag("Sound Source", ["Master", "Music", "Jukebox/Note Blocks", "Weather", "Blocks", "Hostile Creatures", "Friendly Creatures", "Players", "Ambient/Environment", "Voice/Speech"])],
			"StopSounds": [Tag("Sound Source", ["Master", "Music", "Jukebox/Note Blocks", "Weather", "Blocks", "Hostile Creatures", "Friendly Creatures", "Players", "Ambient/Environment", "Voice/Speech"])],
			"PlaySoundSeq": [],
			// Inventory Menus
			"ShowInv": [], "ExpandInv": [], "SetMenuItem": [], "SetInvName": [], "AddInvRow": [Tag("New Row Position", ["Top row", "Bottom row"])],
			"RemoveInvRow": [Tag("Row to Remove", ["Top row", "Bottom row"])], "CloseInv": [], "OpenBlockInv": [],
			// Scoreboard Manipulation
			"SetScoreboardObj": [], "SetSidebar": [Tag("Sidebar", ["Enable", "Disable"])], "SetScore": [], "RemoveScore": [], "ClearScoreboard": [],
			// Statistics
			"Damage": [], "Heal": [], "SetHealth": [], "SetMaxHealth": [], "SetAbsorption": [], "SetFoodLevel": [], "SetSaturation": [],
			"GiveExp": [Tag("Give Experience", ["Points", "Levels", "Level percentage"])], "SetExp": [Tag("Set Experience", ["Points", "Levels", "Level percentage"])],
		 	"GivePotion": [Tag("Show Icon", ["True", "False"]), Tag("Overwrite Effect", ["True", "False"]), Tag("Effect Particles", ["Regular", "Ambient", "None"])],
			"RemovePotion": [], "ClearPotions": [], "SetSlot": [], "SetAtkSpeed": [], "SetFireTicks": [], "SetFreezeTicks": [Tag("Ticking Locked", ["Disable", "Enable"])],
			"SetAirTicks": [], "SetInvulTicks": [], "SetFallDistance": [], "SetSpeed": [Tag("Speed Type", ["Ground speed", "Flight speed", "Both"])],
			// Settings
			"SurvivalMode": [], "AdventureMode": [], "CreativeMode": [], "SpectatorMode": [], "SetAllowFlight": [Tag("Allow Flight", ["Enable", "Disable"])],
			"SetAllowPVP": [Tag("PVP", ["Disable", "Enable"])], "SetDropsEnabled": [Tag("Spawn Death Drops", ["Enable", "Disable"])],
			"SetInventoryKept": [Tag("Inventory Kept", ["Enable", "Disable"])], "SetCollidable": [Tag("Enable Collision", ["Disable", "Enable"])],
			"EnableBlocks": [], "DisableBlocks": [], "InstantRespawn": [Tag("Instant Respawn", ["Enable", "Disable"])], 
			"SetReducedDebug": [Tag("Reduced Debug Info Enabled", ["True", "False"])],
			// Movement
			"Teleport": [Tag("Keep Velocity", ["False", "True"]), Tag("Keep Current Rotation", ["False", "True"])],
			"LaunchUp": [Tag("Add to Current Velocity", ["True", "False"])],
			"LaunchFwd": [Tag("Add to Current Velocity", ["True", "False"]), Tag("Launch Axis", ["Pitch and Yaw", "Yaw Only"])],
			"LaunchToward": [Tag("Add to Current Velocity", ["True", "False"]), Tag("Ignore Distance", ["False", "True"])],
			"RideEntity": [], "SetFlying": [Tag("Flying", ["Enable", "Disable"])], "SetGliding": [Tag("Gliding", ["Enable", "Disable"])], "BoostElytra": [],
			"SetRotation": [], "FaceLocation": [], "SetVelocity": [Tag("Add to Current Velocity", ["False", "True"])], "SpectateTarget": [],
			"SetSpawnPoint": [],
			// World
			"LaunchProj": [], "SetPlayerTime": [], "SetPlayerWeather": [Tag("Weather", ["Downfall", "Clear", "Reset"])], "SetCompassTarget": [], "DisplayBlock": [],
			"DisplayFracture": [Tag("Overwrite Previous Fracture", ["True", "False"])], "DisplayBlockOpen": [Tag("Container State", ["Open", "Closed"])],
			"DisplayGateway": [Tag("Animation Type", ["Initial Beam", "Periodic Beam"])],
			"DisplaySignText": [Tag("Text Color", ["Black", "White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray", "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red"]), Tag("Glowing", ["Disable", "Enable"])],
			"DisplayHologram": [], "SetFogDistance": [], "SetWorldBorder": [], "ShiftWorldBorder": [], "RmWorldBorder": [], "DisplayPickup": [],
			"SetEntityHidden": [Tag("Hidden", ["Enable", "Disable"])],
			// TODO: Visual Effects

			// Appearance
			"MobDisguise": [], "PlayerDisguise": [], "BlockDisguise": [], "SetDisguiseVisible": [Tag("Disguise Visible", ["Disable", "Enable"])],
			"Undisguise": [], "SetChatTag": [], "ChatColor": [], "SetNameColor": [], "SetArrowsStuck": [], "SetStringsStuck": [],
			"SetVisualFire": [Tag("On Fire", ["True", "False"])], "AttackAnimation": [Tag("Animation Arm", ["Swing main arm", "Swing off arm"])],
			"SetStatus": [], "SetSkin": [],
			// Miscellaneous
			"RollBackBlocks": [], "Kick": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "player_action";
	}
}

/// An entity action.
class EntityAction : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			// Statistics
			"Heal": [], "SetHealth": [], "SetAbsorption": [], "SetMaxHealth": [Tag("Heal Mob to Max Health", ["False", "True"])], "Damage": [], "SetFireTicks": [],
			"SetFreezeTicks": [Tag("Ticking Locked", ["Disable", "Enable"])], "SetInvulTicks": [],
			"GivePotion": [Tag("Overwrite Effect", ["True", "False"]), Tag("Effect Particles", ["Regular", "Ambient", "None"])], "RemovePotion": [], 
			"ClearPotions": [], "SetAge": [Tag("Age Lock", ["Don't change", "Enable", "Disable"])], "SetFallDistance": [], "SetCreeperFuse": [],
			"SetCreeperPower": [], "SetCloudRadius": [], "SetVillagerExp": [], "SetWitherInvul": [], "SetHorseJump": [], "SetPickupDelay": [], "SetFishingTime": [],
			"SetWardenAnger": [],
			// Movement
			"Teleport": [Tag("Keep Velocity", ["False", "True"]), Tag("Keep Current Rotation", ["False", "True"])],
			"LaunchUp": [Tag("Add to Current Velocity", ["True", "False"])],
			"LaunchFwd": [Tag("Add to Current Velocity", ["True", "False"]), Tag("Launch Axis", ["Pitch and Yaw", "Yaw Only"])],
			"LaunchToward": [Tag("Add to Current Velocity", ["True", "False"]), Tag("Ignore Distance", ["False", "True"])],
			"RideEntity": [], "SetGliding": [Tag("Gliding", ["Enable", "Disable"])], "BoostElytra": [], "SetGravity": [Tag("Gravity", ["Disable", "Enable"])],
			"SetRotation": [], "SetVelocity": [Tag("Add to Current Velocity", ["False", "True"])], "AttachLead": [],
			// Settings
			"SetName": [Tag("Hide Name Tag", ["False", "True", "Don't Change"])], "SetNameVisible": [Tag("Name Tag Visible", ["Enable", "Disable"])],
			"SetNameColor": [], "SetAI": [Tag("AI", ["None", "Sentient", "Insentient"])], "SetSilenced": [Tag("Silenced", ["Enable", "Disable"])], 
			"SetDeathDrops": [Tag("Has Death Drops", ["Enable", "Disable"])], "SetCollidable": [Tag("Collision", ["Disable", "Enable"])],
			"SetInvulnerable": [Tag("Invulnerable", ["Enable", "Disable"])], "SetMobSitting": [Tag("Is Sitting", ["Enable", "Disable"])],
			"SetBaby": [Tag("Baby", ["Enable", "Disable"])], "SetSize": [], "SetSheepSheared": [Tag("Sheared", ["Enable", "Disable"])],
			"SetSaddle": [Tag("Saddle", ["Enable", "Disable"])], "SetCarryingChest": [Tag("Carrying Chest", ["Enable", "Disable"])],
			"ArmorStandSlots": [Tag("Interactions", ["Take, swap or place item", "Take or swap item", "Take item", "Place item", "None"]), Tag("Equipment Slot", ["All", "Main hand", "Off hand", "Head", "Chest", "Legs", "Feet"])],
			"SetMarker": [Tag("Marker", ["Enable", "Disable"])], "SetAngry": [Tag("Angry", ["Enable", "Disable"])], 
			"SetRearing": [Tag("Rearing", ["Enable", "Disable"])], "SetRiptiding": [Tag("Riptiding", ["Enable", "Disable"])], 
			"CreeperCharged": [Tag("Charged", ["Enable", "Disable"])], "SetInvisible": [Tag("Invisible", ["Enable", "Disable"])],
			"SetGoatScreaming": [Tag("Screams", ["Enable", "Disable"])], 
			"SetGoatHorns": [Tag("Left Horn", ["Show", "Hide", "No Change"]), Tag("Right Horn", ["Show", "Hide", "No Change"])], "Tame": [], "EndCrystalBeam": [],
			"SetPandaGene": [Tag("Set Gene", ["Main gene", "Hidden gene", "Both"]), Tag("Gene Type", ["Aggressive", "Lazy", "Weak", "Worried", "Playful", "Normal", "Brown"])],
			"SetProfession": [Tag("Profession", ["Armorer", "Unemployed", "Butcher", "Cartographer", "Cleric", "Farmer", "Fisherman", "Fletcher", "Leatherworker", "Librarian", "Mason", "Nitwit", "Shepherd", "Toolsmith", "Weaponsmith"])],
			"SetProjSource": [], "SetPersistent": [Tag("Persistent", ["Enable", "Disable"])],
			// Appearance
			"MobDisguise": [], "PlayerDisguise": [], "BlockDisguise": [], "Undisguise": [], "SetGlowing": [Tag("Glowing", ["Enable", "Disable"])],
			"SetDyeColor": [Tag("Dye", ["White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray", "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"])],
			"SetFishPattern": [Tag("Pattern Color", ["White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray", "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black", "Don't Change"]), Tag("Body Color", ["White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray", "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black", "Don't change"]), Tag("Pattern", ["Kob", "Sunstreak", "Snooper", "Dasher", "Brinely", "Spotty", "Flopper", "Stripey", "Glitter", "Blockfish", "Betty", "Clayfish", "Don't change"])],
			"SetRabbitType": [Tag("Skin Type", ["Brown", "White", "Black", "Black and White", "Gold", "Salt and Pepper", "Killer"])],
			"SetCatType": [Tag("Skin Type", ["Tabby", "Tuxedo", "Red", "Siamese", "British Shorthair", "Calico", "Persian", "Ragdoll", "White", "Jellie", "Black"])],
			"MooshroomType": [Tag("Mooshroom Variant", ["Red", "Brown"])], "SetFoxType": [Tag("Fox Type", ["Red", "Snow"])],
			"SetParrotColor": [Tag("Parrot Color", ["Red", "Blue", "Green", "Cyan", "Gray"])],
			"SetHorsePattern": [Tag("Horse Color", ["Flaxen chestnut", "White", "Buckskin", "Bay", "Black", "Dapple gray", "Dark bay", "Don't change"]), Tag("Horse Markings", ["Stockings and blaze", "No markings", "Paint", "Snowflake appaloosa", "Sooty", "Don't change"])],
			"SetAxolotlColor": [Tag("Axolotl Color", ["Pink", "Brown", "Yellow", "Cyan", "Blue"])],
			"SetLlamaColor": [Tag("Llama Color", ["Brown", "Creamy", "White", "Gray"])], "SetFrogType": [Tag("Frog Type", ["Temperate", "Warm", "cold"])],
			"SetVillagerBiome": [Tag("Biome", ["Desert", "Jungle", "Plains", "Savanna", "Snow", "Swamp", "Taiga"])], 
			"SnowmanPumpkin": [Tag("Pumpkin", ["Disable", "Enable"])], "SetEndermanBlock": [], "SetMinecartBlock": [],
			"ArmorStandParts": [Tag("Arms", ["Enable", "Disable", "Don't change"]), Tag("Base Plate", ["Enable", "Disable", "Don't change"])],
			"SetBeeNectar": [Tag("Has Nectar", ["Enable", "Disable"])], "ProjectileItem": [], "SetVisualFire": [Tag("On Fire", ["True", "False"])],
			"SendAnimation": [Tag("Animation Type", ["Hurt animation", "Crit particles", "Enchanted hit particles"])],
			"ArmorStandPose": [Tag("Armor Stand Part", ["Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"])],
			"SetPose": [Tag("Pose", ["Standing", "Sleeping", "Swimming", "Sneaking"])], "SetFoxLeaping": [Tag("Leaping", ["Enable", "Disable"])],
			"SetArmsRaised": [Tag("Arms Raised", ["Enable", "Disable"])], "SetCatResting": [Tag("Resting", ["Enable", "Disable"])], "SetGlowSquidDark": [],
			// AI
			"SetCelebrating": [Tag("Celebrate", ["Enable", "Disable"])], "SetTarget": [], "MoveToLoc": [], "Jump": [], "Ram": [], "FrogEat": [], "SheepEat": [],
			"IgniteCreeper": [], "Explode": [], "FoxSleeping": [Tag("Sleeping", ["Enable", "Disable"])],
			"SetDragonPhase": [Tag("Phase", ["Flying", "Hovering", "Breath attack", "Dying"])], "SetBulletTarget": [],
			"UseItem": [Tag("Hand", ["Main Hand", "Off Hand"]), Tag("Use Item", ["Enable", "Disable"])], "SetAllayDancing": [Tag("Dancing", ["Enable", "Disable"])],
			// Miscellaneous
			"Remove": [],  "SetEquipment": [Tag("Equipment Slot", ["Main hand", "Off hand", "Head", "Body", "Legs", "Feet", "Saddle", "Horse armor", "Decor"])],
			"SetArmor": [], "LaunchProj": [], "ShearSheep": [], "SetCustomTag": [], "GetCustomTag": [], "RemoveCustomTag": [], "SetItem": [],
			"SetDigging": [Tag("Digging Type", ["Emerge", "Dig Down"])], 
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "entity_action";
	}
}

class GameAction : Action {
	static Tag[][string] _actions;

	static this() {
		auto ignoreCase = Tag("IgnoreCase", ["False", "True"]);
		_actions = [
			// Entity Spawning
			"SpawnMob": [], "SpawnItem": [Tag("Apply Item Motion", ["True", "False"])], "SpawnVehicle": [], "SpawnExpOrb": [], "Explosion": [], "SpawnTNT": [],
			"SpawnFangs": [], "Firework": [Tag("Instant", ["False", "True"]), Tag("Movement", ["Upwards", "Directional"])], "LaunchProj": [], "Lightning": [],
			"SpawnPotionCloud": [], "FallingBlock": [Tag("Reform on Impact", ["True", "False"]), Tag("Hurt Hit Entities", ["False", "True"])],
			"SpawnArmorStand": [Tag("Visibility", ["Visible", "Visible (No hitbox)", "Invisible", "Invisible (No hitbox)"])], 
			"SpawnCrystal": [Tag("Show Bottom", ["True", "False"])], "SpawnEnderEye": [Tag("End of Lifespan", ["Random", "Drop item", "Shatter"])],
			"ShulkerBullet": [],
			// Block Manipulation
			"SetBlock": [], "SetRegion": [], "CloneRegion": [Tag("Ignore Air", ["False", "True"]), Tag("Clone Block Entities", ["True", "False"])],
			"BreakBlock": [], "SetBlockData": [Tag("Overwrite Existing Data", ["False", "True"])], "TickBlock": [], 
			"BoneMeal": [Tag("Show Particles", ["True", "False"])], "SetBlockGrowth": [Tag("Growth Unit", ["Growth Stage Number", "Growth Percentage"])],
			"GenerateTree": [Tag("Tree Type", ["Oak Tree", "Big Oak Tree", "Swamp Tree", "Spruce Tree", "Slightly Taller Spruce Tree", "Big Spruce Tree", "Birch Tree", "Tall Birch Tree", "Jungle Tree", "Big Jungle Tree", "Jungle Bush", "Acacia Tree", "Dark Oak Tree", "Mangrove Tree", "Tall Mangrove Tree","Azalea Tree", "Red Mushroom", "Brown Mushroom", "Crimson Fungus", "Warped Fungus", "Chorus Plant"])],
			"FillContainer": [], "SetContainer": [], "SetItemInSlot": [], "ReplaceItems": [], "RemoveItems": [], "ClearItems": [], "ClearContainer": [],
			"SetContainerName": [], "LockContainer": [], "ChangeSign": [],
			"SignColor": [Tag("Text Color", ["Black", "White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray", "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red"]), Tag("Glowing", ["Disable", "Enable"])],
			"SetHead": [], "SetFurnaceSpeed": [], "SetCampfireItem": [Tag("Campfire Slot", ["1", "2", "3", "4"])], "SetLecternBook": [],
			// Event Manipulation
			"CancelEvent": [], "UncancelEvent": [], "SetEventDamage": [], "SetEventHeal": [], "SetEventXP": [], "SetEventProj": [], "SetEventSound": [],
			// Settings
			"BlockDropsOn": [], "BlockDropsOff": [], 
			"WebRequest": [Tag("Request Method", ["Post", "Get", "Put", "Delete"]), Tag("Content Type", ["text/plain", "application/json"])], "DiscordWebhook": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "game_action";
	}
}

abstract class If : Action {
	bool not;

	override JSONValue toJSON() {
		auto json = super.toJSON();
		if(not)
			json["inverted"] = "NOT";
		return json;
	}
	
	this(JSONValue[] items, TagValue[] tagvs, string action, string target, bool not) {
		super(items, tagvs, action, target);
		this.not = not;
	}

	override int size() {
		return 1;
	}
}

class IfPlayer : If {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			// Toggleable Conditions
			"IsSneaking": [], "IsSprinting": [], "IsGliding": [], "IsFlying": [], "IsGrounded": [], "IsSwimming": [], "IsBlocking": [],
			// Locational Conditions
			"IsLookingAt": [Tag("Fluid Mode", ["Ignore fluids", "Detect fluids"])], "StandingOn": [], 
			"IsNear": [Tag("Shape", ["Sphere", "Circle", "Cube", "Square"])], "InWorldBorder": [],
			// Item Conditions
			"IsHolding": [Tag("Hand Slot", ["Either hand", "Main hand", "Off hand"])], "HasItem": [Tag("Check Mode", ["Has Any Item", "Has All Items"])],
			"IsWearing": [Tag("Check Mode", ["Is Wearing Some", "Is Wearing All"])], "IsUsingItem": [], "NoItemCooldown": [], "HasSlotItem": [],
			"MenuSlotEquals": [], "CursorItem": [], 
			"HasRoomForItem": [Tag("Checked Slots", ["Main inventory", "Entire inventory", "Hotbar", "Armor"]), Tag("Check Mode", ["Has Room for Any Item", "Has Room for All Items"])],
			// Miscellaneous Conditions 
			"NameEquals": [], "SlotEquals": [], 
			"HasPotion": [Tag("Check Properties", ["None", "Amplifier", "Duration", "Amplifier and Duration"]), Tag("Check Mode", ["Has any effect", "Has all effects"])],
			"IsRiding": [Tag("Compare Text To", ["Entity type", "Name or UUID"])],
			"InvOpen": [Tag("Inventory Type", ["Any Inventory", "Plot Menu", "Crafting Table", "Chest", "Double Chest", "Ender Chest", "Shulker Box", "Barrel", "Furnace (any)", "Furnace", "Blast Furnace", "Smoker", "Dropper", "Dispenser", "Beacon", "Hopper", "Anvil", "Brewing Stand", "Cartography Table", "Loom", "Grindstone", "Stonecutter", "Enchanting Table", "Trader Menu (any)", "Villager Menu", "Wandering Trader Menu", "Horse Inventory", "Llama Inventory"])],
			"HasPermission": [Tag("Permission", ["Developer or builder", "Owner", "Developer", "Builder", "Whitelisted"])]
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target, bool not) {
		super(items, tagvs, action, target, not);
	}

	override string block() {
		return "if_player";
	}
}

class IfVar : If {
	static Tag[][string] _actions;

	static this() {
		auto ignoreCase = Tag("IgnoreCase", ["False", "True"]);
		_actions = [
			"=": [], "!=": [], ">": [], ">=": [], "<": [], "<=": [], "InRange": [], "LocIsNear": [Tag("Shape", ["Sphere", "Circle", "Cube", "Square"])],
			"TextMatches": [ignoreCase, Tag("Regular Expressions", ["Disable", "Enable"])], "Contains": [ignoreCase], "StartsWith": [ignoreCase],
			"EndsWith": [ignoreCase], "VarExists": [],
			"ValIsType": [Tag("Variable Type", ["Number", "Text", "Location", "Item", "List", "Potion effect", "Sound", "Particle", "Vector", "Dictionary"])],
			"ItemEquals": [Tag("Comparison Mode", ["Exactly equals", "Ignore stack size", "Ignore durability and stack size", "Material only"])],
			"ItemHasTag": [], "ListContains": [], "ListValueEq": [], "DictHasKey": [], "DictValueEquals": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target, bool not) {
		super(items, tagvs, action, target, not);
	}

	override string block() {
		return "if_var";
	}
}

class IfEntity : If {
	static Tag[][string] _actions;

	static this() {
		auto ignoreCase = Tag("IgnoreCase", ["False", "True"]);
		_actions = [
			"IsType": [], "NameEquals": [], "StandingOn": [], "IsGrounded": [], "IsNear": [Tag("Shape", ["Sphere", "Circle", "Cube", "Square"])],
			"IsRiding": [Tag("Compare Text To", ["Entity type", "Name or UUID"])],
			"HasPotion": [Tag("Check Properties", ["None", "Amplifier", "Duration", "Amplifier and Duration"]), Tag("Check Mode", ["Has any effect", "Has all effects"])],
			"IsMob": [], "IsProj": [], "IsVehicle": [], "IsItem": [], "Exists": [], "HasCustomTag": [], "Is Sheared": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target, bool not) {
		super(items, tagvs, action, target, not);
	}

	override string block() {
		return "if_entity";
	}
}

class SetVar : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			// Variable Setting
			"=": [], "RandomValue": [], 
			"PurgeVars": [Tag("Match Requirement", ["Full word(s) in name", "Entire name", "Any part of name"]), Tag("Ignore Case", ["False", "True"])],
			// Numerical Actions
			"+": [], "-": [], "x": [], "/": [Tag("Division Mode", ["Default", "Floor result"])], "%": [], "+=": [], "-=": [], "Exponent": [], "Root": [],
			"Logarithm": [], "ParseNumber": [], "AbsoluteValue": [], "ClampNumber": [], "WrapNumber": [], "Average": [], 
			"RandomNumber": [Tag("Rounding Mode", ["Whole number", "Decimal number"])], "RoundNumber": [Tag("Round Mode", ["Nearest", "Floor", "Ceiling"])],
			"NormalRandom": [Tag("Distribution", ["Normal", "Folded normal"])], 
			"Sine": [Tag("Sine Variant", ["Sine", "Inverse sine (arcsine)", "Hyperbolic sine"]), Tag("Input", ["Degrees", "Radians"])], 
			"Cosine": [Tag("Cosine Variant", ["Cosine", "Inverse cosine (arccosine)", "Hyperbolic cosine"]), Tag("Input", ["Degrees", "Radians"])], 
			"Tangent": [Tag("Tangent Variant", ["Sine", "Inverse tangent (arctangent)", "Hyperbolic tangent"]), Tag("Input", ["Degrees", "Radians"])],
			"PerlinNoise": [Tag("Fractal Type", ["Brownian", "Billow (Dark edges)", "Rigid (Light edges)"])],
			"VoronoiNoise": [Tag("Cell Edge Type", ["Euclidean", "Manhattan", "Natural"])],
			"WorleyNoise": [Tag("Cell Edge Type", ["Euclidean", "Manhattan", "Natural"]), Tag("Distance Calculation", ["Primary", "Secondary", "Additive", "Subtractive", "Multiplicative", "Divisive"])],
			"Bitwise": [Tag("Operator", ["|", "&", "~", "^", "<<", ">>", ">>>"])],
			// Text Manipulation
			"Text": [Tag("Text Value Merging", ["No spaces", "Add spaces"])], 
			"ReplaceText": [Tag("Replacement Type", ["All occurrences", "First occurrence"]), Tag("Regular Expressions", ["Disable", "Enable"])],
			"RemoveText": [Tag("Regular Expressions", ["Disable", "Enable"])], "TrimText": [], "SplitText": [], "JoinText": [],
			"SetCase": [Tag("Capitalization Type", ["UPPERCASE", "lowercase", "Proper Case", "iNVERT CASE", "RAnDoM cASe"])],
			"TranslateColors": [Tag("Translation Type", ["From & to color", "From hex to color", "From color to &", "Strip color"])],
			"TextLength": [], "RepeatText": [], 
			"Format Time": [Tag("Format", ["2020/08/17 17:20:54", "Custom", "2020/08/17", "Mon, August 17", "Monday", "17:20:54", "5:20 PM", "17h20m54s", "54.229 seconds"])], // why??
			// Location manipulation
			"GetCoord": [Tag("Coordinate Type", ["Plot coordinate", "World coordinate"]), Tag("Coordinate", ["X", "Y", "Z", "Pitch", "Yaw"])],
			"SetCoord": [Tag("Coordinate Type", ["Plot coordinate", "World coordinate"]), Tag("Coordinate", ["X", "Y", "Z", "Pitch", "Yaw"])],
			"SetAllCoords": [Tag("Coordinate Type", ["Plot coordinate", "World coordinate"])],
			"ShiftOnAxis": [Tag("Coordinate", ["X", "Y", "Z"])],
			"ShiftAllAxes": [], "ShiftInDirection": [Tag("Direction", ["Forward", "Upward", "Sideways"])], "ShiftAllDirections": [], "ShiftToward": [],
			"ShiftOnVector": [Tag("Add Location Rotation", ["False", "True"])], "GetDirection": [], "SetDirection": [], 
			"ShiftRotation": [Tag("Rotation Axis", ["Pitch", "Yaw"])], "FaceLocation": [Tag("Face Direction", ["Toward location", "Away from location"])],
			"AlignLoc": [Tag("Rotation", ["Keep rotation", "Remove rotation"]), Tag("Coordinates", ["All coordinates", "X and Z", "Only Y"]), Tag("Alignment Mode", ["Block center", "Lower block corner"])],
			"Distance": [Tag("Distance Type", ["Distance 3D (X/Y/Z)", "Distance 2D (X/Z)", "Altitude (Y)"])], "GetCenterLoc": [], "RandomLoc": [],
			// Item Manipulation
			"GetItemType": [Tag("Return Value Type", ["Item ID (golden_apple)", "Item Name (Golden Apple)", "Item"])], "SetItemType": [], "GetItemName": [],
			"SetItemName": [], "GetItemLore": [], "GetItemLoreLine": [], "SetItemLore": [], "GetItemAmount": [], "SetItemAmount": [], "GetMaxItemAmount": [],
			"GetItemDura": [Tag("Durability Type", ["Get Damage", "Get Damage Percentage", "Get Remaining", "Get Remaining Percentage", "Get Maximum"])],
			"SetItemDura": [Tag("Durability Type", ["Set Damage", "Set Damage Percentage", "Set Remaining", "Set Remaining Percentage"])],
			"SetBreakability": [Tag("Breakability", ["Unbreakable", "Breakable"])], "GetItemEnchants": [], "SetItemEnchants": [], "AddItemEnchant": [],
			"RemItemEnchant": [], "GetHeadOwner": [Tag("Text Value", ["Owner Name", "Owner UUID"])], "SetHeadTexture": [], "GetBookText": [], "SetBooKText": [],
			"GetItemTag": [], "SetItemTag": [], "GetAllItemTags": [], "RemoveItemTag": [], "SetModelData": [], "GetItemEffects": [], "SetItemEffects": [],
			"SetItemFlags": [Tag("Hide Color", ["No Change", "True", "False"]),Tag("Hide Enchantments", ["No Change", "True", "False"]),Tag("Hide Attributes", ["No Change", "True", "False"]),Tag("Hide Unbreakable", ["No Change", "True", "False"]),Tag("Hide Can Destroy", ["No Change", "True", "False"]),Tag("Hide Can Place On", ["No Change", "True", "False"]),Tag("Hide Potion Effects", ["No Change", "True", "False"])],
			"SetCanPlaceOn": [], "SetCanDestroy": [], "GetItemRarity": [], "GetLodestoneLoc": [], 
			"SetLodestoneLoc": [Tag("Require Lodestone at Location", ["False", "True"])], "GetItemColor": [], "SetItemColor": [],
			"GetItemAttribute": [Tag("Attribute", ["Armor", "Armor toughness", "Attack damage", "Attack speed", "Maximum health", "Knockback resistance", "Movement speed", "Follow range"]), Tag("Active Equipment Slot", ["Any", "Main hand", "Off hand", "Head", "Body", "Legs", "Feet"])],
			"AddItemAttribute": [Tag("Attribute", ["Armor", "Armor toughness", "Attack damage", "Attack speed", "Maximum health", "Knockback resistance", "Movement speed", "Follow range"]), Tag("Operation", ["Add number", "Add percentage to base", "Multiply modifier by percentage"]), Tag("Active Equipment Slot", ["Main hand", "Any", "Off hand", "Head", "Body", "Legs", "Feet"])],
			"SetMapTexture": [],
			// List Manipulation
			"CreateList": [], "AppendValue": [], "AppendList": [], "GetListValue": [], "SetListValue": [], 
			"GetValueIndex": [Tag("Search Order", ["Ascending (first index)", "Descending (last index)"])], "InsertListValue": [], "RemoveListValue": [],
			"RemoveListIndex": [], "TrimList": [], "SortList": [Tag("Sort Order", ["Ascending", "Descending"])], "ReverseList": [], "RandomizeList": [],
			// Dictionary Manipulation
			"CreateDict": [], "SetDictValue": [], "GetDictValue": [], "GetDictSize": [], "RemoveDictEntry": [], "GetDictKeys": [], "ClearDict": [],
			"GetDictValues": [], "AppendDict": [], 
			"SortDict": [Tag("Sorting Type", ["Sort by Key", "Sort by Value"]), Tag("Sorting Order", ["Ascending", "Descending"])],
			// TODO: Particle Manipulation
			// World Actions
			"GetBlockType": [Tag("Return Value Type", ["Block ID (oak_log)", "Block name (Oak Log)", "Item"])], "GetBlockData": [],
			"GetAllBlockData": [Tag("Hide Default", ["True", "False"])], "GetBlockGrowth": [Tag("Growth Unit", ["Growth stage number", "Growth percentage"])],
			"GetBlockPower": [], "GetLight": [Tag("Light Type", ["Combined light", "Sky light", "Block light"])], 
			"GetSignText": [Tag("Sign Line", ["1", "2", "3", "4", "All lines"])], "GetContainerName": [], "ContainerLock": [],
			"GetContainerItems": [Tag("Ignore Empty Slots", ["False", "True"])], "GetLecternBook": [], "GetLecternPage": [],
			"Raycast": [Tag("Entity Collision", ["False", "True"]), Tag("Block Collision", ["All blocks", "Non-fluid blocks", "Solid blocks", "None"])],
			// Miscellaneous Actions
			"GetPotionType": [], "SetPotionType": [], "GetPotionAmp": [], "SetPotionAmp": [], "GetPotionDur": [], "SetPotionDur": [], "GetSoundType": [],
			"SetSoundType": [], "SetSoundVariant": [], "GetSoundPitch": [Tag("Return Value Type", ["Pitch (number)", "Note (text)"])], "SetSoundPitch": [],
			"GetSoundVolume": [], "SetSoundVolume": [], "RGBColor": [], "HSBColor": [], "HSLColor": [],
			"GetColorChannels": [Tag("Color Channels", ["RGB", "HSB", "HSL"])],
			// Vector Manipulation
			"Vector": [], "VectorBetween": [], "GetVectorComp": [Tag("Component", ["X", "Y", "Z"])], "SetVectorComp": [Tag("Component", ["X", "Y", "Z"])],
			"GetVectorLength": [Tag("Length Type", ["Length", "Length Squared"])], "SetVectorLength": [], "MultiplyVector": [], "AddVectors": [],
			"SubtractVectors": [], "AlignVectors": [], "RotateAroundAxis": [Tag("Axis", ["X", "Y", "Z"]), Tag("Angle Units", ["Degrees", "Radians"])],
			"ReflectVector": [], "CrossProduct": [], "DotProduct": [], "DirectionName": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "set_var";
	}
}

class Control : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			"Wait": [Tag("Time Unit", ["Ticks", "Seconds", "Minutes"])], "Return": [], "End": [], "Skip": [], "StopRepeat": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "control";
	}
}

class Repeat : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			"Forever": [], "Multiple": [], "Range": [], "ForEach": [Tag("Allow List Changes", ["True", "False (copy list)"])], "ForEachEntry": [],
			"Grid": [], 
			"Adjacent": [Tag("Change Location Rotation", ["False", "True"]), Tag("Include Origin Block", ["False", "True"]), Tag("Pattern", ["Adjacent (6 blocks)", "Cardinal (4 blocks)", "Square (8 blocks)", "Cube (26 blocks)"])],
			"Path": [Tag("Rotate Location", ["False", "True"])], "Sphere": [Tag("Point Locations Inwards", ["False", "True"])]
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "repeat";
	}
}

class IfGame : If {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			"BlockEquals": [], "BlockPowered": [Tag("Redstone Power Mode", ["Direct power", "Indirect power"])], "ContainerHas": [], "ContainerHasAll": [],
			"HasRoomForItem": [Tag("Check Mode", ["Has Room for Any Item", "Has Room for All Items"])],
			"SignHasTxt": [Tag("Check Mode", ["Contains", "Equals"]), Tag("Sign Line", ["1", "2", "3", "4", "All lines"])], "HasPlayer": [], "EventBlockEquals": [],
			"EventItemEquals": [Tag("Comparison Mode", ["Exactly equals", "Ignore stack size/durability", "Material only"])],
			"CommandEquals": [Tag("Ignore Case", ["True", "False"]), Tag("Check Mode", ["Check entire command", "Check beginning"])],
			"CmdArgEquals": [Tag("Ignore Case", ["True", "False"])], "AttackIsCrit": [], "EventCancelled": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target, bool not) {
		super(items, tagvs, action, target, not);
	}

	override string block() {
		return "if_game";
	}
}

class SelectObject : Action {
	static Tag[][string] _actions;

	static this() {
		_actions = [
			// Creating Selections
			"EventTarget": [Tag("Event Target", ["Default", "Killer", "Damager", "Victim", "Shooter", "Projectile"])], "RandomPlayer": [], "LastEntity": [],
			"PlayerName": [], "Entity Name": [], "AllPlayers": [], "AllEntities": [], "Invert": [],
			// Selection Filters
			"FilterDistance": [Tag("Ignore Y-Axis", ["False", "True"]), Tag("Compare Mode", ["Nearest", "Farthest"])], 
			"FilterSort": [Tag("Sort Order", ["Ascending", "Descending"])], 
			"FilterRay": [Tag("Block Collision", ["Solid Blocks", "All blocks", "Non-fluid blocks", "None"])], "Reset": []
		];
	}

	override Tag[][string] actions() { return _actions; }

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "select_obj";
	}
}

/// A block with a subaction
class SubAction : CodeBlock {
	string block;
	string subAction;
	string action;
	string subIf;
	bool not;
	JSONValue[] items;
	
	Tag[][string] actions() {
		final switch(subIf) {
			case "IF_ENTITY":
				return IfEntity._actions;
			case "IF_PLAYER":
				return IfPlayer._actions;
			case "IF_VAR":
				return IfVar._actions;
			case "IF_GAME":
				return IfGame._actions;
		}
	}

	this(JSONValue[] items, TagValue[] tagvs, string block, string action, string subAction, string subIf, bool not) {
		this.block = block;
		this.action = action;
		this.subAction = subAction;
		this.subIf = subIf;
		this.items = items;
		this.not = not;
		validateTags(this, "block", block, subAction, tagvs, actions[subAction]); 
	}

	JSONValue toJSON() {
		auto v = JSONValue([
			"id": "block",
			"block": block,
			"action": action,
			"subAction": subAction
		]);
		v["args"] = ["items": items];
		if(not)
			v["inverted"] = "NOT";
		return v;
	}

	int size() {
		return block == "repeat" ? 1 : 2;
	}

}

// TODO: repeat while, select object by conditions, filter selection by conditions
//       ^ all of these should probably have a common superclass
