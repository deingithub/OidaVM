const std = @import("std");
usingnamespace @import("oidavm.zig");
const parser = @import("parser.zig");

const RunMode = enum {
    Debug,
    Run,
};

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();
    const alloc = &allocator.allocator;

    var arguments = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, arguments);

    if (arguments.len < 2 or std.mem.eql(u8, arguments[1], "help") or std.mem.eql(u8, arguments[1], "--help")) {
        printUsageAndExit();
    }

    var mode: RunMode = blk: {
        if (std.mem.eql(u8, arguments[1], "run")) {
            break :blk .Run;
        } else if (std.mem.eql(u8, arguments[1], "dbg")) {
            break :blk .Debug;
        } else {
            std.debug.warn("unknown argument {}\n", .{arguments[1]});
            printUsageAndExit();
        }
    };

    var file = try std.fs.cwd().openFile(arguments[2], .{});
    defer file.close();
    const file_content = try file.inStream().readAllAlloc(alloc, try file.getEndPos());

    var timestamp = std.time.timestamp(); // `var` to avoid comptime initialization of RNG
    var vm: OidaVm = .{
        .memory = try parser.assemble(file_content),
        .rng = std.rand.DefaultPrng.init(timestamp).random,
    };

    // Just run the program and exit
    if (mode == .Run) {
        const entry_point = if (arguments.len == 4)
            (std.fmt.parseInt(u12, arguments[3], 16) catch 0)
        else
            0;
        vm.eval(entry_point);
        return;
    }

    // Run oiDB REPL
    std.debug.warn(
        "Welcome to oiDB!\n{}\noiDB@{X:0^3}) ",
        .{
            oidb_usage,
            vm.instruction_ptr,
        },
    );

    var breakpoints = std.ArrayList(u12).init(alloc);
    var in_buffer = std.ArrayList(u8).init(alloc);
    repl: while (true) : (std.debug.warn("\noiDB@{X:0^3}) ", .{vm.instruction_ptr})) {
        try std.io.getStdIn().inStream().readUntilDelimiterArrayList(&in_buffer, '\n', 1024);
        var tokens = std.mem.tokenize(in_buffer.items, " ");
        const instruction_token = tokens.next() orelse continue;
        switch (instruction_token[0]) {
            'h', '?' => {
                // Display help
                std.debug.warn("{}", .{oidb_usage});
            },
            'n' => {
                // Step to next instruction
                if (vm.memory[vm.instruction_ptr] == 0xf00f) {
                    std.debug.warn("Reached cease instruction", .{});
                    continue :repl;
                } else {
                    vm.step();
                    vm.instruction_ptr += 1;
                }
            },
            'd' => {
                // Dump VM state
                std.debug.warn("\n", .{});
                vm.dump();
            },
            'q' => {
                // Exit
                std.debug.warn("\n", .{});
                std.process.exit(0);
            },
            'i' => {
                // Set instruction pointer
                const address_token = tokens.next() orelse continue;
                const value = std.fmt.parseInt(u12, address_token, 16) catch continue;
                vm.instruction_ptr = value;
                std.debug.warn("Set instruction pointer to 0x{X:0^3}", .{value});
            },
            'a' => {
                // Set ACC
                const value_token = tokens.next() orelse continue;
                const value = std.fmt.parseInt(u16, value_token, 16) catch continue;
                vm.accumulator = value;
                std.debug.warn("Set ACC to 0x{X:0^4}", .{value});
            },
            's' => {
                // Set arbitrary memory
                const address_token = tokens.next() orelse continue;
                const value_token = tokens.next() orelse continue;
                const address = std.fmt.parseInt(u12, address_token, 16) catch continue;
                const value = std.fmt.parseInt(u16, value_token, 16) catch continue;
                vm.memory[address] = value;
                std.debug.warn("Set memory at 0x{X:0^3} to 0x{X:0^4}", .{ address, value });
            },
            'p' => {
                // Print memory
                const address_token = tokens.next() orelse continue;
                const address = std.fmt.parseInt(u12, address_token, 16) catch continue;
                std.debug.warn("Memory at 0x{X:0^3}: 0x{X:0^4}", .{ address, vm.memory[address] });
            },
            'b' => {
                // Add breakpoint
                const address_token = tokens.next() orelse continue;
                const address = std.fmt.parseInt(u12, address_token, 16) catch continue;
                for (breakpoints.items) |bp| {
                    if (bp == address) {
                        std.debug.warn("Breakpoint already present at 0x{X:0^3}", .{address});
                        continue :repl;
                    }
                }
                try breakpoints.append(address);
                std.debug.warn("Added breakpoint at 0x{X:0^3}", .{address});
            },
            'l' => {
                // List breakpoints
                const num_breakpoints = breakpoints.items.len;
                const fmt_pluralize = if (num_breakpoints == 0) "s" else if (num_breakpoints == 1) ":" else "s:";

                std.debug.warn("{} Breakpoint{} ", .{
                    num_breakpoints,
                    fmt_pluralize,
                });
                for (breakpoints.items) |bp, i| {
                    const fmt_cond_comma = if (i == num_breakpoints - 1) "" else ", ";
                    std.debug.warn("0x{X:0^3}{}", .{
                        bp,
                        fmt_cond_comma,
                    });
                }
            },
            'r' => {
                // Remove breakpoint
                const address_token = tokens.next() orelse continue;
                const address = std.fmt.parseInt(u12, address_token, 16) catch continue;
                for (breakpoints.items) |bp, i| {
                    if (bp == address) {
                        _ = breakpoints.orderedRemove(i);
                        std.debug.warn("Removed breakpoint at 0x{X:0^3}", .{address});
                        continue :repl;
                    }
                }
                std.debug.warn("No breakpoint at 0x{X:0^3} to remove", .{address});
            },
            'c' => {
                // Continue execution up to next breakpoint
                const pointer_at_start = vm.instruction_ptr;
                while (vm.instruction_ptr < 4095) : (vm.instruction_ptr += 1) {
                    if (vm.memory[vm.instruction_ptr] == 0xf00f) {
                        std.debug.warn("Reached cease instruction", .{});
                        continue :repl;
                    }
                    for (breakpoints.items) |bp| {
                        if (vm.instruction_ptr == bp and !(pointer_at_start == bp)) continue :repl;
                    }
                    vm.step();
                }
            },

            else => continue,
        }
    }
}

fn printUsageAndExit() noreturn {
    std.debug.warn("{}", .{oidavm_usage});
    std.process.exit(0);
}

const oidavm_usage =
    \\OidaVM 0.1
    \\
    \\Usage: ovm run [file.oidasm] <entry point>
    \\       ovm dbg [file.oidasm]
    \\       ovm help
    \\
;
const oidb_usage =
    \\oiDB Commands
    \\ d    dump VM's state
    \\ q    quit oiDB
    \\ h,?  display this message
    \\
    \\ n    execute and increase instruction pointer
    \\ i    set the instruction pointer: i 000
    \\ a    set ACC: a 0000
    \\ s    set memory: s 000 f00f
    \\ p    print memory: p 000
    \\
    \\ b    set breakpoint: b 000
    \\ l    list breakpoints
    \\ r    remove breakpoint: r 000
    \\ c    continue execution to next breakpoint
    \\
;
