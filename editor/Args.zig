const std = @import("std");
const Args = @This();

project_path: []const u8 = ".",
log_file: ?[]const u8 = null,
debug_scopes: std.ArrayList([]const u8) = .empty,
help: bool = false,

pub const usage =
    \\Usage: zixel_editor [project-path] [options]
    \\
    \\  --log-file <path>    Append logs to a file (stderr and console stay enabled)
    \\  --debug-log <scope>  Enable debug logs for this scope; may be repeated
    \\  -h, --help           Show this help
    \\  --                   Treat remaining arguments as positional
    \\
;

/// All strings borrow from argv. Free only the debug-scope list with deinit.
pub fn parse(alloc: std.mem.Allocator, argv: []const [:0]const u8) !Args {
    var result = Args{};
    errdefer result.deinit(alloc);
    var have_project = false;
    var options = true;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (options and std.mem.eql(u8, arg, "--")) {
            options = false;
        } else if (options and (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h"))) {
            result.help = true;
        } else if (options and (std.mem.eql(u8, arg, "--log-file") or std.mem.eql(u8, arg, "--debug-log"))) {
            i += 1;
            if (i == argv.len or argv[i].len == 0 or std.mem.startsWith(u8, argv[i], "--")) return error.MissingValue;
            if (std.mem.eql(u8, arg, "--log-file")) {
                result.log_file = argv[i];
            } else try result.debug_scopes.append(alloc, argv[i]);
        } else {
            if (options and std.mem.startsWith(u8, arg, "-")) return error.UnknownOption;
            if (have_project) return error.UnexpectedArgument;
            result.project_path = arg;
            have_project = true;
        }
    }
    return result;
}

pub fn deinit(self: *Args, alloc: std.mem.Allocator) void {
    self.debug_scopes.deinit(alloc);
}

test "logging flags preserve project path and repeated debug scopes" {
    var args = try Args.parse(std.testing.allocator, &.{ "--debug-log", "zixel_physics", "my-game", "--log-file", "editor.log", "--debug-log", "zixel_nav" });
    defer args.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("my-game", args.project_path);
    try std.testing.expectEqualStrings("editor.log", args.log_file.?);
    try std.testing.expectEqual(@as(usize, 2), args.debug_scopes.items.len);
    try std.testing.expectEqualStrings("zixel_nav", args.debug_scopes.items[1]);
}

test "invalid flags are rejected without leaking parsed options" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.MissingValue, Args.parse(alloc, &.{ "--debug-log", "zixel_physics", "--log-file" }));
    try std.testing.expectError(error.MissingValue, Args.parse(alloc, &.{ "--log-file", "--help" }));
    try std.testing.expectError(error.UnknownOption, Args.parse(alloc, &.{"--unknown"}));
    try std.testing.expectError(error.UnexpectedArgument, Args.parse(alloc, &.{ "one", "two" }));
    var args = try Args.parse(alloc, &.{ "--", "-project" });
    defer args.deinit(alloc);
    try std.testing.expectEqualStrings("-project", args.project_path);
}
