const std = @import("std");
const Alignment = std.mem.Alignment;
const parseCommand = @import("parse.zig").parseCommand;
const command = @import("command.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const cmd = parseCommand(args) catch {
        try command.help.run(stdout);
        try stdout.flush();
        std.process.exit(1);
    };

    switch (cmd) {
        .help => try command.help.run(stdout),
        .version => try command.version.run(stdout),
        .new => |c| try command.new.run(alloc, stdout, c),
    }

    try stdout.flush();
}
