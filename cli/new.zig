const std = @import("std");
const NewArgs = @import("command.zig").NewArgs;

pub fn run(alloc: std.mem.Allocator, stdout: *std.Io.Writer, c: NewArgs) !void {
    _ = alloc;
    try stdout.print("new project: {s}\n", .{c.name});
    if (c.sample) |s| try stdout.print("sample: {s}\n", .{s});
}
