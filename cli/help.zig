const std = @import("std");

pub const text =
    \\zixel
    \\  help
    \\  version
    \\  new <name> [--sample <sample>]
    \\
;

pub fn run(stdout: *std.Io.Writer) !void {
    try stdout.print("{s}", .{text});
}
