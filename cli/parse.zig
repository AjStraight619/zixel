const std = @import("std");
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;

const Command = @import("command.zig").Command;

pub const ParseError = error{
    InvalidCommand,
    MissingValue,
};

/// Returned strings borrow from args.
pub fn parseCommand(args: []const [:0]const u8) !Command {
    const first = if (args.len > 1) args[1] else return .{ .help = {} };

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

    if (args.len < 3) return ParseError.MissingValue;
    const name = args[2];

    var sample: ?[]const u8 = null;

    var index: usize = 3;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (!stop_options) {
            if (eql(u8, arg, "--")) {
                stop_options = true;
                continue;
            }
            if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                return .{ .help = {} }; // or you can introduce help topic later
            }
            if (eql(u8, arg, "--sample")) {
                index += 1;
                if (index == args.len) return ParseError.MissingValue;
                sample = args[index];
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
