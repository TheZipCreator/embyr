module peg;

import pegged.grammar;

mixin(grammar(`
Embyr:
	Program <- (:_? Declaration :_?)* endOfInput

	Declaration <- PlayerEventDecl / EntityEventDecl / FunctionDecl / ProcessDecl / Definition
	
	PlayerEventDecl <- 'PLAYER_EVENT' :_? Identifier :_? ':' :_? Blocks?
	EntityEventDecl <- 'ENTITY_EVENT' :_? Identifier :_? ':' :_? Blocks?
	FunctionDecl <- 'FUNCTION' :_? Identifier :_? (Values / ^eps) :_? ':' :_? Blocks?
	ProcessDecl <- 'PROCESS' :_? Identifier :_? (Values / ^eps) :_? ':' :_? Blocks?

	Blocks <- (:_? Block :_?)+

	Block <- PlayerActionBlock / IfPlayerBlock / IfVarBlock / SetVarBlock / CallFuncBlock / StartProcessBlock / ControlBlock / GameActionBlock
		/ RepeatWhileBlock / RepeatBlock / IfGameBlock / ElseBlock / EntityActionBlock / IfEntityBlock / SelectObjectBlock
		/ LeftPiston / RightPiston / LeftRepeatPiston / RightRepeatPiston / Definition

	LeftPiston <- '{'
	RightPiston <- '}'
	LeftRepeatPiston <-  '${'
	RightRepeatPiston <- '}$'

	PlayerActionBlock <- 'PLAYER_ACTION' :_ (Target :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	EntityActionBlock <- 'ENTITY_ACTION' :_ (Target :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	GameActionBlock <- 'GAME_ACTION' :_ (Target ;_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	IfPlayerBlock <- 'IF_PLAYER' :_ (Target :_ / ^eps) (Not :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	IfEntityBlock <- 'IF_ENTITY' :_ (Target :_ / ^eps) (Not :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	IfVarBlock <- 'IF_VAR' :_ ^eps (Not :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	IfGameBlock <- 'IF_GAME' :_ ^eps (Not :_ / ^eps) Identifier :_ (Values / ^eps) :_? Terminator
	SetVarBlock <- 'SET_VAR' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator
	SelectObjectBlock <- 'SELECT_OBJECT' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator
	CallFuncBlock <- 'CALL_FUNCTION' :_ Identifier :_? Terminator
	StartProcessBlock <- 'START_PROCESS' :_ Identifier :_ (Values / ^eps) :_? Terminator
	ControlBlock <- 'CONTROL' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator
	RepeatWhileBlock <- 'REPEAT' :_ 'While' :_ ('IF_PLAYER' / 'IF_ENTITY' / 'IF_VAR' / 'IF_GAME') :_ Identifier :_ (Values / ^eps) :_? Terminator
	RepeatBlock <- 'REPEAT' :_ ^eps Identifier :_ (Values / ^eps) :_? Terminator
	ElseBlock <- 'ELSE' :_? Terminator

	Definition <- Identifier :_? '=' :_? Value :_? ';'

	Values <- (:_? Value :_?)+

	Value <- TxtValue / NumValue / LocValue / VarValue / GameValue / VecValue / SndValue / PotionValue / TagValue / ItemValue / Identifier # / ParticleValue
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
	_ <- ([ \r\n\t]+ / Comment)*
	Comment <- '#' (!endOfLine .)*

	Not <- 'NOT'

	Identifier <~ [a-zA-Z0-9_\-\+\*\/%=<>]+
	Number <~ '-'? [0-9]+ ('.' [0-9]*)?
	String <- NormalString / RawString

	Target <- 'Selection' / 'Default' / 'Killer' / 'Damager' / 'Victim' / 'Shooter' / 'Projectile' / 'LastEntity' / 'AllPlayers' / 'AllEntities' / 'AllMobs'

	RawString <~ backquote (!backquote .*) backquote
	NormalString <- doublequote (EscapeSequence / CharSeq)* doublequote

	EscapeSequence <~ backslash (backslash / doublequote / 'n' / 'r' / 't' / '&')
	CharSeq <~ (!EscapeSequence !doublequote .)*

	Terminator <- ';' / &LeftPiston / &RightPiston / &LeftRepeatPiston / &RightRepeatPiston

# SNBT syntax

	SNBTValue <- SNBTCompound / SNBTFloat / SNBTByte / SNBTShort / SNBTLong / SNBTDouble / SNBTInt / SNBTBoolean / SNBTString / SNBTList / SNBTByteArray / SNBTIntArray / SNBTLongArray

	SNBTCompound <- '{' :_? SNBTCompoundEntry (:_? ',' :_? SNBTCompoundEntry :_?)* :_? '}'
	SNBTCompoundEntry <- (Identifier / NormalString) :_? ':' :_? SNBTValue

	SNBTByte <- '-'? [0-9]+ ('b' / 'B')
	SNBTBoolean <- 'true' / 'false'
	SNBTShort <- '-'? [0-9]+ ('s' / 'S')
	SNBTInt <- '-'? [0-9]+
	SNBTLong <- '-'? [0-9]+ ('l' / 'L')
	SNBTFloat <- '-'? [0-9]+ ('.' [0-9]*)? ('f' / 'F')
	SNBTDouble <- '-'? [0-9]+ '.' [0-9]*

	SNBTString <- SNBTSingleString / SNBTDoubleString
	SNBTDoubleString <- doublequote SNBTDoubleChar* doublequote
	SNBTDoubleChar <- backslash doublequote / !doublequote .
	SNBTSingleString <- quote SNBTSingleChar* quote
	SNBTSingleChar <- backslash quote / !quote .

	SNBTList <- '[' :_? SNBTValue (:_? ',' :_? SNBTValue :_? )* :_? ']'
	SNBTByteArray <- '[B;' :_? SNBTByte (:_? ',' SNBTByte)* :_? ']'
	SNBTIntArray <- '[I;' :_? SNBTInt (:_? ',' SNBTInt)* :_? ']'
	SNBTLongArray <- '[L;' :_? SNBTLong (:_? ',' SNBTLong)* :_? ']'
`
));
