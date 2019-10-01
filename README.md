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

- `0x11 incby` *Increment By*: Adds value of address in memory to ACC. Overflow gets silently truncated to 65535.
- `0x12 minus` *Minus*: Substracts value of address in memory from ACC. Underflow gets silently truncated to 0.
- `0x20 fetch` *Fetch*: Copies memory value at address into ACC.
- `0x21 write` *Write*: Overwrites memory at address with copy of ACC.
- `0x30 jmpto` *Jump To*: Unconditionally continues execution at address.
- `0x31 jmpez` *Jump If Equal To Zero*: If ACC is 0, continues execution at address, otherwise skips instruction.

### Extended opcodes (sixteen bits)

These can't target memory and take no arguments, so they are either used for I/O or operations on ACC. This category has up to 4096 possible opcodes available.

- `0xf00f cease` *Cease*: Halts execution.
- `0xf010 outnm` *Output, Numeric*: Writes the content of ACC to stderr, as a decimal number.
- `0xf011 outch` *Output, Character*: Writes the lower eight bits of ACC to stderr, as ASCII character.
- `0xf012 outlf` *Output Linefeed*: Writes `\n` to stderr.
- `0xf013 outhx` *Output, Hexadecimal*: Writes the content of ACC to stderr, as a hexadecimal number.
- `0xf020 inacc` *Input To ACC*: Awaits one word of input from user and writes it into ACC.
- `0xf030 rando` *Randomize ACC*: Write a random value (backed by the default PRNG) into ACC.
- `0xf040 augmt` *Augment ACC*: Increase ACC by one. Overflow gets silently truncated to 65535.
- `0xf041 dimin` *Diminish ACC*: Diminish ACC by one. Underflow gets silently truncated to 0.
- `0xf042 shfl4` *Shift Left Four*: Shifts the value of ACC four bytes to the left.
- `0xf043 shfr4` *Shift Right Four*: Shifts the value of ACC four bytes to the right.
- `0xf044 shfl1` *Shift Left One*: Shifts the value of ACC one byte to the left.
- `0xf045 shfr1` *Shift Right One*: Shifts the value of ACC one byte to the right.

## oidASM

**OIDASM IS PENDING REVISION TO MAKE IT LESS HORRIBLE.**  
oidASM is a relatively-easy-to-write textual representation of the machine's memory. It's tokenized per-line, so you need to be aware of the line types:

- Comment lines are ignored wholly and start with `;`. Blank lines are ignored similarly.
- Name assignment lines assign a name to an address and follow the syntax `= identifier_here #123`.
- Cursor lines set the position of the parser's cursor, i.e. where the next expression line will be placed inside the VM's memory. They take the form of `:= [address]`, `:+ [offset]` or `:- [offset]`, where `[address]`/`[offset]` are either a `$name` or a bare address `#123`.
- Expression lines evaluate to a single word that gets placed in the VM's memory according to the cursor's current position. They either are a bare `#1234` u16 value or a five-letter opcode mnemonic optionally followed by an address, like this: `outnm`, `jmpto $addr` or `fetch #f00`. Every parsed expression line increases the cursor by one. Other lines do not increase the cursor. The cursor starts at `0x000`.

For some examples, look into the oidASM/ folder.

## Why?

Yes.
