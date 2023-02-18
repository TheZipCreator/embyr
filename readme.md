# Embyr
Embyr is a text representation of DiamondFire code blocks. This repository is a compiler that converts Embyr into DiamondFire code templates, written in D.

## Reasoning
The goal of Embyr is to be a sort-of portable DiamondFire assembly language. This is in order to make it easier to make other languages with DiamondFire as a target. For example, if you make a compiler called `mylangc`, and you wanted the output format to be DiamondFire code blocks, you could compile to an Embyr source code file, and then shell out to embyr, with something like `embyr -o out.txt compiled.embyr`.
The reason to do this instead of directly compiling to DiamondFire code blocks is so that you wouldn't have to mess around with the specific details of how DF encodes code blocks into templates. Instead, it is of more practical value to just consider *which* code blocks you want to compile code to, rather than worrying about how to convert those codeblocks into a format that DiamondFire knows.
It also provides a way to write DiamondFire code through exclusively text, if you prefer that medium over writing code directly on the server.

## Examples

# A simple Hello, World!
This sends the player a message when they join the plot.
```
PLAYER_EVENT Join:
	PLAYER_ACTION SendMessage txt"Hello, World!";
```
There's a few things to note here. The first one is declarations. Declarations are the generic name that Embyr gives to things such as Player Events, Functions, or Processes. This file contains a single declaration (`PLAYER_EVENT Join:`) but a file may contain as many declarations as necessary. Each declaration is converted into 1 or more code templates.
Also note the `txt` prefix before `"Hello, World!"`. This tells the compiler that this is *text*, and not another datatype. This is important, because in DiamondFire, things such as numbers may also contain arbitrary text (this is why you can type things like `%math(2+3)` into a number). As such, the datatype is almost always prefixed before the value.
Another thing to look at is the semicolon (`;`) after the player action. All codeblocks must end with a semicolon, or a brace ('{', '}' for pistons, '<', '>' for sticky pistons). This is so you can wrap code blocks over multiple lines, which may be useful for setting up things like inventory menus.
# Item Giver
This is a program that assumes the existence of signs at some given coordinates. It then will detect which sign the player clicked on, and give an item accordingly.
```
PLAYER_EVENT RightClick:
	IF_PLAYER IsLookingAt loc[5 50 5] {
		PLAYER_ACTION GiveItems item{id:"minecraft:oak_log",Count:1b};
	}
	IF_PLAYER IsLookingAt loc[5 50 6] {
		PLAYER_ACTION GiveItems item{id:"minecraft:stone",Count:1b};
	}
	IF_PLAYER IsLookingAt loc[5 50 7] {
		PLAYER_ACTION GiveItems item{id"minecraft:diamond",Count:1b};
	}
```
This shows off the location syntax, and `IF_PLAYER`. Locations are of the form `loc[x y z]` or `loc[x y z pitch yaw]`, and they're used here to give coordinates which the player is expected to click at.
Also notable is the `item` literal, which uses the SNBT (String Named Binary Table) format, which is something Minecraft natively supports (and DF uses to encode items).
# A simple PVP game
```
PLAYER_EVENT Join:
	PLAYER_ACTION SetAllowPVP tag["PVP" "Enable"];
	PLAYER_ACTION AllPlayers SendMessage txt"\&a+ \&e%default has joined.";
	PLAYER_ACTION GiveItems item{id:"minecraft:iron_sword",Count:1b};

PLAYER_EVENT Leave:
	PLAYER_ACTION AllPlayers SendMessage txt"\&c- \&e%default has left.";

PLAYER_EVENT Respawn:
	PLAYER_ACTION GiveItems item{id:"minecraft:iron_sword",Count:1b};

PLAYER_EVENT KillPlayer:
	SET_VAR += var"%default kills"s num"1";
	PLAYER_ACTION AllPlayers SendMessage txt"\&4%default \&chas killed \&4%victim\&c. They now have %var(%default kills) kills.";
```
This shows many new things. The first thing to look at is tags. In the previous examples, the tags for each player action were generated by the compiler, via the `--addtags` switch. Here it's the same, but we also add a tag of our own, in `SetAllowPVP`. Tags consist of the tag name, followed by the value. Creating an invalid tag will cause a compiler error.
Another new thing in this example is targets. Targets are specified as identifiers and placed before the action. Targets are only valid in some contexts. For example, a target is *invalid* in `SET_VAR`.
Another thing of note is the variable literals, notice the `s` after it? That `s` is a flag that makes it a *saved* variable. There a 3 variable flags: `g` for global, `s` for saved, and `l` for local. They must immediately succeed a variable string.
Finally, you might notice the `\&` in variables. This is another way of typing the section symbol, which MC uses for colors. It is equivalent to just typing `&` on the DF server.