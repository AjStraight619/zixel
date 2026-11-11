const std = @import("std");
const buildinfo = @import("zixel_buildinfo");
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
        .new => |c| command.new.run(alloc, init.io, stdout, std.Io.Dir.cwd(), c, buildinfo.source_dir) catch |err| {
            // Refusals have already been explained on stdout by `new`.
            switch (err) {
                error.InvalidProjectName, error.UnsupportedOption, error.DirectoryNotEmpty => {},
                else => try stdout.print("error: could not create the project: {s}\n", .{@errorName(err)}),
            }
            try stdout.flush();
            std.process.exit(1);
        },
    }

    try stdout.flush();
}
