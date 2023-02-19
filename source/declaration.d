module declaration;

import std.json, std.algorithm;

import compiler, codeblock;

/// General class for player events, entity events, functions, etc.
abstract class Declaration {
	JSONValue start; /// The block that begins this declaration
	CodeBlock[] blocks; /// A list of code blocks within this declaration
	string name; /// Name of this declaration
	
	this(CodeBlock[] blocks) {
		this.blocks = blocks;
		start = emptyObject;
	}
	
	/// Convert this declaration to json
	JSONValue toJSON() {
		auto v = [start];
		foreach(b; blocks)
			v ~= b.toJSON();
		return JSONValue(["blocks": v]);
	}

	/// Get the total size of this declaration
	int size() {
		return blocks.fold!"a+b.size"(0)+2;
	}
}

/// Player events
class PlayerEvent : Declaration {
	/// List of valid player events
	static immutable string[] playerEvents = [
		// the event names are so inconsistent, I hate it.

		// Plot and Server Events
		"Join", "Leave", "Command",
		// Click Events
		"RightClick", "LeftClick", "ClickEntity", "ClickPlayer", "PlaceBlock", "BreakBlock", "SwapHands", "ChangeSlot",
		// Movement Events
		"Walk", "Jump", "Sneak", "Unsneak", "StartSprint", "StopSprint", "StartFlight", "StopFlight", "Riptide", "Dismount", "HorseJump", "VehicleJump",
		// Item Events
		"ClickMenuSlot", "ClickInvSlot", "PickupItem", "DropItem", "Consume", "BreakItem", "CloseInv", "Fish",
		// Damage Events
		"PlayerTakeDmg", "PlayerDmgPlayer", "DamageEntity", "EntityDmgPlayer", "PlayerHeal", "ShootBow", "ShootProjectile", "ProjHit", "ProjDmgPlayer", "CloudImbuePlayer",
		// Death Event
		"Death", "KillPlayer", "KillMob", "MobKillPlayer", "Respawn"
	];

	this(CodeBlock[] blocks, string evtname) {
		super(blocks);
		if(!playerEvents.canFind(evtname))
			throw new CompilerException("Invalid player event '"~evtname~"'.");
		start["action"] = evtname;
		start["args"] = ["items": emptyArray];
		start["block"] = "event";
		start["id"] = "block";
		name = "Player Event "~evtname;
	}
}

/// Entity events
class EntityEvent : Declaration {
	/// List of valid entity events
	static immutable string[] entityEvents = [
		"EntityDmgEntity", "EntityKillEntity", "EntityDmg", "ProjDmgEntity", "ProjKillEntity", "EntityDeath", "VehicleDamage", "BlockFall", "FallingBlockLand"
	];

	this(CodeBlock[] blocks, string evtname) {
		super(blocks);
		if(!entityEvents.canFind(evtname))
			throw new CompilerException("Invalid player event '"~evtname~"'.");
		start["action"] = evtname;
		start["args"] = ["items": emptyArray];
		start["block"] = "entity_event";
		start["id"] = "block";
		name = "Entity Event "~evtname;
	}
}

/// Declarations with arguments
abstract class ArgDeclaration : Declaration {
	JSONValue[] items;
	string data;

	string block() { return ""; }

	Tag[] tags() { return []; }
	
	this(CodeBlock[] blocks, JSONValue[] items, TagValue[] tagvs, string data) {
		super(blocks);
		this.items = items;
		this.name = name;
		validateTags(this, "declaration '"~data~"'", block, "dynamic", tagvs, tags);
		start["id"] = "block";
		start["data"] = data;
		start["block"] = block;
		start["args"] = ["items": this.items];
	}
}

/// Function declaration
class Function : ArgDeclaration {
	this(CodeBlock[] blocks, JSONValue[] items, TagValue[] tagvs, string data) {
		super(blocks, items, tagvs, data);
		name = "Function "~data;
	}

	override string block() { return "func"; }

	static _tags = [
		Tag("Is Hidden", ["False", "True"])
	];

	override Tag[] tags() {
		return _tags;	
	}
}

/// Process declaration
class Process : ArgDeclaration {
	this(CodeBlock[] blocks, JSONValue[] items, TagValue[] tagvs, string data) {
		super(blocks, items, tagvs, data);
		name = "Process "~data;
	}

	override string block() { return "process"; }

	static _tags = [
		Tag("Is Hidden", ["False", "True"])
	];

	override Tag[] tags() {
		return _tags;	
	}
}
