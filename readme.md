# Embyr
Embyr is a text representation of DiamondFire code blocks. This repository is a compiler that converts Embyr into DiamondFire code templates, written in D.

## Reasoning
The goal of Embyr is to be a sort-of portable DiamondFire assembly language. This is in order to make it easier to make other languages with DiamondFire as a target. For example, if you make a compiler called `mylangc`, and you wanted the output format to be DiamondFire code blocks, you could compile to an Embyr source code file, and then shell out to embyr, with something like `embyr -o out.txt compiled.embyr`.
The reason to do this instead of directly compiling to DiamondFire code blocks is so that you wouldn't have to mess around with the specific details of how DF encodes code blocks into templates. Instead, it is of more practical value to just consider *which* code blocks you want to compile code to, rather than worrying about how to convert those codeblocks into a format that DiamondFire knows.
It also provides a way to write DiamondFire code through exclusively text, if you prefer that medium over writing code directly on the server.
