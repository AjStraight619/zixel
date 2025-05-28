const std = @import("std");
const rl = @import("raylib");
const zig2d = @import("zig2d");
const Engine = zig2d.Engine;
const PhysicsTestRunner = zig2d.PhysicsTestRunner;

var test_runner: ?PhysicsTestRunner = null;
var current_test: usize = 0;

fn handleInput(engine: *Engine, _: std.mem.Allocator) !void {
    if (test_runner == null) {
        test_runner = PhysicsTestRunner.init(engine);
    }

    // Number keys to run specific tests
    const keys = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven };
    for (keys, 0..) |key, i| {
        if (rl.isKeyPressed(key)) {
            try test_runner.?.runScenario(i);
            std.debug.print("🔢 Started test {} with key {}\n", .{ i + 1, i + 1 });
        }
    }

    // Space to run next test in sequence
    if (rl.isKeyPressed(.space)) {
        try test_runner.?.runScenario(current_test);
        current_test = (current_test + 1) % 7;
        std.debug.print("▶️ Started sequential test {}\n", .{current_test + 1});
    }

    // R to reset
    if (rl.isKeyPressed(.r)) {
        const world = engine.getPhysicsWorld();
        world.bodies.clearRetainingCapacity();
        if (test_runner) |*runner| {
            runner.current_scenario = null;
        }
        std.debug.print("🔄 Reset physics world\n", .{});
    }
}

fn updateGame(_: *Engine, _: std.mem.Allocator, _: f32) !void {
    if (test_runner) |*runner| {
        try runner.update();
    }
}

fn renderGame(engine: *Engine, allocator: std.mem.Allocator) !void {
    // Render physics bodies
    const world = engine.getPhysicsWorld();
    for (world.bodies.items) |*body| {
        const pos = body.getPosition();
        const shape = body.getShape();
        const color = if (body.isSleeping()) rl.Color.gray else rl.Color.blue;

        switch (shape) {
            .circle => |circle| {
                rl.drawCircleV(pos, circle.radius, color);
                rl.drawCircleLinesV(pos, circle.radius, rl.Color.black);
            },
            .rectangle => |rect| {
                const rotation = body.getRotation();
                if (@abs(rotation) < 0.01) {
                    // Axis-aligned optimization
                    rl.drawRectangle(@intFromFloat(pos.x - rect.width / 2), @intFromFloat(pos.y - rect.height / 2), @intFromFloat(rect.width), @intFromFloat(rect.height), color);
                    rl.drawRectangleLines(@intFromFloat(pos.x - rect.width / 2), @intFromFloat(pos.y - rect.height / 2), @intFromFloat(rect.width), @intFromFloat(rect.height), rl.Color.black);
                } else {
                    // Rotated rectangle - draw as lines
                    const hw = rect.width / 2;
                    const hh = rect.height / 2;
                    const cos_r = @cos(rotation);
                    const sin_r = @sin(rotation);

                    const corners = [4]rl.Vector2{
                        rl.Vector2{ .x = pos.x + (-hw * cos_r - -hh * sin_r), .y = pos.y + (-hw * sin_r + -hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (hw * cos_r - -hh * sin_r), .y = pos.y + (hw * sin_r + -hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (hw * cos_r - hh * sin_r), .y = pos.y + (hw * sin_r + hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (-hw * cos_r - hh * sin_r), .y = pos.y + (-hw * sin_r + hh * cos_r) },
                    };

                    for (0..4) |i| {
                        const next = (i + 1) % 4;
                        rl.drawLineV(corners[i], corners[next], rl.Color.black);
                    }
                }
            },
        }

        // Draw velocity vector for dynamic bodies
        if (body.*.kind == .Dynamic) {
            const vel = body.kind.Dynamic.velocity;
            const speed = @sqrt(vel.x * vel.x + vel.y * vel.y);
            if (speed > 10.0) {
                const end_pos = rl.Vector2{
                    .x = pos.x + vel.x * 0.1,
                    .y = pos.y + vel.y * 0.1,
                };
                rl.drawLineV(pos, end_pos, rl.Color.red);
            }
        }
    }

    // Render test runner UI
    if (test_runner) |*runner| {
        runner.renderUI();
    }

    // Render controls
    const controls = [_][]const u8{
        "PHYSICS VERIFICATION TESTS",
        "",
        "1-7: Run specific test",
        "SPACE: Run next test in sequence",
        "R: Reset world",
        "",
        "🧪 AVAILABLE TESTS:",
        "1. Momentum Conservation",
        "2. Energy Conservation",
        "3. SAT Accuracy (Rotation)",
        "4. Tunneling Prevention",
        "5. Mass Ratio Physics",
        "6. Sleep/Wake System",
        "7. Newton's Cradle",
    };

    var y: i32 = 450;
    for (controls) |line| {
        rl.drawText(@as([:0]const u8, @ptrCast(line)), 10, y, 14, rl.Color.dark_gray);
        y += 16;
    }

    // Physics stats
    const stats_text = std.fmt.allocPrint(allocator, "Bodies: {} | Steps: {}", .{ world.bodies.items.len, engine.getPhysicsStepCount() }) catch "Stats Error";
    defer allocator.free(stats_text);
    rl.drawText(@as([:0]const u8, @ptrCast(stats_text)), 10, 700, 16, rl.Color.black);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window = .{
            .title = "Physics Verification Tests",
            .width = 1000,
            .height = 750,
        },
        .physics = .{
            .gravity = .{ .x = 0, .y = 0 },
            .allow_sleeping = true,
            .debug_draw_aabb = false,
        },
        .target_fps = 60,
    });
    defer engine.deinit();

    engine.setHandleInputFn(handleInput);
    engine.setUpdateFn(updateGame);
    engine.setRenderFn(renderGame);

    std.debug.print("\n🎮 Physics Verification Test Suite\n", .{});
    std.debug.print("===================================\n", .{});
    std.debug.print("Use number keys 1-7 to run specific tests\n", .{});
    std.debug.print("Press SPACE to cycle through tests\n", .{});
    std.debug.print("Press R to reset the world\n\n", .{});

    try engine.run();
}
