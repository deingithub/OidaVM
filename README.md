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
