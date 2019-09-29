const std = @import("std");

/// The upper four bits of a word
pub const Opcode = enum(u4) {
    /// Skips instruction.
    NoOp = 0x0,

    /// Reads address into accumulator.
    Fetch = 0x1,

    /// Dereferences address, adds to accumulator. Overflow gets silently truncated to 65535.
    IncBy = 0x2,

    /// Dereferences address, substracts from accumulator. Overflow gets silently truncated to 0.
    Minus = 0x3,

    /// Unconditionally continues execution at address.
    Jump = 0x7,

    /// Continues execution at address if accumulator is 0, otherwise skips instruction.
    JumpEZ = 0x8,

    /// Writes content of accumulator to address.
    Write = 0x9,

    /// Interprets the entirety of the word as an extended opcode
    Extend = 0xf,
};



/// The lower twelve bits of a word as used in conjunction with Opcode.Extend (0xf)
pub const ExtendedOpcode = enum(u12) {
    /// Halts execution.
    Halt = 0x00f,

    /// Writes the content of accumulator to stderr.
    OutputNumeric = 0x010,

    /// Writes the lower eight bits of accumulator interpreted as ASCII to stderr.
    OutputChar = 0x011,

    /// Writes \n to stderr.
    OutputLinefeed = 0x012,
};

pub const OidaVm = struct {
    memory: [4096]u16 = [_]u16{0} ** 4096,
    accumulator: u16 = 0,
    instruction_ptr: u12 = 0,

    /// Executes a single instruction
    fn exec(this: *OidaVm, op: Opcode, addr: u12) void {
        switch (op) {
            .NoOp => return,
            .Fetch => this.accumulator = this.memory[addr],
            .IncBy => if (@intCast(u32, this.accumulator) + this.memory[addr] <= 65535) {
                this.accumulator += this.memory[addr];
            } else {
                this.accumulator = 65535;
            },
            .Minus => if (this.accumulator >= this.memory[addr]) {
                this.accumulator -= this.memory[addr];
            } else {
                this.accumulator = 0;
            },

            .Jump => this.instruction_ptr = addr - 1, // The continuation of eval()'s loop will increase iptr by one
            .JumpEZ => if (this.accumulator == 0) {
                this.instruction_ptr = addr - 1;
            } else return,
            .Write => this.memory[addr] = this.accumulator,
            .Extend => switch (@intToEnum(ExtendedOpcode, addr)) {
                .Halt => return, // Handled by eval()
                .OutputNumeric => std.debug.warn("{}", this.accumulator),
                .OutputChar => std.debug.warn("{c}", @truncate(u8, this.accumulator)),
                .OutputLinefeed => std.debug.warn("\n"),
            },
        }
    }

    /// Starts to evaluate memory as instructions starting at `addr`.
    /// Invalid opcodes invoke safety-checked UB, so try to avoid them.
    fn eval(this: *OidaVm, addr: u12) void {
        this.instruction_ptr = addr;
        while (this.instruction_ptr < 4095) : (this.instruction_ptr += 1) {
            const address: u12 = @truncate(u12, this.memory[this.instruction_ptr]);
            const operation: u4 = @intCast(u4, this.memory[this.instruction_ptr] >> 12);
            if (this.memory[this.instruction_ptr] == 0xf00f) return; // Extend-Halt opcode
            this.exec(@intToEnum(Opcode, operation), address);
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
