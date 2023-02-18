module app;

import std.stdio, std.getopt, std.file, std.json, std.base64, std.zlib, std.format, std.conv;

import peg, compiler, declaration;

enum VERSION = "0.1.0";

int main(string[] args) {
	enum Format {
		chest, json, base64, hotbar
	}
	struct Flags {
		Format fmt;
		bool ast;
		string output;
		bool addtags;
	}
	Flags flags;
	try {
		auto opt = getopt(args,
			"ast", "Print AST to stdout and don't compile.", &flags.ast,
			"f|format", "Output format. Valid options are: \n\tchest - Outputs a command that creates a chest above the executor containing all generated code templates.\n\tjson - Outputs a json file containing an array where each element is each generated pattern\n\tbase64 - Generates a base64-encoded version of the json.\n\thotbar - Generates a hotbar.dat file containing all generated templates that can be placed within your .minecraft folder.", &flags.fmt,
			"o|output", "Output file.", &flags.output,
			"t|addtags", "Automatically insert tags when required. If this is off, not having a required tag will cause an error.", &flags.addtags
		);
		if(opt.helpWanted) {
			writeln("Embyr Compiler V"~VERSION);
			defaultGetoptPrinter("Options:", opt.options);
			writeln(`Exit codes:
1 - No output files
2 - No input files
3 - Error opening files
4 - Parsing error
5 - Compilation Error
6 - Argument Error`);
			return 0;
		}
	} catch(GetOptException e) {
		stderr.writeln("Argument Error: ", e.msg);
		return 6;
	} catch(ConvException e) {
		stderr.writeln("Argument Error: ", e.msg);
		return 6;
	}
	string[] inputs = args[1..$];
	if(flags.output == string.init && !flags.ast) {
		stderr.writeln("Fatal Error: No output files.");
		return 1;
	}
	string output = flags.output;
	if(inputs.length == 0) {
		stderr.writeln("Error: No input files.");
		return 2;
	}
	foreach(i; inputs) {
		try {
			string text = readText(i);
			auto ast = Embyr(text);
			if(flags.ast) {
				writeln(i~":");
				writeln(ast);
				continue;
			}
			if(!ast.successful) {
				stderr.writeln("Error parsing file '"~i~"': ", ast.failMsg); // TODO: use better fail message
				return 4;
			}
			auto decls = compile(i, text, ast, flags.addtags);
			string base64(Declaration d) {
				auto compressor = new Compress(6, HeaderFormat.gzip);
				return Base64.encode((cast(ubyte[])compressor.compress(d.toJSON().toString()))~(cast(ubyte[])compressor.flush()));
			}
			final switch(flags.fmt) {
				case Format.json:
					JSONValue[] json;
					foreach(d; decls)
						json ~= d.toJSON();
					std.file.write(output, JSONValue(json).toPrettyString());
					break;
				case Format.base64: {
					string ret = "";
					foreach(d; decls) {
						ret ~= d.name~":\n"~base64(d)~"\n";
					}
					std.file.write(output, ret);
					break;
				}
				case Format.chest: {
					// can't use std.json here because nbt json is a bit different than normal json
					string command = `
/setblock ~ ~1 ~ minecraft:chest{
	"Items": [
`;
					int slot = 0;
					foreach(j, d; decls) {
						if(j != 0)
							command ~= `,`;
						command ~= `
{
	"Slot": %db,
	"id": "minecraft:ender_chest",
	"Count": 1b,
	"tag": {
		"PublicBukkitValues": {
			"hypercube:codetemplatedata": "{\"author\":\"Embyr Compiler\",\"name\":\"%s\",\"version\":1,\"code\":\"%s\"}"
		},
		"display": {
			"Name": "{\"text\":\"%s\"}"
		}
	}
}
							`.format(slot, d.name, base64(d), d.name);
					}
					command ~= `]}`;
					std.file.write(output, command);
					break;
				}
				case Format.hotbar: {
					import sel.nbt, std.system : Endian;
					// this is probably not the best way to do it but it'll work
					Compound[] items;
					foreach(d; decls) {
						items ~= new Compound(
							new Named!Int("Count", 1),
							new Named!String("id", "minecraft:ender_chest"),
							new Named!Compound("tag",
								new Named!Compound("display", 
									new Named!String("Name", `{"text":"`~d.name~`"}`)
								),
								new Named!Compound("PublicBukkitValues",
									new Named!String("hypercube:codetemplatedata", `{"author":"Embyr Compiler","name":"`~d.name~`","version":1,"code":"`~base64(d)~`"}`)
								)
							)
						);
					}
					Tag[9][9] grid;
					for(int j = 0; j < 9; j++) {
						for(int k = 0; k < 9; k++) {
							size_t idx = j*9+k;
							if(idx >= items.length) {
								grid[j][k] = new Compound(
									new Named!Int("Count, 1"),
									new Named!String("id", "minecraft:air")
								);
								continue;
							}
							grid[j][k] = items[idx];
						}
					}
					auto res = new Compound();
					foreach(j, g; grid) {
						List l = new List(g);
						res[j.to!string] = l;
					}
					res["DataVersion"] = new Int(3218); // not entirely sure what this does, but probably not important.
					auto stream = new ClassicStream!(Endian.bigEndian)();
					stream.writeTag(res);
					std.file.write(output, stream.data);
					break;
				}
			}
		} catch(FileException e) {
			stderr.writeln("Error: "~e.msg);
			return 3;
		} catch(CompilerException e) {
			stderr.writeln("Error compiling: "~e.msg);
			return 5;
		}
	}
	return 0;
}
