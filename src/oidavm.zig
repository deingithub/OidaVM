const std = @import("std");

/// Uppermost four bits of a word. Can address all memory.
pub const GlobalOpcode = enum(u4) {
    /// Skips instruction.
    NoOp = 0x0,

    /// Selects the highest four bits of the address as page and unconditionally continues execution at address.
    PageAndJump = 0xa,

    /// Dereference address and copy content into ACC.
    FarFetch = 0xb,

    /// Copy ACC into address.
    FarWrite = 0xc,

    /// Interprets the entirety of the word as an extended opcode.
    Extend = 0xf,
};

/// Uppermost eight bits of a word. Can only use addresses within the current page.
pub const PagedOpcode = enum(u8) {
    /// Dereference address and add it to ACC. Overflow gets silently truncated to 65535.
    IncrementBy = 0x11,

    /// Dereference address and subtract it from ACC. Underflow gets silently truncated to 0.
    Minus = 0x12,

    /// Dereference address and copy it into ACC.
    Fetch = 0x20,

    /// Copy ACC into address.
    Write = 0x21,

    /// Unconditionally continue execution at address.
    Jump = 0x30,

    /// Continue execution at address if ACC is 0, otherwise skip instruction.
    JumpEZ = 0x31,
};

/// The lower twelve bits of a word as used in conjunction with GlobalOpcode.Extend (0xf). Can't address memory.
pub const ExtendedOpcode = enum(u12) {
    /// Halts execution.
    Halt = 0x00f,

    /// Writes the content of ACC to stderr.
    OutputNumeric = 0x010,

    /// Writes the lower eight bits of ACC interpreted as ASCII to stderr.
    OutputChar = 0x011,

    /// Writes \n to stderr.
    OutputLinefeed = 0x012,
};

pub const OidaVm = struct {
    memory: [4096]u16 = [_]u16{0} ** 4096,
    accumulator: u16 = 0,
    instruction_ptr: u12 = 0,
    page: u4 = 0,

    /// Executes a single instruction
    fn exec(this: *OidaVm, word: u16) void {
        if (word >> 12 > 0 and word >> 12 < 0xa) {
            // Paged Opcodes: 0x01..0x99
            const address: u12 = (@intCast(u12, this.page) << 8) + @truncate(u8, word);
            switch (@intToEnum(PagedOpcode, @intCast(u8, word >> 8))) {
                .IncrementBy => if (usize(this.accumulator) + this.memory[address] >= 65535) {
                    this.accumulator = 65535;
                } else {
                    this.accumulator += this.memory[address];
                },
                .Minus => if (this.accumulator >= this.memory[address]) {
                    this.accumulator -= this.memory[address];
                } else {
                    this.accumulator = 0;
                },
                .Fetch => this.accumulator = this.memory[address],
                .Write => this.memory[address] = this.accumulator,
                .Jump => this.instruction_ptr = address - 1,
                .JumpEZ => if (this.accumulator == 0) {
                    this.instruction_ptr = address - 1;
                } else {
                    return;
                },
            }
        } else {
            // Unpaged Opcodes: 0x0000, 0xa..0xf
            const address = @truncate(u12, word);
            switch (@intToEnum(GlobalOpcode, @intCast(u4, word >> 12))) {
                .NoOp => return,
                .FarFetch => this.accumulator = this.memory[address],
                .FarWrite => this.memory[address] = this.accumulator,
                .PageAndJump => {
                    this.instruction_ptr = address - 1;
                    this.page = @intCast(u4, address >> 8);
                },
                .Extend => switch (@intToEnum(ExtendedOpcode, address)) {
                    .Halt => return, // Handled by eval()
                    .OutputNumeric => std.debug.warn("{}", this.accumulator),
                    .OutputChar => std.debug.warn("{c}", @truncate(u8, this.accumulator)),
                    .OutputLinefeed => std.debug.warn("\n"),
                },
            }
        }
    }

    /// Starts to evaluate memory as instructions starting at `addr`.
    /// Invalid opcodes invoke safety-checked UB, so try to avoid them.
    fn eval(this: *OidaVm, addr: u12) void {
        this.instruction_ptr = addr;
        while (this.instruction_ptr < 4095) : (this.instruction_ptr += 1) {
            if (this.memory[this.instruction_ptr] == 0xf00f) return; // Extend-Halt opcode
            this.exec(this.memory[this.instruction_ptr]);
        }
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
        std.debug.warn("Page {X} [{X:0^3}..{X:0^3}]\n", this.page, this.page * u16(256), this.page * u16(256) + 255);

        var elided = false;
        std.debug.warn("Memory: \n");
        for (this.memory) |val, addr| {
            // Check if this row is entirely made up of zeroes, if yes, skip it
            const row_start = addr - addr % 8;
            if (std.mem.eql(u16, this.memory[row_start .. row_start + 8], [_]u16{0} ** 8)) {
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
        std.debug.warn("== end dump ==\n");
    }

    /// Resets the VM to starting conditions.
    fn flush(this: *OidaVm) void {
        this.instruction_ptr = 0;
        this.accumulator = 0;
        this.memory = [_]u16{0} ** 4096;
    }
};
