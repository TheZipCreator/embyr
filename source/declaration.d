module declaration;

import std.json, std.algorithm;

import compiler : CompilerException, emptyObject, emptyArray;
import codeblock;

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
