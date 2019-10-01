# OidaVM

A (not that, anymore) minimal bytecode VM implemented in Zig with integrated debugger.

## Usage

Run `oida run youroidasmfile` to run your program, optionally specifying an entry point in hex after the filename. To debug oidaVM programs, use the internal debugger oiDB, which you can invoke using `oida dbg youroidasmfile`. It has a GDB-*inspired* REPL and internal help accessible via `?` or `h` in oiDB.

## Specs

- 4096 16-bit words of memory, each freely interpretable as instruction or data
- Two (2) internal registers, `ACC` and the instruction pointer.

## ISA

### Global Opcodes (four bits)

These can target the entire memory space of the VM. There are six possible opcodes in this category.

- `noopr` (0x0): Skips instruction.
- `pgjmp` (0xa): Selects highest four bits of address as page and unconditionally continues execution at address.
- `fftch` (0xb): Copies memory value at address into ACC.
- `fwrte` (0xc): Overwrites memory at address with copy of ACC.

### Paged Opcodes (eight bits)

These can target all addresses on the current page, which represents one 16th of the full memory. There are 144 possible opcodes in this category.

- `incby` (0x11): Adds value of address in memory to ACC. Overflow gets silently truncated to 65535.
- `minus` (0x12): Substracts value of address in memory from ACC. Underflow gets silently truncated to 0.
- `fetch` (0x20): Copies memory value at address into ACC.
- `write` (0x21): Overwrites memory at address with copy of ACC.
- `jmpto` (0x30): Unconditionally continues execution at address.
- `jmpez` (0x31): If ACC is 0, continues execution at address, otherwise skips instruction.

### Extended opcodes (sixteen bits)

These can't target memory and take no arguments, so they are either used for I/O or operations on ACC. This category has up to 4096 possible opcodes available.

- `cease` (0xf00f): Halts execution.
- `outnm` (0xf010): Writes the content of ACC to stderr, as a decimal number.
- `outch` (0xf011): Writes the lower eight bits of ACC to stderr, as ASCII character.
- `outlf` (0xf012): Writes `\n` to stderr.
- `outnm` (0xf013): Writes the content of ACC to stderr, as a hexadecimal number.
- `inacc` (0xf020): Awaits one word of input from user and writes it into ACC.
- `rando` (0xf030): Write a random value (backed by the default PRNG) into ACC.
- `augmt` (0xf040): Increase ACC by one. Overflow gets silently truncated to 65535.
- `dimin` (0xf041): Diminish ACC by one. Underflow gets silently truncated to 0.
- `shfl4` (0xf042): Shifts the value of ACC four bytes to the left.
- `shfr4` (0xf043): Shifts the value of ACC four bytes to the right.
- `shfl1` (0xf044): Shifts the value of ACC one byte to the left.
- `shfr1` (0xf045): Shifts the value of ACC one byte to the right.

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
