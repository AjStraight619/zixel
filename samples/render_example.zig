const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Renderer = zixel.Renderer;

pub const ExampleScene = struct {
    pub const name = "render_example";

    ctx: Engine.Ctx,
    time: f32,

    pub fn init(ctx: Engine.Ctx) !ExampleScene {
        return .{
            .ctx = ctx,
            .time = 0.0,
        };
    }

    pub fn update(self: *ExampleScene, dt: f32) void {
        self.time += dt;
    }

    pub fn render(self: *ExampleScene) void {
        const r = self.ctx.renderer;

        // Static boxes
        r.drawRect(50, 50, 200, 150, Renderer.Color.red);
        r.drawRect(300, 100, 150, 200, Renderer.Color.green);
        r.drawRect(50, 300, 120, 80, Renderer.Color.yellow);

        // Animated box: wiggle horizontally
        const base_x: f32 = 500;
        const base_y: f32 = 50;
        const amplitude: f32 = 50;
        const speed: f32 = 2.0;

        const offset: f32 = @sin(self.time * speed) * amplitude;
        r.drawRect(base_x + offset, base_y, 100, 100, Renderer.Color.blue);
    }

    pub fn deinit(self: *ExampleScene, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Render Example",
        },
    });

    try engine.createScene(ExampleScene);
    engine.run();
}
