# OidaVM

A (not that, anymore) minimal bytecode VM implemented in Zig with integrated debugger.

## Usage

Run `oida run youroidasmfile` to run your program, optionally specifying an entry point in hex after the filename. To debug oidaVM programs, use the internal debugger oiDB, which you can invoke using `oida dbg youroidasmfile`. It has a GDB-*inspired* REPL and internal help accessible via `?` or `h`.

## Specs

- 4096 16-bit words of memory, each freely interpretable as instruction or data
- Two (2) internal registers, `ACC` and the instruction pointer.

## ISA

### Global Opcodes (four bits)

These can target the entire memory space of the VM. There are six possible opcodes in this category.

- `0x0 noopr` *No Operation*: Skips instruction.
- `0xa pgjmp` *Page And Jump*: Selects highest four bits of address as page and unconditionally continues execution at address.
- `0xb fftch` *Far Fetch*: Copies memory value at address into ACC.
- `0xc fwrte` *Far Write*: Overwrites memory at address with copy of ACC.

### Paged Opcodes (eight bits)

These can target all addresses on the current page, which represents one 16th of the full memory. There are 144 possible opcodes in this category.

- `0x11 incby` *Increment By*: Adds value of address in memory to ACC. Overflow gets truncated to 65535; if no overflow occurs the next instruction is skipped.
- `0x12 minus` *Minus*: Substracts value of address in memory from ACC. Underflow gets truncated to 0; if no overflow occurs the next instruction is skipped.
- `0x20 fetch` *Fetch*: Copies memory value at address into ACC.
- `0x21 write` *Write*: Overwrites memory at address with copy of ACC.
- `0x30 jmpto` *Jump To*: Unconditionally continues execution at address.
- `0x31 jmpez` *Jump If Equal To Zero*: If ACC is 0, continues execution at address, otherwise skips instruction.

### Extended opcodes (sixteen bits)

These can't target memory and take no arguments, so they are either used for I/O or operations on ACC. There are 144 possible opcodes in this category.

- `0xf00f cease` *Cease*: Halts execution.
- `0xf010 outnm` *Output, Numeric*: Writes the content of ACC to stderr, as a decimal number.
- `0xf011 outch` *Output, Character*: Writes the lower eight bits of ACC to stderr, as ASCII character.
- `0xf012 outlf` *Output Linefeed*: Writes `\n` to stderr.
- `0xf013 outhx` *Output, Hexadecimal*: Writes the content of ACC to stderr, as a hexadecimal number.
- `0xf020 inacc` *Input To ACC*: Awaits one word of input from user and writes it into ACC.
- `0xf030 rando` *Randomize ACC*: Writes a random value (backed by the default PRNG) into ACC.
- `0xf040 augmt` *Augment ACC*: Increases ACC by one. Overflow gets truncated to 65535; if no overflow occurs the next instruction is skipped.
- `0xf041 dimin` *Diminish ACC*: Diminishes ACC by one. Underflow gets truncated to 0; if no underflow occurs the next instruction is skipped.
- `0xf042 shfl4` *Shift Left Four*: Shifts the value of ACC four bytes to the left.
- `0xf043 shfr4` *Shift Right Four*: Shifts the value of ACC four bytes to the right.
- `0xf044 shfl1` *Shift Left One*: Shifts the value of ACC one byte to the left.
- `0xf045 shfr1` *Shift Right One*: Shifts the value of ACC one byte to the right.

## oidASM

oidASM is the assembly language for OidaVM. It has five fundamental elements: Directives, Variable Definitions, Blocks, Instructions and Comments. Each element takes up one line. Comments start with `#` and are ignored by the assembler. Directives start with `@` and pass metadata to the assembler. Variable definitions start with `$` and bind a value to a symbol for later reference. Blocks start with `:` and delineate sections of the program that can be jumped to. Instructions appear after a block marker and consist of a five-char mnemonic and optionally an address (either as `$variable` or `:block`).  
Each program needs at least a `@entry` directive to set the entry point of the program to a block and one block to execute.  
The `@page` directive sets the current working page of the assembler. If no directive is specified, the assembler assumes page `0`.

For some examples, look into the oidASM/ folder.

## Why?

Yes.
