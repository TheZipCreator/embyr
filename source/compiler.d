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

/// Find the position of of a given ParseTree
FilePos pos(ParseTree pt) {
	size_t line;
	size_t col;
	for(size_t i = pt.end; i > 0; i--) {
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
				// TODO: make sure game value is valid
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
				case "Embyr.PlayerActionBlock": {
					add!PlayerAction();
					break;
				}
				case "Embyr.IfPlayerBlock": {
					add!IfPlayer();
					break;
				}
				case "Embyr.IfVarBlock": {
					add!IfVar();
					break;
				}
				case "Embyr.SetVarBlock": {
					add!SetVar();
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
	Declaration[] decls;
	pt = pt[0]; // get the Embyr.Program
	foreach(decl; pt) {
		decl = decl[0];
		try {
			final switch(decl.name) {
				case "Embyr.PlayerEventDecl":
					decls ~= new PlayerEvent(parseBlocks(decl[1]), decl[0].matches[0]);
					break;
			}
		} catch(CompilerException e)
			throw new CompilerException(e, decl.pos);
	}
	return decls;
}
