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

fn instruction(comptime op: Opcode, comptime address: u12) u16 {
    return (@intCast(u16, @enumToInt(op)) << 12) + address;
}

fn hello_world(vm: *OidaVm) void {
    vm.flush();
    const hello = "Hello, World!\n";
    inline for (hello) |c, i| {
        vm.load(@intCast(u8, i), c); // Write character into i
        vm.load(@intCast(u8, (i * 2) + 100), instruction(.Fetch, @intCast(u8, i))); // Write READ i into 100 plus i * 2
        vm.load(@intCast(u8, (i * 2 + 1) + 100), instruction(.Extend, @enumToInt(ExtendedOpcode.OutputChar))); // Write OUTPUTCHAR into 100 plus i * 2, plus 1
        // i.e. i = 0 => 100, 101; i = 1 => 102, 103; i = 2 => 104, 105; …
    }
    vm.load(100 + hello.len * 2, instruction(.Extend, @enumToInt(ExtendedOpcode.Halt))); // Write HALT after last instruction
    vm.eval(100);
}

fn count_to_100(vm: *OidaVm) void {
    vm.flush();

    const _one = 0;
    const _counter = 1;
    const _ninetynine = 2;
    vm.load(_one, 1);
    vm.load(_ninetynine, 99);
    vm.load(100, instruction(.IncBy, _one));
    vm.load(101, instruction(.Write, _counter));
    vm.load(102, instruction(.Minus, _ninetynine));
    vm.load(103, instruction(.JumpEZ, 110));
    vm.load(104, instruction(.Fetch, _counter));
    vm.load(105, instruction(.Extend, @enumToInt(ExtendedOpcode.OutputNumeric)));
    vm.load(106, instruction(.Extend, @enumToInt(ExtendedOpcode.OutputLinefeed)));
    vm.load(107, instruction(.Extend, @enumToInt(ExtendedOpcode.Halt)));

    vm.load(110, instruction(.Fetch, _counter));
    vm.load(111, instruction(.Jump, 100));
    vm.eval(100);
}

fn fourier_sequence(vm: *OidaVm) void {
    vm.flush();

    const _old = 25;
    vm.load(_old, 1);

    const _new = 30;
    vm.load(_new, 1);

    const _oldtemp = 35;

    const _overflow_full = 40;
    vm.load(_overflow_full, 65534);
    const _overflow_acc = 45;

    vm.load(100, instruction(.Fetch, _old));
    vm.load(101, instruction(.Write, _oldtemp));
    vm.load(102, instruction(.IncBy, _new));
    vm.load(103, instruction(.Write, _overflow_acc));
    vm.load(104, instruction(.Minus, _overflow_full));
    vm.load(105, instruction(.JumpEZ, 110));
    vm.load(106, instruction(.Extend, @enumToInt(ExtendedOpcode.Halt)));

    vm.load(110, instruction(.Fetch, _overflow_acc));
    vm.load(111, instruction(.Write, _old));
    vm.load(112, instruction(.Fetch, _oldtemp));
    vm.load(113, instruction(.Write, _new));
    vm.load(114, instruction(.Extend, @enumToInt(ExtendedOpcode.OutputNumeric)));
    vm.load(115, instruction(.Extend, @enumToInt(ExtendedOpcode.OutputLinefeed)));
    vm.load(116, instruction(.Jump, 100));
    vm.eval(100);
}
