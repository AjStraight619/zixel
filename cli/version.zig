const std = @import("std");
const buildinfo = @import("zixel_buildinfo");

pub fn run(stdout: *std.Io.Writer) !void {
    try stdout.print("{s}\n", .{buildinfo.version});
}
