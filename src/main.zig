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

fn instruction(comptime op: Opcode, comptime address: u8) u16 {
    return (@intCast(u16, @enumToInt(op)) << 8) + address;
}

fn hello_world(vm: *OidaVm) void {
    vm.flush();
    const hello = "Hello, World!\n";
    inline for (hello) |c, i| {
        vm.load(@intCast(u8, i), c); // Write character into i
        vm.load(@intCast(u8, (i * 2) + 100), instruction(.Read, @intCast(u8, i))); // Write READ i into 100 plus i * 2
        vm.load(@intCast(u8, (i * 2 + 1) + 100), instruction(.OutputChar, 0)); // Write OUTPUTCHAR into 100 plus i * 2, plus 1
        // i.e. i = 0 => 100, 101; i = 1 => 102, 103; i = 2 => 104, 105; …
    }
    vm.load(100 + hello.len * 2, instruction(.Halt, 0)); // Write HALT after last instruction
    vm.eval(100);
}

fn count_to_100(vm: *OidaVm) void {
    vm.flush();
    vm.load(0, 1);
    vm.load(2, 99);
    vm.load(10, "\n"[0]);
    vm.load(100, instruction(.Add, 0));
    vm.load(101, instruction(.Write, 1));
    vm.load(102, instruction(.Sub, 2));
    vm.load(103, instruction(.JumpEqualsZero, 110));
    vm.load(104, instruction(.Read, 1));
    vm.load(105, instruction(.Output, 0));
    vm.load(106, instruction(.Read, 10));
    vm.load(107, instruction(.OutputChar, 0));
    vm.load(108, instruction(.Halt, 0));
    vm.load(110, instruction(.Read, 1));
    vm.load(111, instruction(.Jump, 100));
    vm.eval(100);
}

fn fourier_sequence(vm: *OidaVm) void {
    vm.flush();

    const _newline = 20;
    vm.load(_newline, "\n"[0]);

    const _old = 25;
    vm.load(_old, 1);

    const _new = 30;
    vm.load(_new, 1);

    const _oldtemp = 35;

    const _overflow_full = 40;
    vm.load(_overflow_full, 65534);
    
    const _overflow_acc = 45;

    vm.load(100, instruction(.Read, _old));
    vm.load(101, instruction(.Write, _oldtemp));
    vm.load(102, instruction(.Add, _new));
    vm.load(103, instruction(.Write, _overflow_acc));
    vm.load(104, instruction(.Sub, _overflow_full));
    vm.load(105, instruction(.JumpEqualsZero, 110));
    vm.load(106, instruction(.Halt, 0));

    vm.load(110, instruction(.Read, _overflow_acc));
    vm.load(111, instruction(.Write, _old));
    vm.load(112, instruction(.Read, _oldtemp));
    vm.load(113, instruction(.Write, _new));
    vm.load(114, instruction(.Output, 0));
    vm.load(115, instruction(.Read, _newline));
    vm.load(116, instruction(.OutputChar, 0));
    vm.load(117, instruction(.Jump, 100));
    vm.eval(100);
}