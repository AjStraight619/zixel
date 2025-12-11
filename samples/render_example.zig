const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

// Adjust these imports to match your project layout:
const Scene = zixel.Scene;
const World = zixel.World;
const Renderer = zixel.Renderer;

const Engine = zixel.Engine;

pub const ExampleScene = struct {
    world: *World,
    renderer: *Renderer,
    time: f32,

    pub fn init(world: *World, renderer: *Renderer) ExampleScene {
        return .{
            .world = world,
            .renderer = renderer,
            .time = 0.0,
        };
    }

    /// Called every frame by the Engine
    pub fn update(self: *ExampleScene, dt: f32) void {
        // Simple timer, just to show time-based movement
        self.time += dt;
    }

    /// Called every frame by the Engine between beginFrame/endFrame
    pub fn render(self: *ExampleScene) void {
        // Very simple: draw a few rectangles.
        // One of them moves left/right with time.

        const r = self.renderer;

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

        // NOTE: if you want to tie this to physics later,
        // you already have self.world here and can pull body positions.
    }

    /// Called when the Engine switches scenes or shuts down
    pub fn deinit(self: *ExampleScene, alloc: Allocator) void {
        // No heap state in this example, nothing special to free.
        // If you later add ArrayLists or other allocations to ExampleScene,
        // clean them up here, then destroy self if you allocated it.
        _ = self;
        _ = alloc;
    }
};

/// Helper: allocate ExampleScene and wrap it in the vtable-based Scene type.
///
/// Usage:
///   const scene_iface = try createScene(alloc, &engine.world, &engine.renderer);
///   engine.setScene(scene_iface);
pub fn createScene(alloc: Allocator, world: *World, renderer: *Renderer) !Scene.Scene {
    const ptr = try alloc.create(ExampleScene);
    ptr.* = ExampleScene.init(world, renderer);
    return Scene.init(ptr);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = try Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Render Example",
        },
        // .physics = .{}  // optional, defaults are used
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer);
    engine.setScene(scene_iface);

    engine.run();
}
