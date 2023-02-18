﻿/*
 * Copyright (c) 2017-2020 sel-project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */
/**
 * Copyright: Copyright (c) 2017-2020 sel-project
 * License: MIT
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-nbt/sel/nbt/parser.d, sel/nbt/parser.d)
 */
module sel.nbt.parser;

import std.algorithm : canFind;
import std.conv : to, ConvOverflowException;
import std.string;

import sel.nbt.tags;

/**
 * Parses a string into a tag.
 */
public Tag parse(string data) {
	return parseImpl(data);
}

///
unittest {

	assert(parse("") is null);

	assert(parse("{}") == new Compound());
	assert(parse("{a:true,b:false}") == new Compound(new Named!Byte("a", true), new Named!Byte("b", false)));

	assert(parse("[string,1]") is null);
	assert(parse("[]") == new List());
	assert(parse("[,]") == new IntArray());
	assert(parse("[1L, 2]") == new IntArray(1, 2));
	
	// string
	assert(parse(`"a string"`) == new String("a string"));
	assert(parse(`"a \"quoted\" string"`) == new String("a \"quoted\" string"));
	assert(parse(`"a newline\nstring"`) == new String("a newline\\nstring"));
	assert(parse(`"\\\\\" \ "`) == new String(`\\" \ `));
	assert(parse("test") == new String("test"));
	
	// numbers
	assert(parse("55") == new Int(55));
	assert(parse("12b") == new Byte(12));
	assert(parse("-4S") == new Short(-4));
	assert(parse("2147483649") == new Long(2147483649L));
	assert(parse("0L") == new Long(0));
	assert(parse("12.1") == new Double(12.1));
	assert(parse(".44f") == new Float(.44f));
	assert(parse("12.1.1.1") == new Double(12.1));
	assert(parse(".00D") == new Double(0));

	// compound
	assert(parse(`{EntityData:{id:"minecraft:creeper"}}`) == new Compound(new Named!Compound("EntityData", new Named!String("id", "minecraft:creeper"))));
	assert(parse(`{Potion:"minecraft:long_strength"}`) == new Compound(new Named!String("Potion", "minecraft:long_strength")));
	
}

private Tag parseImpl(ref string data) {

	// remove spaces
	data = data.stripLeft;

	char shift() {
		char ret = data[0];
		data = data[1..$];
		return ret;
	}

	if(data.length == 0) {
		return null;
	} else if(data[0] == '{') {
		// read a compound
		shift();
		Tag[] ret;
		while(data.length && data[0] != '}') {
			// read name
			string name = parseUnquotedString([':'], data);
			if(data.length) {
				shift();
				// read value
				auto tag = parseImpl(data);
				if(tag !is null) ret ~= tag.rename(name.strip);
				// read comma
				if(data.length && data[0] == ',') shift();
			}
		}
		shift();
		return new Compound(ret);
	} else if(data[0] == '[') {
		// read array
		shift();
		if(data.startsWith(",]")) {
			data = data[2..$];
			return new IntArray();
		}
		Tag[] ret;
		while(data.length && data[0] != ']') {
			ret ~= parseImpl(data);
			if(data.length && data[0] == ',') shift();
		}
		int[] integrals;
		foreach(tag ; ret) {
			if(cast(Byte)tag) integrals ~= cast(Byte)tag;
			else if(cast(Short)tag) integrals ~= cast(Short)tag;
			else if(cast(Int)tag) integrals ~= cast(Int)tag;
			else if(cast(Long)tag) integrals ~= cast(int)cast(Long)tag;
			else break;
		}
		// return int array if all the tags are integrals
		if(integrals.length && integrals.length == ret.length) {
			return new IntArray(integrals);
		}
		// return list if they're all the same type
		if(ret.length) {
			bool valid = true;
			ubyte type = ret[0].type;
			foreach(tag ; ret[1..$]) {
				if(tag.type != type) {
					valid = false;
					break;
				}
			}
			if(!valid) return null;
		}
		return new List(ret);
	} else if(data[0] == '"') {
		// read string
		shift();
		return new String(parseQuotedString(data));
	} else if(data.startsWith("true")) {
		// Byte(1)
		data = data[4..$];
		return new Byte(true);
	} else if(data.startsWith("false")) {
		// Byte(0)
		data = data[5..$];
		return new Byte(false);
	} else if("-0123456789.".canFind(data[0])) {
		// read a number
		bool floating = false;
		string number;
		bool checkFloat() {
			if(!floating) return floating = data[0] == '.';
			else return false;
		}
		if(data[0] == '-') number ~= shift();
		while(data.length && ("0123456789".canFind(data[0]) || checkFloat())) {
			number ~= shift();
		}
		if(data.length && "bslfdBSLFD".canFind(data[0])) {
			final switch(shift()) {
				case 'b': case 'B': return new Byte(to!byte(number));
				case 's': case 'S': return new Short(to!short(number));
				case 'l': case 'L': return new Long(to!long(number));
				case 'f': case 'F': return new Float(to!float(number));
				case 'd': case 'D': return new Double(to!double(number));
			}
		}
		if(floating) {
			return new Double(to!double(number));
		} else {
			try {
				return new Int(to!int(number));
			} catch(ConvOverflowException) {
				return new Long(to!long(number));
			}
		}
	} else {
		// assume it's an unquoted string
		return new String(parseUnquotedString([',', '{', '}', '[', ']'], data));
	}

}

private string parseUnquotedString(char[] terminate, ref string data) {
	string ret;
	while(data.length && !terminate.canFind(data[0])) {
		ret ~= data[0];
		data = data[1..$];
	}
	return ret;
}

private string parseQuotedString(ref string data) {
	// assuming that the first quote has been removed
	string ret;
	while(data.length && data[0] != '"') {
		if(data.length >= 2 && data[0] == '\\' && (data[1] == '"' || data[1] == '\\')) {
			ret ~= data[1];
			data = data[2..$];
		} else {
			ret ~= data[0];
			data = data[1..$];
		}
	}
	if(data.length) data = data[1..$]; // closing
	return ret;
}
