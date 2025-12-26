const std = @import("std");
const zixel = @import("zixel_new");

const Engine = zixel.Engine;

/// Standalone Zixel Editor
/// This runs the engine with no scene, just the editor overlay.
/// Use this for creating new scenes from scratch.
/// For editing scenes that have code, run your game with:
///   zig build run -Deditor=true
pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 1600,
            .height = 900,
            .title = "Zixel Editor",
        },
    });

    // No scene - just the editor overlay
    engine.run();
}
