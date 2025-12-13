const std = @import("std");
const debug = std.debug;
const zixel = @import("zixel_new");
const Engine = zixel.Engine;
const parser = @import("cli/parse.zig");

pub fn main() !void {
    const cmd = try parser.parseArgs(std.heap.page_allocator);

    switch (cmd) {
        .help => {
            debug.print("I need help\n", .{});
            return;
        },

        .run => |r| {
            debug.print("mode={any} scene={s}\n", .{
                r.mode,
                r.scene_path orelse "(none)",
            });
        },
    }

    // var engine = try zixel.Engine.init(std.heap.page_allocator, .{});
    // engine.run();
}
