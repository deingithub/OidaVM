const std = @import("std");

pub fn parse(code: []const u8) ![4096]u16 {
    var allocator = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer allocator.deinit();
    const alloc = &allocator.allocator;

    var cursor: u12 = 0;
    var memory = [_]u16{0} ** 4096;

    var line_no: usize = 1;
    var had_errors = false;
    var name_map = std.BufMap.init(alloc);

    var lines = std.mem.separate(code, "\n");
    while (lines.next()) |line| : (line_no += 1) {
        if (line.len == 0) continue;
        switch (line[0]) {
            // Comments
            ';' => continue,
            // Name Definition
            '=' => {
                var tokens = std.mem.tokenize(line, " ");
                _ = tokens.next();
                if (tokens.next()) |name| {
                    if (tokens.next()) |value| {
                        try name_map.set(name, value);
                    } else {
                        std.debug.warn("Missing value in line {}\n", line_no);
                        had_errors = true;
                    }
                } else {
                    std.debug.warn("Missing name in line {}\n", line_no);
                    had_errors = true;
                }
            },
            // Cursor operation
            ':' => {
                var tokens = std.mem.tokenize(line, " ");
                if (tokens.next()) |op_kind| {
                    if (op_kind.len != 2) {
                        std.debug.warn("Malformed cursor operation in line {}\n", line_no);
                        had_errors = true;
                    }
                    switch (op_kind[1]) {
                        '=' => {
                            if (tokens.next()) |addr| {
                                cursor = to_address(addr, &name_map) catch |e| {
                                    std.debug.warn("Failed to parse address in line {}: {}\n", line_no, e);
                                    had_errors = true;
                                    continue;
                                };
                            } else {
                                std.debug.warn("Missing cursor position in line {}\n", line_no);
                                had_errors = true;
                            }
                        },
                        '+' => {
                            if (tokens.next()) |addr| {
                                cursor += to_address(addr, &name_map) catch |e| {
                                    std.debug.warn("Failed to parse address in line {}: {}\n", line_no, e);
                                    had_errors = true;
                                    continue;
                                };
                            } else {
                                std.debug.warn("Missing cursor position in line {}\n", line_no);
                                had_errors = true;
                            }
                        },
                        '-' => {
                            if (tokens.next()) |addr| {
                                cursor -= to_address(addr, &name_map) catch |e| {
                                    std.debug.warn("Failed to parse address in line {}: {}\n", line_no, e);
                                    had_errors = true;
                                    continue;
                                };
                            } else {
                                std.debug.warn("Missing cursor position in line {}\n", line_no);
                                had_errors = true;
                            }
                        },
                        else => {
                            std.debug.warn("Unknown cursor operation in line {}\n", line_no);
                            had_errors = true;
                        },
                    }
                } else unreachable;
            },
            // Instruction or raw data
            else => {
                var tokens = std.mem.tokenize(line, " ");
                if (tokens.next()) |token| {
                    switch (token[0]) {
                        // A word of raw data
                        '#' => memory[cursor] = std.fmt.parseInt(u16, token[1..], 16) catch {
                            std.debug.warn("Failed to parse raw data \"{}\" in line {}", token, line_no);
                            had_errors = true;
                            continue;
                        },
                        // Instruction mnemonic
                        else => {
                            if (token.len != 5) {
                                std.debug.warn("Malformed instruction \"{}\" in line {}\n", token, line_no);
                                had_errors = true;
                                continue;
                            }
                            const instruction = parse_instruction(token) catch {
                                std.debug.warn("Unknown instruction \"{}\" in line {}\n", token, line_no);
                                had_errors = true;
                                continue;
                            };
                            if (tokens.next()) |addr| {
                                memory[cursor] = instruction + (to_address(addr, &name_map) catch |e| {
                                    std.debug.warn("Failed to parse address in line {}: {}\n", line_no, e);
                                    had_errors = true;
                                    continue;
                                });
                            } else {
                                memory[cursor] = instruction;
                            }
                        },
                    }
                } else unreachable;
                cursor += 1;
            },
        }
    }
    return if (had_errors) error.ParserFailure else memory;
}

const AddressParseError = error{
    InvalidSigil,
    InvalidToken,
    UnknownName,
    InvalidAddress,
};

fn to_address(token: []const u8, names: *std.BufMap) AddressParseError!u12 {
    if (token.len < 2) {
        std.debug.warn("Invalid token \"{}\"", token);
        return error.InvalidToken;
    }
    return switch (token[0]) {
        '$' => to_address(names.get(token[1..]) orelse return error.UnknownName, names),
        '#' => std.fmt.parseInt(u12, token[1..], 16) catch return error.InvalidAddress,
        else => error.InvalidSigil,
    };
}

usingnamespace @import("oidavm.zig");
const eql = std.mem.eql;
fn parse_instruction(token: []const u8) !u16 {
    if (eql(u8, token, "noopr")) {
        // Starting here: Global Opcodes
        return u16(@enumToInt(GlobalOpcode.NoOp)) << 12;
    } else if (eql(u8, token, "pgjmp")) {
        return u16(@enumToInt(GlobalOpcode.PageAndJump)) << 12;
    } else if (eql(u8, token, "fftch")) {
        return u16(@enumToInt(GlobalOpcode.FarFetch)) << 12;
    } else if (eql(u8, token, "fwrte")) {
        return u16(@enumToInt(GlobalOpcode.FarWrite)) << 12;
    } else if (eql(u8, token, "incby")) {
        // Starting here: Paged Opcodes
        return u16(@enumToInt(PagedOpcode.IncrementBy)) << 8;
    } else if (eql(u8, token, "minus")) {
        return u16(@enumToInt(PagedOpcode.Minus)) << 8;
    } else if (eql(u8, token, "fetch")) {
        return u16(@enumToInt(PagedOpcode.Fetch)) << 8;
    } else if (eql(u8, token, "write")) {
        return u16(@enumToInt(PagedOpcode.Write)) << 8;
    } else if (eql(u8, token, "jmpto")) {
        return u16(@enumToInt(PagedOpcode.Jump)) << 8;
    } else if (eql(u8, token, "jmpez")) {
        return u16(@enumToInt(PagedOpcode.JumpEZ)) << 8;
    } else if (eql(u8, token, "cease")) {
        // Starting here: Extended Opcodes
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.Halt));
    } else if (eql(u8, token, "outnm")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.OutputNumeric));
    } else if (eql(u8, token, "outch")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.OutputChar));
    } else if (eql(u8, token, "outhx")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.OutputHex));
    } else if (eql(u8, token, "outlf")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.OutputLinefeed));
    } else if (eql(u8, token, "inacc")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.InputACC));
    } else if (eql(u8, token, "rando")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.Randomize));
    } else if (eql(u8, token, "augmt")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.Augment));
    } else if (eql(u8, token, "dimin")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.Diminish));
    } else if (eql(u8, token, "shfl4")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.ShiftLeftFour));
    } else if (eql(u8, token, "shfl1")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.ShiftLeftOne));
    } else if (eql(u8, token, "shfr4")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.ShiftRightFour));
    } else if (eql(u8, token, "shfr1")) {
        return 0xf000 + u16(@enumToInt(ExtendedOpcode.ShiftRightOne));
    }
    return error.InvalidOpcode;
}
