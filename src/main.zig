const std = @import("std");
const zixel_new = @import("zixel_new");

const Scene = zixel_new.Scene;

// const sokol = @import("sokol");
// const math = zixel_new.math;

// const Vec2 = math.Vec2;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try zixel_new.bufferedPrint();

    // const scene_1 = Scene
}
