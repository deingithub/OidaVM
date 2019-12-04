const std = @import("std");

/// Uppermost four bits of a word. Can address all memory.
pub const GlobalOpcode = enum(u4) {
    /// noopr — Skips instruction.
    NoOp = 0x0,

    /// pgjmp — Selects the highest four bits of the address as page and unconditionally continues execution at address.
    PageAndJump = 0xa,

    /// fftch — Dereference address and copy content into ACC.
    FarFetch = 0xb,

    /// fwrte — Copy ACC into address.
    FarWrite = 0xc,

    /// Interprets the entirety of the word as an extended opcode.
    Extend = 0xf,
};

/// Uppermost eight bits of a word. Can only use addresses within the current page.
pub const PagedOpcode = enum(u8) {
    /// incby — Dereference address and add it to ACC. Overflow gets silently truncated to 65535.
    IncrementBy = 0x11,

    /// minus — Dereference address and subtract it from ACC. Underflow gets silently truncated to 0.
    Minus = 0x12,

    /// fetch — Dereference address and copy it into ACC.
    Fetch = 0x20,

    /// write — Copy ACC into address.
    Write = 0x21,

    /// jmpto — Unconditionally continue execution at address.
    Jump = 0x30,

    /// jmpez — Continue execution at address if ACC is 0, otherwise skip instruction.
    JumpEZ = 0x31,
};

/// The lower twelve bits of a word as used in conjunction with GlobalOpcode.Extend (0xf). Can't address memory.
pub const ExtendedOpcode = enum(u12) {
    /// cease — Halts execution.
    Halt = 0x00f,

    /// outnm — Writes the content of ACC to stderr.
    OutputNumeric = 0x010,

    /// outch — Writes the lower eight bits of ACC interpreted as ASCII to stderr.
    OutputChar = 0x011,

    /// outlf — Writes \n to stderr.
    OutputLinefeed = 0x012,

    // outhx — Writes the content of ACC formatted as hexadecimal to stderr.
    OutputHex = 0x013,

    /// inacc — Awaits one-word input from user and writes it into ACC.
    InputACC = 0x020,

    /// rando — Randomizes ACC using the default PRNG.
    Randomize = 0x030,

    /// augmt — Increase ACC by one. Overflow gets silently truncated to 65535.
    Augment = 0x040,

    /// dimin — Diminish ACC by one. Underflow gets silently truncated to 0.
    Diminish = 0x041,

    /// shfl4 — Shift ACC left by four bits.
    ShiftLeftFour = 0x042,

    /// shfr4 — Shift ACC left by four bits.
    ShiftRightFour = 0x043,

    /// shfl1 — Shift ACC left by one bit.
    ShiftLeftOne = 0x044,

    /// shfr1 — Shift ACC right by one bit.
    ShiftRightOne = 0x045,
};

pub const OidaVm = struct {
    memory: [4096]u16 = [_]u16{0} ** 4096,
    accumulator: u16 = 0,
    instruction_ptr: u12 = 0,
    page: u4 = 0,
    rng: std.rand.Random,

    /// Executes a single instruction
    fn exec(this: *OidaVm, word: u16) void {
        if (word >> 12 > 0 and word >> 12 < 0xa) {
            // Paged Opcodes: 0x01..0x99
            const global_address = (@as(u12, this.page) << 8) + @truncate(u8, word);
            const opcode = @intCast(u8, word >> 8);
            if (!enum_check(PagedOpcode, opcode)) {
                this.vm_panic("Encountered invalid opcode 0x{X:0^2} at address 0x{X:0^3}.", opcode, this.instruction_ptr);
            }
            switch (@intToEnum(PagedOpcode, opcode)) {
                .IncrementBy => if (@as(usize, this.accumulator) + this.memory[global_address] >= 65535) {
                    this.accumulator = 65535;
                } else {
                    this.accumulator += this.memory[global_address];
                    this.instruction_ptr += 1;
                },
                .Minus => if (this.accumulator >= this.memory[global_address]) {
                    this.accumulator -= this.memory[global_address];
                    this.instruction_ptr += 1;
                } else {
                    this.accumulator = 0;
                },
                .Fetch => this.accumulator = this.memory[global_address],
                .Write => this.memory[global_address] = this.accumulator,
                .Jump => this.instruction_ptr = global_address - 1,
                .JumpEZ => if (this.accumulator == 0) {
                    this.instruction_ptr = global_address - 1;
                } else {
                    return;
                },
            }
        } else {
            // Unpaged Opcodes: 0x0000, 0xa..0xf
            const global_address = @truncate(u12, word);
            const opcode = @intCast(u4, word >> 12);
            if (!enum_check(GlobalOpcode, opcode)) {
                this.vm_panic("Encountered invalid opcode 0x{X} at address 0x{X:0^3}.", opcode, this.instruction_ptr);
            }
            switch (@intToEnum(GlobalOpcode, opcode)) {
                .NoOp => return,
                .FarFetch => this.accumulator = this.memory[global_address],
                .FarWrite => this.memory[global_address] = this.accumulator,
                .PageAndJump => {
                    this.instruction_ptr = global_address - 1;
                    this.page = @intCast(u4, global_address >> 8);
                },
                .Extend => {
                    if (!enum_check(ExtendedOpcode, global_address)) {
                        this.vm_panic("Encountered invalid opcode 0xF{X:0^3} at address 0x{X:0^3}.", global_address, this.instruction_ptr);
                    }
                    switch (@intToEnum(ExtendedOpcode, global_address)) {
                        .Halt => return, // Handled by eval()
                        .OutputNumeric => std.debug.warn("{}", this.accumulator),
                        .OutputChar => std.debug.warn("{c}", @truncate(u8, this.accumulator)),
                        .OutputHex => std.debug.warn("{X:0^4}", this.accumulator),
                        .OutputLinefeed => std.debug.warn("\n"),
                        .InputACC => {
                            var buffer = std.Buffer.initSize(std.heap.direct_allocator, 0) catch this.vm_panic("OOM");
                            defer buffer.deinit();

                            this.accumulator = while (true) : (std.debug.warn("Please use hex format: 0000-ffff\n")) {
                                std.debug.warn("Instruction at 0x{X:0^3} requests one word input: ", this.instruction_ptr);
                                const line = std.io.readLine(&buffer) catch this.vm_panic("Failed to read from STDIN");
                                break std.fmt.parseInt(u16, buffer.toSlice(), 16) catch continue;
                            } else unreachable;
                        },
                        .Randomize => {
                            this.accumulator = this.rng.int(u16);
                        },
                        .Augment => {
                            if (this.accumulator < 65535) {
                                this.accumulator += 1;
                                this.instruction_ptr += 1;
                            }
                        },
                        .Diminish => {
                            if (this.accumulator > 0) {
                                this.accumulator -= 1;
                                this.instruction_ptr += 1;
                            }
                        },
                        .ShiftLeftFour => {
                            this.accumulator = this.accumulator << 4;
                        },
                        .ShiftRightFour => {
                            this.accumulator = this.accumulator >> 4;
                        },
                        .ShiftLeftOne => {
                            this.accumulator = this.accumulator << 1;
                        },
                        .ShiftRightOne => {
                            this.accumulator = this.accumulator >> 1;
                        },
                    }
                },
            }
        }
    }

    /// Starts to evaluate memory as instructions starting at `addr`.
    /// If the VM encounters invalid opcodes, it will exit with status 1
    /// and dump its memory to stderr.
    fn eval(this: *OidaVm, addr: u12) void {
        this.instruction_ptr = addr;
        while (this.instruction_ptr < 4095) : (this.instruction_ptr += 1) {
            if (this.memory[this.instruction_ptr] == 0xf00f) return; // Extend-Halt opcode
            this.step();
        }
    }

    fn step(this: *OidaVm) void {
        this.exec(this.memory[this.instruction_ptr]);
    }

    /// Writes `value` to `addr` in the VM's memory.
    fn load(this: *OidaVm, addr: u12, value: u16) void {
        this.memory[addr] = value;
    }

    /// Dumps the VM's state to stderr.
    fn dump(this: OidaVm) void {
        std.debug.warn("== OidaVM dump ==\n");
        std.debug.warn("Instruction Pointer: 0x{X:0^3}\n", this.instruction_ptr);
        std.debug.warn("Accumulator: 0x{X:0^4}\n", this.accumulator);
        std.debug.warn("Page {X} [{X:0^3}..{X:0^3}]\n", this.page, this.page * @as(u16, 256), this.page * @as(u16, 256) + 255);

        var elided = false;
        std.debug.warn("Memory: \n");
        for (this.memory) |val, addr| {
            // Check if this row is entirely made up of zeroes, if yes, skip it
            const row_start = addr - addr % 8;
            if (std.mem.eql(u16, this.memory[row_start .. row_start + 8], &[_]u16{0} ** 8)) {
                elided = true;
                continue;
            }
            if (elided) {
                std.debug.warn(" [elided]\n");
                elided = false;
            }
            std.debug.warn("{}{}0x{X:0^3}: 0x{X:0^4}{} {}", if (addr == this.instruction_ptr) "\x1b[7m" else "", // Inverted formatting for instruction ptr
                if (val != 0) "\x1b[1m" else "", // Bold formatting for non-null values
                addr, val, if (addr == this.instruction_ptr or val != 0) "\x1b[0m" else "", // Reset all formatting
                if ((addr + 1) % 8 == 0) "\n" else "| " // If next entry is 8, 16, … print newline
            );
        }
        if (elided) std.debug.warn(" [elided]\n");
        std.debug.warn("== end dump ==\n");
    }

    /// Resets the VM to starting conditions.
    fn flush(this: *OidaVm) void {
        this.instruction_ptr = 0;
        this.accumulator = 0;
        this.memory = [_]u16{0} ** 4096;
    }

    fn vm_panic(this: *OidaVm, comptime format: []const u8, args: ...) noreturn {
        std.debug.warn("\n== VM PANIC ==\n" ++ format ++ "\n", args);
        this.dump();
        std.process.exit(1);
    }
};

const builtin = @import("builtin");

/// Checks if the supplied `enum_type` has a field with the value `tag`.
fn enum_check(comptime enum_type: type, tag: usize) bool {
    switch (@typeInfo(enum_type)) {
        builtin.TypeId.Enum => |e| {
            inline for (e.fields) |field| {
                if (field.value == tag) {
                    return true;
                }
            }
            return false;
        },
        else => @compileError("expected enum for enum_check"),
    }
}
