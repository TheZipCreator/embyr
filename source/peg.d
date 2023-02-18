module peg;

import pegged.grammar;

mixin(grammar(`
Embyr:
	Program <- Declaration* endOfInput

	Declaration <- PlayerEventDecl / FunctionDecl
	PlayerEventDecl <- 'PLAYER_EVENT' :_? Identifier :_? ':' :_? (Blocks / ^eps)
	FunctionDecl <- 'FUNCTION' :_? Identifier :_? ':' :_? (Blocks / ^eps)

	Blocks <- (:_? Block :_?)+

	Block <- PlayerActionBlock / IfPlayerBlock / IfVarBlock / SetVarBlock / LeftPiston / RightPiston / LeftRepeatPiston / RightRepeatPiston

	LeftPiston <- '{'
	RightPiston <- '}'
	LeftRepeatPiston <- '<'
	RightRepeatPiston <- '>'

	PlayerActionBlock <- 'PLAYER_ACTION' :_ ((Identifier / ^eps) :_?) Identifier :_ (Values / ^eps) :_? Terminator
	IfPlayerBlock <- 'IF_PLAYER' :_ ((Identifier / ^eps) :_?) Identifier :_ (Values / ^eps) :_? Terminator
	IfVarBlock <- 'IF_VAR' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator
	SetVarBlock <- 'SET_VAR' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator


	Values <- (:_? Value :_?)*

	Value <- TxtValue / NumValue / LocValue / VarValue / GameValue / VecValue / SndValue / PotionValue / TagValue / ItemValue # / ParticleValue
	TxtValue <- 'txt' :_? String 
	NumValue <- 'num' :_? String
	LocValue <- 'loc' :_? '[' :_? Number :_ Number :_ Number (:_ Number :_ Number)? :_? ']' # x y z (pitch yaw)
	VarValue <- 'var' :_? String :_? VarFlags?
	VarFlags <- 'g' / 's' / 'l' # global / saved / local
	GameValue <- 'g_val' :_? (String / '[' :_? String :_? String :_? ']') # name / name target  # target defaults to default
	VecValue <- 'vec' :_? '[' :_? Number :_? Number :_? Number :_? ']' # x y z
	SndValue <- 'snd' :_? '[' :_? String :_? Number :_? Number :_? ']' # name pitch vol
	PotionValue <- 'pot' :_? '[' :_? String :_? Number :_? Number :_? ']' # pot amp dur
	TagValue <- 'tag' :_? '[' :_? String :_? String :_? ']' # tag option
	ItemValue <- 'item' :_? ~SNBTCompound

# not using the < operator because sometimes I do want whitespace in places
	_ <- ([ \n\t]+ / Comment)*
	Comment <- '#' (!endOfLine .)*

	Identifier <~ [a-zA-Z0-9_\-\+\*\/%=]+
	Number <~ '-'? [0-9]+ ('.' [0-9]*)?
	String <- NormalString / RawString

	RawString <~ backquote (!backquote .*) backquote
	NormalString <- doublequote (EscapeSequence / CharSeq)* doublequote

	EscapeSequence <~ backslash (backslash / doublequote / 'n' / 'r' / 't' / '&')
	CharSeq <~ (!EscapeSequence !doublequote .)*

	Terminator <- ';' / &LeftPiston / &RightPiston / &LeftRepeatPiston / &RightRepeatPiston

# SNBT syntax

	SNBTValue <- SNBTCompound / SNBTFloat / SNBTByte / SNBTShort / SNBTLong / SNBTDouble / SNBTInt / SNBTBoolean / NormalString / SNBTList / SNBTByteArray / SNBTIntArray / SNBTLongArray

	SNBTCompound <- '{' :_? SNBTCompoundEntry (:_? ',' :_? SNBTCompoundEntry :_?)* :_? '}'
	SNBTCompoundEntry <- (Identifier / NormalString) :_? ':' :_? SNBTValue

	SNBTByte <- '-'? [0-9]+ ('b' / 'B')
	SNBTBoolean <- 'true' / 'false'
	SNBTShort <- '-'? [0-9]+ ('s' / 'S')
	SNBTInt <- '-'? [0-9]+
	SNBTLong <- '-'? [0-9]+ ('l' / 'L')
	SNBTFloat <- '-'? [0-9]+ ('.' [0-9]*)? ('f' / 'F')
	SNBTDouble <- '-'? [0-9]+ '.' [0-9]*
# TODO: create custom SNBTString instead of using NormalString

	SNBTList <- '[' :_? SNBTValue (:_? ',' :_? SNBTValue :_? )* :_? ']'
	SNBTByteArray <- '[B;' :_? SNBTByte (:_? ',' SNBTByte)* :_? ']'
	SNBTIntArray <- '[I;' :_? SNBTInt (:_? ',' SNBTInt)* :_? ']'
	SNBTLongArray <- '[L;' :_? SNBTLong (:_? ',' SNBTLong)* :_? ']'
`
));
