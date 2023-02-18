module codeblock;

import std.json, std.algorithm, std.string;

import compiler;

/// A codeblock inside a declaration
interface CodeBlock {
	JSONValue toJSON(); /// Convert this codeblock to json
}

struct TagValue {
	string name;
	string option;
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
}

/// Represents actions and setvars
abstract class Action : CodeBlock {	
	JSONValue[] items;
	
	/// Represents a tag
	struct Tag {
		string name;
		string[] options;
		bool opEquals(string s) {
			return s == name;
		}
	}

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
		bool[string] found; // tags that have been found 
	 	// find largest slot (important for detecting value/tag overlap)
		int slot = 0;
		foreach(i; items) {
			int s = cast(int)(i["slot"].integer);
			if(s > slot)
				slot = s;
		}
		// make sure all tags are present and valid
		foreach(t; tagvs) {
			if(!tags.canFind(t.name))
				throw new CompilerException("Invalid tag '"~t.name~"' for action '"~action~"'.");
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
			this.items ~= o;
		}
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

class IfPlayer : Action {
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

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "if_player";
	}
}

class IfVar : Action {
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

	this(JSONValue[] items, TagValue[] tagvs, string action, string target) {
		super(items, tagvs, action, target);
	}

	override string block() {
		return "if_var";
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
			// TODO: Item Manipulation
			// List Manipulation
			"CreateList": [], "AppendValue": [], "AppendList": [], "GetListValue": [], "SetListValue": [], 
			"GetValueIndex": [Tag("Search Order", ["Ascending (first index)", "Descending (last index)"])], "InsertListValue": [], "RemoveListValue": [],
			"RemoveListIndex": [], "TrimList": [], "SortList": [Tag("Sort Order", ["Ascending", "Descending"])], "ReverseList": [], "RandomizeList": [],
			// TODO: all the other setvars
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
