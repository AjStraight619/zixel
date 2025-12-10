const std = @import("std");
const zixel = @import("zixel_new");

const Engine = zixel.Engine;
const Sprite = zixel.Sprite;
const Renderable = zixel.Renderable;
const Color = zixel.Color;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Render Example",
        },
    });

    // Create sprites using the built-in Sprite type
    const red_box = try Sprite.create(alloc, 50, 50, 200, 150, Color.red);
    const green_box = try Sprite.create(alloc, 300, 100, 150, 200, Color.green);
    const blue_box = try Sprite.create(alloc, 500, 50, 100, 100, Color.blue);
    const yellow_box = try Sprite.create(alloc, 50, 300, 120, 80, Color.yellow);

    // Add them to the engine - they render automatically!
    try engine.addRenderable(Renderable.init(red_box));
    try engine.addRenderable(Renderable.init(green_box));
    try engine.addRenderable(Renderable.init(blue_box));
    try engine.addRenderable(Renderable.init(yellow_box));

    // Run the engine - everything is handled internally
    engine.run();
}
