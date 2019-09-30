# OidaVM

A minimal bytecode VM implemented in Zig.

## Specs

- 4096 16-bit words of memory
- Two (2) internal registers

### ISA

- A word can be interpreted as opcode with either a global, page-local, or no address attached.
- Global-argument opcodes take up four bits. They are `0x0` and `0xa`-`0xe` for a total of six possible global opcodes.
- Local-argument opcodes take up eight bits. They are `0x10`-`0x9f` for a total of 144 local opcodes.
- No-argument (extended) opcodes take up a full word and start with `0xf`, allowing for 4096 extended opcodes.
- While global-argument opcodes can target the entire address space, local-argument opcodes are limited to the current page of memory (set using global PageAndJump `0xa`). A page has 256 words of memory, there are 16 pages numbered `0` through `F`.

## Why?

Yes.

## oidASM

oidASM is a relatively-easy-to-write textual representation of the machine's memory. It's tokenized per-line, so you need to be aware of the line types:

- Comment lines are ignored wholly and start with `;`. Blank lines are ignored similarly.
- Name assignment lines assign a name to an address and follow the syntax `= identifier_here #123`.
- Cursor lines set the position of the parser's cursor, i.e. where the next expression line will be placed inside the VM's memory. They take the form of `:= [address]`, `:+ [offset]` or `:- [offset]`, where `[address]`/`[offset]` are either a `$name` or a bare address `#123`.
- Expression lines evaluate to a single word that gets placed in the VM's memory according to the cursor's current position. They either are a bare `#1234` u16 value or a five-letter opcode mnemonic optionally followed by an address, like this: `outnm`, `jmpto $addr` or `fetch #f00`. Every parsed expression line increases the cursor by one. Other lines do not increase the cursor. The cursor starts at `0x000`.

For some examples, look into the oidASM/ folder.