pub const Engine = @import("core/Engine.zig");
pub const Renderer = @import("core/Renderer.zig");
pub const Scene = @import("core/Scene.zig");

pub const math = struct {
    const Vec2 = @import("./math/vec2.zig");
};

// Convienence exports

pub const EngineConfig = Engine.Config;

pub const Vec2 = math.Vec2;

// pub fn bufferedPrint() !void {
//     // Stdout is for the actual output of your application, for example if you
//     // are implementing gzip, then only the compressed bytes should be sent to
//     // stdout, not any debugging messages.
//     var stdout_buffer: [1024]u8 = undefined;
//     var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
//     const stdout = &stdout_writer.interface;

//     try stdout.print("Run `zig build test` to run the tests.\n", .{});

//     try stdout.flush(); // Don't forget to flush!
// }
