const std = @import("std");

pub const Opcode = enum(u8) {
    /// Skips instruction.
    Noop = 0x0,
    /// Reads address into accumulator.
    Read = 0x1,
    /// Dereferences address, adds to accumulator. Overflow gets silently truncated to 65535.
    Add = 0x2,
    /// Dereferences address, substracts from accumulator. Overflow gets silently truncated to 0.
    Sub = 0x3,
    /// Prints numeric value of accumulator to stderr.
    Output = 0x4,
    /// Stops execution.
    Halt = 0x5,
    /// Dereferences address, prints ASCII representation of lower 8 bits to stderr.
    OutputChar = 0x6,
    /// Unconditionally continues execution at address.
    Jump = 0x7,
    /// Continues execution at address if accumulator is 0, otherwise skips instruction.
    JumpEqualsZero = 0x8,
    /// Writes content of accumulator to address.
    Write = 0x9,
};

pub const OidaVm = struct {
    memory: [256]u16 = [_]u16{0} ** 256,
    accumulator: u16 = 0,
    instruction_ptr: u8 = 0,

    /// Executes a single instruction
    fn exec(this: *OidaVm, op: Opcode, addr: u8) void {
        switch (op) {
            .Noop => return,
            .Read => this.accumulator = this.memory[addr],
            .Add => if (@intCast(u32, this.accumulator) + this.memory[addr] <= 65535) {
                this.accumulator += this.memory[addr];
            } else {
                this.accumulator = 65535;
            },
            .Sub => if (this.accumulator >= this.memory[addr]) {
                this.accumulator -= this.memory[addr];
            } else {
                this.accumulator = 0;
            },
            .Output => std.debug.warn("{}", this.accumulator),
            .Halt => return, // Handled by eval()
            .OutputChar => std.debug.warn("{c}", @truncate(u8, this.accumulator)),
            .Jump => this.instruction_ptr = addr - 1, // The continuation of eval()'s loop will increase iptr by one
            .JumpEqualsZero => if (this.accumulator == 0) {
                this.instruction_ptr = addr - 1;
            } else return,
            .Write => this.memory[addr] = this.accumulator,
        }
    }

    /// Starts to evaluate memory as instructions starting at `addr`.
    /// Invalid opcodes invoke safety-checked UB, so try to avoid them.
    fn eval(this: *OidaVm, addr: u8) void {
        this.instruction_ptr = addr;
        while (this.instruction_ptr < 255) : (this.instruction_ptr += 1) {
            const address: u8 = @truncate(u8, this.memory[this.instruction_ptr]);
            const operation: u8 = @intCast(u8, this.memory[this.instruction_ptr] >> 8);
            if (operation == @enumToInt(Opcode.Halt)) return;
            this.exec(@intToEnum(Opcode, operation), address);
        }
    }

    /// Writes `value` to `addr` in the VM's memory.
    fn load(this: *OidaVm, addr: u8, value: u16) void {
        this.memory[addr] = value;
    }

    /// Dumps the VM's state to stderr.
    fn dump(this: OidaVm) void {
        std.debug.warn("== OidaVM dump ==\n");
        std.debug.warn("Instruction Pointer: 0x{X:0^2}\n", this.instruction_ptr);
        std.debug.warn("Accumulator: 0x{X:0^4}\n", this.accumulator);
        std.debug.warn("Memory: \n");
        for (this.memory) |val, addr| {
            std.debug.warn("{}{}0x{X:0^2}: 0x{X:0^4}{} {}", if (addr == this.instruction_ptr) "\x1b[7m" else "", // Inverted formatting for instruction ptr
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
        this.memory = [_]u16{0} ** 256;
    }
};
