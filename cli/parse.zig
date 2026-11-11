const std = @import("std");
const eql = std.mem.eql;

const Command = @import("command.zig").Command;

pub const ParseError = error{
    InvalidCommand,
    MissingValue,
};

/// Returned strings borrow from args.
pub fn parseCommand(args: []const [:0]const u8) ParseError!Command {
    const first = if (args.len > 1) args[1] else return .{ .help = {} };

    // Global flags (no subcommand required)
    if (eql(u8, first, "help") or eql(u8, first, "-h") or eql(u8, first, "--help"))
        return .{ .help = {} };

    if (eql(u8, first, "version") or eql(u8, first, "-V") or eql(u8, first, "--version"))
        return .{ .version = {} };

    // Only "new" supported so far
    if (!eql(u8, first, "new"))
        return ParseError.InvalidCommand;

    // Parse: zixel new [flags...] <name> [flags...]
    var stop_options = false;
    var name: ?[]const u8 = null;
    var sample: ?[]const u8 = null;

    var index: usize = 2;
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
        if (name != null) return ParseError.InvalidCommand;
        name = arg;
    }

    return .{ .new = .{ .name = name orelse return ParseError.MissingValue, .sample = sample } };
}

test "new takes one name; flags are never mistaken for it" {
    const new = (try parseCommand(&.{ "zixel", "new", "game" })).new;
    try std.testing.expectEqualStrings("game", new.name);
    try std.testing.expect(new.sample == null);

    // Flags may come before or after the name.
    for ([_][]const [:0]const u8{
        &.{ "zixel", "new", "--sample", "physics", "game" },
        &.{ "zixel", "new", "game", "--sample", "physics" },
    }) |args| {
        const with_sample = (try parseCommand(args)).new;
        try std.testing.expectEqualStrings("game", with_sample.name);
        try std.testing.expectEqualStrings("physics", with_sample.sample.?);
    }

    try std.testing.expect((try parseCommand(&.{ "zixel", "new", "--help" })) == .help);
    try std.testing.expectEqualStrings("-odd", (try parseCommand(&.{ "zixel", "new", "--", "-odd" })).new.name);

    try std.testing.expectError(ParseError.MissingValue, parseCommand(&.{ "zixel", "new" }));
    try std.testing.expectError(ParseError.MissingValue, parseCommand(&.{ "zixel", "new", "--sample", "physics" }));
    try std.testing.expectError(ParseError.MissingValue, parseCommand(&.{ "zixel", "new", "game", "--sample" }));
    try std.testing.expectError(ParseError.InvalidCommand, parseCommand(&.{ "zixel", "new", "--unknown", "game" }));
    try std.testing.expectError(ParseError.InvalidCommand, parseCommand(&.{ "zixel", "new", "one", "two" }));
    try std.testing.expectError(ParseError.InvalidCommand, parseCommand(&.{ "zixel", "frobnicate" }));
}

test "global commands" {
    try std.testing.expect((try parseCommand(&.{"zixel"})) == .help);
    try std.testing.expect((try parseCommand(&.{ "zixel", "--version" })) == .version);
    try std.testing.expect((try parseCommand(&.{ "zixel", "help" })) == .help);
}

test {
    // Pull in the tests of the command implementations.
    _ = @import("new.zig");
}
