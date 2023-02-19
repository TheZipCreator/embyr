module compiler;

import std.json, std.conv, std.algorithm;
import std.typecons : Tuple, tuple;

import pegged.grammar;

import declaration, codeblock;

/// Create an empty JSON object (why this isn't in std.json is beyond me)
@property JSONValue emptyObject() {
	return JSONValue(string[string].init);
}
/// Create an empty JSON array
@property JSONValue emptyArray() {
	return JSONValue(string[].init);
}

/// Position in a file
struct FilePos {
	string filename;
	size_t line;
	size_t col;
}

/// Thrown when an error happens in compilation
class CompilerException : Exception {
	bool hasPos = false;
	this(string msg, FilePos p) {
		super(p.filename~":"~p.line.to!string~":"~p.col.to!string~": "~msg);
		hasPos = true;
	}
	this(CompilerException e, lazy FilePos p) {
		if(e.hasPos)
			super(e.msg);
		else
			super(p.filename~":"~p.line.to!string~":"~p.col.to!string~": "~e.msg);
		hasPos = true;
	}
	this(string msg) {
		super(msg);
	}
}

bool addtags;

/// List of all valid targets
static immutable string[] targets = [
	"", "Selection", "Default", "Killer", "Damager", "Victim", "Shooter", "Projectile", "LastEntity", "AllPlayers"
];

private:

// this is a hack FIXME
string filename;
string filetext;

static immutable gameValues = [
	// Statistical Values
	"Current Health", "Maximum Health", "Absorption Health", "Food Level", "Food Saturation", "Food Exhaustion", "Attack Damage", "Attack Speed",
	"Armor Points", "Armor Toughness", "Invulnerability Ticks", "Experience Level", "Experience Progress", "Fire Ticks", "Freeze Ticks", "Remaining Air",
	"Fall Distance", "Held Slot", "Ping", "Steer Sideways Movement", "Steer Forward Movement",
	// Locational Values
	"Location", "Target Block Location", "Target Block Side", "Eye Location", "X-Coordinate", "Y-Coordinate", "Z-Coordinate", "Pitch", "Yaw",
	"Spawn Location", "Velocity", "Direction",
	// Item Values
	"Main Hand Item", "Off Hand Item", "Armor Items", "Hotbar Items", "Inventory Items", "Cursor Item", "Inventory Menu Items", "Saddle Item", "Entity Item",
	// Informational Values
	"Name", "UUID", "Entity Type", "Open Inventory Title", "Potion Effects", "Vehicle", "Passengers", "Lead Holder", "Attached Leads",
	// Event Values
	"Event Block Location", "Event Block Side", "Event Damage", "Damage Event Cause", "Event Death Message", "Event Heal Amount", "Heal Event Cause",
	"Event Power", "Event Command", "Event Command Arguments", "Event Item", "Event Hotbar Slot", "Event Clicked Slot Index", "Event Clicked Slot Item",
	"Event Clicked Slot New Item", "Close Inventory Event Cause", "Inventory Event Click Type", "Fish Event Cause",
	// Plot Values
	"Player Count", "CPU Usage", "Server TPS", "Timestamp", "Selection Size", "Selection Size", "Selection Target Names", "Selection Target UUIDs"
];

struct Definitions {
	ParseTree[string] definitions;

	ParseTree opIndex(string k) {
		if(k !in definitions)
			throw new CompilerException("Unknown definition '"~k~"'.");
		return definitions[k];
	}

	void opIndexAssign(ParseTree v, string k) {
		if(k in definitions)
			throw new CompilerException("Duplicate definition '"~k~"'.");
		definitions[k] = v;
	}
}
Definitions definitions;

/// Find the position of of a given ParseTree
FilePos pos(ParseTree pt) {
	size_t line;
	size_t col;
	for(size_t i = pt.end-1; i > 0; i--) {
		col++;
		if(filetext[i] == '\n') {
			col = 0;
			line++;
		}
	}
	return FilePos(filename, line, col);
}

/// Parse a string
string parseString(ParseTree pt) {
	pt = pt[0];
	final switch(pt.name) {
		case "Embyr.RawString":
			return pt.matches[0][1..$-1];
		case "Embyr.NormalString": {
			string s = "";
			foreach(e; pt) {
				final switch(e.name) {
					case "Embyr.CharSeq":
						s ~= e.matches[0];
						break;
					case "Embyr.EscapeSequence":
						final switch(e.matches[0][1]) {
							case 'n':
								s ~= '\n';
								break;
							case 'r':
								s ~= '\r';
								break;
							case 't':
								s ~= '\t';
								break;
							case '\\':
								s ~= '\\';
								break;
							case '"':
								s ~= '"';
								break;
							case '&':
								s ~= '§';
								break;
						}
				}
			}
			return s;
		}
	}
}

/// Parse a number
float parseNum(ParseTree pt) {
	return pt.matches[0].to!float;
}

/// Parse a list of values into items
Tuple!(JSONValue[], TagValue[]) parseValues(ParseTree pt) {
	JSONValue[] ret;
	TagValue[] tags;
	int slot = 0;
	void addItem(T...)(string id, T items) {
		auto item = emptyObject;
		item["data"] = emptyObject;
		foreach(i; items) {
			foreach(k, v; i)
				item["data"][k] = v;
		}
		item["id"] = id;
		auto o = emptyObject;
		o["item"] = item;
		o["slot"] = slot++;
		if(slot > 26)
			throw new CompilerException("Too many items in code block.");
		ret ~= o;
	}
	foreach(v; pt) {
		start:
		v = v[0];
		final switch(v.name) {
			case "Embyr.NumValue":
			case "Embyr.TxtValue": {
				addItem(v.name == "Embyr.TxtValue" ? "txt" : "num", ["name": parseString(v[0])]);
				break;
			}
			case "Embyr.LocValue": {
				addItem("loc", [
					"isBlock": false, // don't really know what this does
				], [
					"loc": [
						"x": parseNum(v[0]),
						"y": parseNum(v[1]),
						"z": parseNum(v[2]),
						"pitch": v.children.length > 3 ? parseNum(v[3]) : 0,
						"yaw": v.children.length > 3 ? parseNum(v[4]) : 0
					]
				]);
				break;
			}
			case "Embyr.VecValue": {
				addItem("vec", [
					"x": parseNum(v[0]),
					"y": parseNum(v[1]),
					"z": parseNum(v[2])
				]);
				break;
			}
			case "Embyr.SndValue": {
				addItem("snd", [
					"pitch": parseNum(v[1]),
					"vol": parseNum(v[2])
				], [
					"sound": parseString(v[0])
				]);
				break;
			}
			case "Embyr.PotValue": {
				addItem("pot", [
					"amp": parseNum(v[1]),
					"dur": parseNum(v[2])
				], [
					"pot": parseString(v[0])
				]);
				break;
			}
			case "Embyr.VarValue": {
				string type = "unsaved";
				if(v.children.length > 1) {
					final switch(v[1].matches[0]) {
						case "g":
							type = "unsvaed";
							break;
						case "s":
							type = "saved";
							break;
						case "l":
							type = "local";
							break;
					}
				}
				addItem("var", [
					"name": parseString(v[0]),
					"scope": type
				]);
				break;
			}
			case "Embyr.GameValue": {
				string target = "Default";
				if(v.children.length > 1) {
					target = parseString(v[1]);
					if(!targets.canFind(target))
						throw new CompilerException("Invalid target '"~target~"'.");
				}
				string name = parseString(v[0]);
				if(!gameValues.canFind(name))
					throw new CompilerException("Unknown game value '"~name~"'.");
				addItem("g_val", [
					"target": target,
					"type": parseString(v[0])
				]);
				break;
			}
			case "Embyr.ItemValue": {
				addItem("item", [
					"item": v[0].matches[0]
				]);
				break;
			}
			case "Embyr.TagValue": {
				tags ~= TagValue(parseString(v[0]), parseString(v[1]));
				break;
			}
			
			case "Embyr.Identifier": {
				v = definitions[v.matches[0]];
				goto start; // I feel like there's a better way to do this, but this is simplest.
			}
		}
	}
	return tuple(ret, tags);
}

CodeBlock[] parseBlocks(ParseTree pt) {
	CodeBlock[] res;
	foreach(b; pt) {
		b = b[0];
		try {
			void add(T)() {
				auto vals = parseValues(b[2]);
				string target = "";
				if(b[0].name != "eps")
					target = b[0].matches[0];
				res ~= new T(vals[0], vals[1], b[1].matches[0], target);
			}
			final switch(b.name) {
				case "Embyr.PlayerActionBlock":
					add!PlayerAction();
					break;
				case "Embyr.IfPlayerBlock":
					add!IfPlayer();
					break;
				case "Embyr.IfVarBlock":
					add!IfVar();
					break;
				case "Embyr.IfGameBlock":
					add!IfVar();
					break;
				case "Embyr.SetVarBlock":
					add!SetVar();
					break;
				case "Embyr.ControlBlock":
					add!Control();
					break;
				case "Embyr.GameActionBlock":
					add!GameAction();
					break;
				case "Embyr.RepeatBlock":
					add!GameAction();
					break;
					// TODO: Repeat while
				case "Embyr.CallFuncBlock": {
					res ~= new CallFunction(b[0].matches[0]);
					break;
				}
				case "Embyr.StartProcessBlock": {
					auto vals = parseValues(b[1]);
					res ~= new StartProcess(vals[0], vals[1], b[0].matches[0]);
					break;
				}
				case "Embyr.LeftPiston": {
					res ~= new Piston(false, false);
					break;
				}
				case "Embyr.RightPiston": {
					res ~= new Piston(true, false);
					break;
				}
				case "Embyr.LeftRepeatPiston": {
					res ~= new Piston(false, true);
					break;
				}
				case "Embyr.RightRepeatPiston": {
					res ~= new Piston(true, true);
					break;
				}

				case "Embyr.Definition": {
					definitions[b.matches[0]] = b[1];
					break;
				}
			}
		} catch(CompilerException e)
			throw new CompilerException(e, pos(b));
	}
	return res;
}

/// Compile a parsetree into an array of Declarations
public Declaration[] compile(string filename_, string filetext_, ParseTree pt, bool addtags_) {
	filename = filename_;
	filetext = filetext_;
	addtags = addtags_;
	definitions = Definitions();
	Declaration[] decls;
	pt = pt[0]; // get the Embyr.Program
	foreach(decl; pt) {
		decl = decl[0];
		try {
			final switch(decl.name) {
				case "Embyr.PlayerEventDecl": {
					auto blocks = decl.children.length > 1 ? parseBlocks(decl[1]) : [];
					decls ~= new PlayerEvent(blocks, decl[0].matches[0]);
					break;
				}
				case "Embyr.FunctionDecl": {
					auto blocks = decl.children.length > 2 ? parseBlocks(decl[2]) : [];
					auto vals = parseValues(decl[1]);
					decls ~= new Function(blocks, vals[0], vals[1], decl[0].matches[0]);
					break;
				}
				case "Embyr.ProcessDecl": {
					auto blocks = decl.children.length > 2 ? parseBlocks(decl[2]) : [];
					auto vals = parseValues(decl[1]);
					decls ~= new Process(blocks, vals[0], vals[1], decl[0].matches[0]);
					break;
				}

				case "Embyr.Definition": {
					definitions[decl.matches[0]] = decl[1];
					break;
				}
			}
		} catch(CompilerException e)
			throw new CompilerException(e, decl.pos);
	}
	return decls;
}
