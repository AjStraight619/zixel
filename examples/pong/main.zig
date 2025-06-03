const std = @import("std");
const zixel = @import("zixel");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var engine = try zixel.Engine.init(allocator, .{
        .window_width = 1000,
        .window_height = 700,
        .window_title = "Pong",
        .target_fps = 200,
    });
    defer engine.deinit();

    try engine.run();
}
