const std = @import("std");
usingnamespace @import("oidavm.zig");
const parser = @import("parser.zig");

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer allocator.deinit();
    const alloc = &allocator.allocator;

    var arguments = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, arguments);

    if (arguments.len == 1 or std.mem.eql(u8, arguments[1], "--help")) {
        std.debug.warn(
            \\OidaVM 0.1
            \\
            \\Usage: ovm [file.oidasm] <entry point>
            \\
        );
        return;
    }

    var file = try std.fs.File.openRead(arguments[1]);
    defer file.close();

    var buffer = try std.Buffer.initSize(alloc, 0);
    var stream = &file.inStream().stream;
    try stream.readAllBuffer(&buffer, (try file.getEndPos()) + 1);

    var vm = OidaVm {
        .memory = try parser.parse(buffer.toSliceConst())
    };
    
    const entry_point = if (arguments.len != 3) 0 else try std.fmt.parseInt(u12, arguments[2], 16);

    vm.eval(entry_point);

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