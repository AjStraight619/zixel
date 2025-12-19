const std = @import("std");
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;

const Command = @import("command.zig").Command;

pub const ParseError = error{
    InvalidCommand,
    MissingValue,
};

pub fn parseCommand(alloc: Allocator) !Command {
    var it = try std.process.argsWithAllocator(alloc);
    defer it.deinit();

    _ = it.next(); // exe name

    const first = it.next() orelse return .{ .help = {} };

    // Global flags (no subcommand required)
    if (eql(u8, first, "help") or eql(u8, first, "-h") or eql(u8, first, "--help"))
        return .{ .help = {} };

    if (eql(u8, first, "version") or eql(u8, first, "-V") or eql(u8, first, "--version"))
        return .{ .version = {} };

    // Only "new" supported so far
    if (!eql(u8, first, "new"))
        return ParseError.InvalidCommand;

    // Parse: zixel new <name> [flags...]
    var stop_options = false;

    const name = it.next() orelse return ParseError.MissingValue;

    var sample: ?[]const u8 = null;

    while (it.next()) |arg| {
        if (!stop_options) {
            if (eql(u8, arg, "--")) {
                stop_options = true;
                continue;
            }
            if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                return .{ .help = {} }; // or you can introduce help topic later
            }
            if (eql(u8, arg, "--sample")) {
                sample = it.next() orelse return ParseError.MissingValue;
                continue;
            }
            // Unknown flag
            if (arg.len > 0 and arg[0] == '-') return ParseError.InvalidCommand;
        }

        // Extra positional args not supported yet
        return ParseError.InvalidCommand;
    }

    return .{ .new = .{ .name = name, .sample = sample } };
}
