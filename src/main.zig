const std = @import("std");
usingnamespace @import("oidavm.zig");

pub fn main() void {
    var vm = OidaVm{};
    std.debug.warn("Hello World:\n");
    hello_world(&vm);
    vm.dump();
    std.debug.warn("Count to 100:\n");
    count_to_100(&vm);
    vm.dump();
    std.debug.warn("Fourier Sequence:\n");
    fourier_sequence(&vm);
    vm.dump();
}

fn global_instruction(comptime op: GlobalOpcode, comptime addr: u12) u16 {
    return (u16(@enumToInt(op)) << 12) + addr;
}
fn paged_instruction(comptime op: PagedOpcode, comptime addr: u8) u16 {
    return (u16(@enumToInt(op)) << 8) + addr;
}
fn extended_instruction(comptime op: ExtendedOpcode) u16 {
    return 0xf000 + u16(@enumToInt(op));
}

fn hello_world(vm: *OidaVm) void {
    vm.flush();
    const hello = "Hello, World!\n";
    vm.load(0x14, global_instruction(.PageAndJump, 0x015));
    inline for (hello) |c, i| {
        vm.load(@intCast(u8, i), c); // Write character into i
        vm.load(@intCast(u8, (i * 2) + 0x15), paged_instruction(.Fetch, i)); // Write Fetch i into 0x15 plus i * 2
        vm.load(@intCast(u8, (i * 2 + 1) + 0x15), extended_instruction(.OutputChar)); // Write OutputChar into 0x15 plus i * 2, plus 1
        // i.e. i = 0 => 100, 101; i = 1 => 102, 103; i = 2 => 104, 105; …
    }
    vm.load(0x15 + hello.len * 2, 0xf00f); // Write Halt after last instruction
    vm.eval(0x14);
}

fn count_to_100(vm: *OidaVm) void {
    vm.flush();

    const _one = 0x0;
    const _counter = 0x1;
    const _ninetynine = 0x2;
    vm.load(_one, 1);
    vm.load(_ninetynine, 99);
    vm.load(0x5, global_instruction(.PageAndJump, 0x006));
    vm.load(0x6, paged_instruction(.IncrementBy, _one));
    vm.load(0x7, paged_instruction(.Write, _counter));
    vm.load(0x8, paged_instruction(.Minus, _ninetynine));
    vm.load(0x9, paged_instruction(.JumpEZ, 0x10));
    vm.load(0xa, paged_instruction(.Fetch, _counter));
    vm.load(0xb, extended_instruction(.OutputNumeric));
    vm.load(0xc, extended_instruction(.OutputLinefeed));
    vm.load(0xd, extended_instruction(.Halt));

    vm.load(0x10, paged_instruction(.Fetch, _counter));
    vm.load(0x11, paged_instruction(.Jump, 0x5));
    vm.eval(0x5);
}

fn fourier_sequence(vm: *OidaVm) void {
    vm.flush();

    const _old = 0x0;
    vm.load(_old, 1);

    const _new = 0x1;
    vm.load(_new, 1);

    const _oldtemp = 0x2;

    const _overflow_full = 0x3;
    vm.load(_overflow_full, 65534);
    const _overflow_acc = 0x4;

    vm.load(0x6, global_instruction(.PageAndJump, 0x007));
    vm.load(0x7, paged_instruction(.Fetch, _old));
    vm.load(0x8, paged_instruction(.Write, _oldtemp));
    vm.load(0x9, paged_instruction(.IncrementBy, _new));
    vm.load(0xa, paged_instruction(.Write, _overflow_acc));
    vm.load(0xb, paged_instruction(.Minus, _overflow_full));
    vm.load(0xc, paged_instruction(.JumpEZ, 0x10));
    vm.load(0xd, extended_instruction(.Halt));

    vm.load(0x10, paged_instruction(.Fetch, _overflow_acc));
    vm.load(0x11, paged_instruction(.Write, _old));
    vm.load(0x12, paged_instruction(.Fetch, _oldtemp));
    vm.load(0x13, paged_instruction(.Write, _new));
    vm.load(0x14, extended_instruction(.OutputNumeric));
    vm.load(0x15, extended_instruction(.OutputLinefeed));
    vm.load(0x16, paged_instruction(.Jump, 0x6));
    vm.eval(0x7);
}
