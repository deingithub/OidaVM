const std = @import("std");
const warn = std.debug.warn;

const InstructionBlock = struct {
    instructions: std.ArrayList(Instruction),
    page: u4,
    addr: ?u12,
};

const Instruction = struct {
    opcode: []const u8,
    address: ?[]const u8,
};

const VariableDef = struct {
    value: u16,
    page: u4,
    addr: ?u12,
};

pub fn assemble(code: []const u8) ![4096]u16 {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();
    const alloc = &allocator.allocator;
    var had_errors = false;

    var entry_point: ?[]const u8 = null;
    var current_page: u4 = 0;
    var vardefs = std.StringHashMap(VariableDef).init(alloc);
    var blocks = std.StringHashMap(InstructionBlock).init(alloc);
    var current_block: ?InstructionBlock = null;
    var current_block_name: ?[]const u8 = null;

    // Parsing stage
    var line_number: usize = 1;
    var lines = std.mem.split(code, "\n");
    while (lines.next()) |line| : (line_number += 1) {
        var tokens = std.mem.tokenize(line, " ");
        const first_token = tokens.next() orelse continue; // Skip empty lines
        switch (first_token[0]) {
            '#' => continue, // Skip comment lines
            '@' => { // Parser Directives
                if (std.mem.eql(u8, first_token, "@page")) {
                    // Set memory page
                    const page_token = tokens.next() orelse {
                        warn("{}: Missing page number\n", .{line_number});
                        had_errors = true;
                        continue;
                    };
                    current_page = std.fmt.parseInt(u4, page_token, 16) catch {
                        warn("{}: Invalid page number {}\n", .{ line_number, page_token });
                        had_errors = true;
                        continue;
                    };
                } else if (std.mem.eql(u8, first_token, "@entry")) {
                    // Set entry point label
                    const label_token = tokens.next() orelse {
                        warn("{}: Missing entry point label\n", .{line_number});
                        had_errors = true;
                        continue;
                    };
                    entry_point = label_token;
                } else {
                    warn("{}: Unknown directive {}\n", .{ line_number, first_token });
                    had_errors = true;
                }
            },
            '$' => { // Variable Definitions
                const variable_name = first_token;
                const value_token = tokens.next() orelse "0";
                const value = std.fmt.parseInt(u16, value_token, 16) catch {
                    warn("{}: Invalid variable value {}\n", .{ line_number, value_token });
                    had_errors = true;
                    continue;
                };
                if (vardefs.contains(variable_name)) {
                    warn("{}: Redefinition of variable {}\n", .{ line_number, variable_name });
                    had_errors = true;
                    continue;
                }
                try vardefs.putNoClobber(variable_name, .{
                    .value = value,
                    .page = current_page,
                    .addr = null,
                });
            },
            ':' => { // Instruction blocks/labels
                if (current_block) |block| {
                    // Save current block into ArrayList
                    // Both current_block_name and block have been set because this is at least the second block
                    // Also, duplicate blocks are checked during creation below, so assert there's no double
                    try blocks.putNoClobber(current_block_name.?, block);
                }
                if (first_token.len < 2) {
                    warn("{}: Missing block name\n", .{line_number});
                    had_errors = true;
                    continue;
                }
                if (blocks.contains(first_token)) {
                    warn("{}: Redefinition of block {}\n", .{ line_number, first_token });
                    had_errors = true;
                    continue;
                }
                current_block = .{
                    .instructions = std.ArrayList(Instruction).init(alloc),
                    .page = current_page,
                    .addr = null,
                };
                current_block_name = first_token;
            },
            else => {
                if (first_token.len != 5) {
                    warn("{}: Malformed instruction {}", .{ line_number, first_token });
                    had_errors = true;
                    continue;
                }
                if (current_block != null) {
                    // We can't use if-optional syntax here.
                    // TODO find out why exactly the compiler complains
                    try current_block.?.instructions.append(.{
                        .opcode = first_token,
                        .address = tokens.next(),
                    });
                } else {
                    warn("{}: Instruction outside block\n", .{line_number});
                    had_errors = true;
                    continue;
                }
            },
        }
    }

    // Save last open block into ArrayList
    if (current_block == null or current_block_name == null) {
        warn("{}: Missing any instruction block\n", .{line_number});
        had_errors = true;
    } else {
        try blocks.putNoClobber(current_block_name.?, current_block.?);
    }

    // Codegen stage
    var memory = [_]u16{0} ** 4096;

    var page: u4 = 0;

    // Iterate through all vardefs and blocks per-page and give them addresses
    while (page < 15) : (page += 1) {
        // On page 0, reserve the first instruction for the entry point
        var in_page_cursor: usize = if (page == 0) 1 else 0;
        var var_it = vardefs.iterator();
        while (var_it.next()) |vardef| {
            if (vardef.value.page != page) continue;
            vardef.value.addr = (@as(u12, page) << 8) + @truncate(u12, in_page_cursor);
            in_page_cursor += 1;
        }
        var block_it = blocks.iterator();
        while (block_it.next()) |block| {
            if (block.value.page != page) continue;
            block.value.addr = (@as(u12, page) << 8) + @truncate(u12, in_page_cursor);
            in_page_cursor += block.value.instructions.items.len;
        }
        if (in_page_cursor > 255) {
            warn("Page {} is too full [{}/256]\n", .{ page, in_page_cursor });
            had_errors = true;
            continue;
        }
    }

    // Commit vardefs into memory
    var var_iter = vardefs.iterator();
    while (var_iter.next()) |vardef| {
        memory[vardef.value.addr.?] = vardef.value.value;
    }

    // Commit blocks into memory
    var block_iter = blocks.iterator();
    while (block_iter.next()) |block| {
        for (block.value.instructions.toSlice()) |instruction, index| {
            const opcode = parse_instruction(instruction.opcode) catch {
                warn("Encountered invalid opcode {}\n", .{instruction});
                had_errors = true;
                continue;
            };
            var word: u16 = opcode;
            const truncate_address = (word >= 0x1000 and word <= 0x9fff);
            if (instruction.address) |address| {
                if (word >= 0xf000) {
                    warn("Encountered extended opcode {} with address\n", .{instruction.opcode});
                    had_errors = true;
                }
                switch (address[0]) {
                    '$' => {
                        const var_ref = vardefs.getValue(address) orelse {
                            warn("Encountered unknown variable {}\n", .{address});
                            had_errors = true;
                            continue;
                        };
                        word += if (truncate_address) @truncate(u8, var_ref.addr.?) else var_ref.addr.?;
                    },
                    ':' => {
                        const block_ref = blocks.getValue(address) orelse {
                            warn("Encountered unknown label {}\n", .{address});
                            had_errors = true;
                            continue;
                        };
                        word += if (truncate_address) @truncate(u8, block_ref.addr.?) else block_ref.addr.?;
                    },
                    else => {
                        warn("Encountered malformed address {}\n", .{address});
                        had_errors = true;
                    },
                }
            }
            memory[block.value.addr.? + index] = word;
        }
    }

    if (entry_point == null) {
        warn("No entry point found\n", .{});
        had_errors = true;
        return error.ParserFailure;
    } else if (!blocks.contains(entry_point.?)) {
        warn("Unknown entry point label {}\n", .{entry_point});
        had_errors = true;
        return error.ParserFailure;
    }
    memory[0] = (@as(u16, @enumToInt(GlobalOpcode.PageAndJump)) << 12) + blocks.getValue(entry_point.?).?.addr.?;

    return if (had_errors) error.ParserFailure else memory;
}

usingnamespace @import("oidavm.zig");
const eql = std.mem.eql;
fn parse_instruction(token: []const u8) !u16 {
    if (eql(u8, token, "noopr")) {
        // Starting here: Global Opcodes
        return @as(u16, @enumToInt(GlobalOpcode.NoOp)) << 12;
    } else if (eql(u8, token, "pgjmp")) {
        return @as(u16, @enumToInt(GlobalOpcode.PageAndJump)) << 12;
    } else if (eql(u8, token, "fftch")) {
        return @as(u16, @enumToInt(GlobalOpcode.FarFetch)) << 12;
    } else if (eql(u8, token, "fwrte")) {
        return @as(u16, @enumToInt(GlobalOpcode.FarWrite)) << 12;
    } else if (eql(u8, token, "incby")) {
        // Starting here: Paged Opcodes
        return @as(u16, @enumToInt(PagedOpcode.IncrementBy)) << 8;
    } else if (eql(u8, token, "minus")) {
        return @as(u16, @enumToInt(PagedOpcode.Minus)) << 8;
    } else if (eql(u8, token, "fetch")) {
        return @as(u16, @enumToInt(PagedOpcode.Fetch)) << 8;
    } else if (eql(u8, token, "write")) {
        return @as(u16, @enumToInt(PagedOpcode.Write)) << 8;
    } else if (eql(u8, token, "jmpto")) {
        return @as(u16, @enumToInt(PagedOpcode.Jump)) << 8;
    } else if (eql(u8, token, "jmpez")) {
        return @as(u16, @enumToInt(PagedOpcode.JumpEZ)) << 8;
    } else if (eql(u8, token, "cease")) {
        // Starting here: Extended Opcodes
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.Halt));
    } else if (eql(u8, token, "outnm")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.OutputNumeric));
    } else if (eql(u8, token, "outch")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.OutputChar));
    } else if (eql(u8, token, "outhx")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.OutputHex));
    } else if (eql(u8, token, "outlf")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.OutputLinefeed));
    } else if (eql(u8, token, "inacc")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.InputACC));
    } else if (eql(u8, token, "rando")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.Randomize));
    } else if (eql(u8, token, "augmt")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.Augment));
    } else if (eql(u8, token, "dimin")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.Diminish));
    } else if (eql(u8, token, "shfl4")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.ShiftLeftFour));
    } else if (eql(u8, token, "shfl1")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.ShiftLeftOne));
    } else if (eql(u8, token, "shfr4")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.ShiftRightFour));
    } else if (eql(u8, token, "shfr1")) {
        return 0xf000 + @as(u16, @enumToInt(ExtendedOpcode.ShiftRightOne));
    }
    return error.InvalidOpcode;
}
