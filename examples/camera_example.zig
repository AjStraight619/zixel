const std = @import("std");
const zixel = @import("zixel");

// User-defined action enum
const GameAction = enum {
    move_left,
    move_right,
    move_up,
    move_down,
    jump,
    switch_to_menu,
    zoom_in,
    zoom_out,
};

const MenuAction = enum {
    select,
    back,
};

// Input Managers
const GameInputManager = zixel.input.KeybindManager(GameAction);
const MenuInputManager = zixel.input.KeybindManager(MenuAction);

const GameScene = struct {
    // Scene data is part of the scene itself
    player_body_id: ?usize = null,

    // Scene configuration - LSP will hint these fields!
    const config = .{
        .needs_physics = true,
        .physics_config = .{
            .gravity = .{ .x = 0, .y = 800 }, // Custom gravity stronger than default
            .allow_sleeping = false, // Disable sleeping in game scene
            .debug_draw_aabb = true, // Show collision boxes in game
        },
        .auto_update_physics = true,
        .camera_config = zixel.CameraConfig{
            .camera_type = .follow_player,
            .follow_speed = 3.0,
            .bounds = .{
                .min_x = -500,
                .max_x = 1500,
                .min_y = -300,
                .max_y = 800,
            },
            .min_zoom = 0.5,
            .max_zoom = 3.0,
        },
        .auto_update_camera = true,
        .input_manager_name = "game",
    };

    pub fn init(self: *GameScene, ctx: *zixel.SceneContext) !void {
        // Create player body using the actual API
        if (ctx.physics()) |physics| {
            self.player_body_id = try physics.addBody(zixel.Body.initDynamic(
                .{ .circle = .{ .radius = 20 } },
                .{ .x = 400, .y = 300 },
                .{
                    .mass = 1.0,
                    .restitution = 0.3,
                    .friction = 0.8,
                },
            ));

            // Create some platforms for the player to jump on
            _ = try physics.addBody(zixel.Body.initStatic(
                .{ .rectangle = .{ .x = 0, .y = 0, .width = 200, .height = 20 } },
                .{ .x = 300, .y = 450 },
                .{},
            ));

            _ = try physics.addBody(zixel.Body.initStatic(
                .{ .rectangle = .{ .x = 0, .y = 0, .width = 200, .height = 20 } },
                .{ .x = 600, .y = 350 },
                .{},
            ));

            _ = try physics.addBody(zixel.Body.initStatic(
                .{ .rectangle = .{ .x = 0, .y = 0, .width = 800, .height = 40 } },
                .{ .x = 400, .y = 580 },
                .{},
            ));
        }

        // Set camera to follow player
        if (ctx.camera()) |camera| {
            if (self.player_body_id) |body_id| {
                if (ctx.physics().?.getBodyById(body_id)) |player| {
                    camera.setTarget(player.getPosition());
                }
            }
        }
    }

    pub fn deinit(self: *GameScene, ctx: *zixel.SceneContext) void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *GameScene, ctx: *zixel.SceneContext, dt: f32) !void {
        _ = dt;

        // Use the input manager instead of direct raylib calls
        if (ctx.input(GameInputManager)) |input| {
            if (input.isActionTapped(.switch_to_menu)) {
                try ctx.switchScene("menu");
                return;
            }

            // Player movement
            if (self.player_body_id) |body_id| {
                if (ctx.physics().?.getBodyById(body_id)) |player| {
                    const move_force = 500.0;

                    if (input.isActionHeld(.move_left)) {
                        player.applyForce(.{ .x = -move_force, .y = 0 });
                    }
                    if (input.isActionHeld(.move_right)) {
                        player.applyForce(.{ .x = move_force, .y = 0 });
                    }
                    if (input.isActionHeld(.move_up)) {
                        player.applyForce(.{ .x = 0, .y = -move_force });
                    }
                    if (input.isActionHeld(.move_down)) {
                        player.applyForce(.{ .x = 0, .y = move_force });
                    }

                    if (input.isActionTapped(.jump)) {
                        player.applyForce(.{ .x = 0, .y = -1000 });
                    }

                    // Update camera target
                    if (ctx.camera()) |camera| {
                        camera.setTarget(player.getPosition());
                    }

                    // Camera zoom controls
                    if (input.isActionTapped(.zoom_in)) {
                        if (ctx.camera()) |camera| {
                            camera.setZoom(camera.camera2d.zoom + 0.2);
                        }
                    }
                    if (input.isActionTapped(.zoom_out)) {
                        if (ctx.camera()) |camera| {
                            camera.setZoom(camera.camera2d.zoom - 0.2);
                        }
                    }
                }
            }
        }
    }

    pub fn render(self: *GameScene, ctx: *zixel.SceneContext) !void {
        // Begin camera mode
        if (ctx.camera()) |camera| {
            camera.beginMode();

            // Draw all physics bodies
            const physics = ctx.physics().?;
            for (physics.bodies.items) |*body| {
                const color = if (body.id == self.player_body_id)
                    zixel.Color.blue
                else if (body.kind == .dynamic)
                    zixel.Color.red
                else
                    zixel.Color.green;

                body.draw(color);
            }

            // Draw some world objects for reference
            zixel.rl.drawRectangle(100, 100, 50, 50, zixel.Color.yellow);
            zixel.rl.drawRectangle(900, 200, 50, 50, zixel.Color.purple);

            camera.endMode();
        }

        // Draw UI (not affected by camera)
        zixel.rl.drawText("Perfect Clean Scene API!", 10, 10, 20, zixel.Color.black);
        zixel.rl.drawText("WASD: Move, Space: Jump, -/+: Zoom, Esc: Menu", 10, 35, 16, zixel.Color.dark_gray);

        // Show camera info
        if (ctx.camera()) |camera| {
            const target = camera.camera2d.target;
            const zoom = camera.camera2d.zoom;
            const info_text = std.fmt.allocPrintZ(ctx.alloc(), "Camera: ({d:.1}, {d:.1}) Zoom: {d:.2}", .{ target.x, target.y, zoom }) catch "Camera: ?";
            defer ctx.alloc().free(info_text);
            zixel.rl.drawText(info_text, 10, 60, 14, zixel.Color.dark_gray);
        }
    }
};

const MenuScene = struct {
    // Scene data
    selected_item: u32 = 0,
    menu_items: []const []const u8 = &[_][]const u8{ "Resume Game", "New Game", "Exit" },

    const config = .{
        .needs_physics = true, // Changed from false to demonstrate different physics
        .physics_config = .{
            .gravity = .{ .x = 0, .y = 0 }, // Zero gravity in menu (space-like)
            .allow_sleeping = true, // Allow sleeping in menu
            .debug_draw_aabb = false, // No debug drawing in menu
        },
        .auto_update_physics = false,
        .camera_config = zixel.CameraConfig{
            .camera_type = .fixed,
        },
        .auto_update_camera = true,
        .input_manager_name = "menu",
    };

    pub fn init(self: *MenuScene, ctx: *zixel.SceneContext) !void {
        _ = self;

        // Add some floating objects to demonstrate zero gravity
        if (ctx.physics()) |physics| {
            // Create some floating dynamic bodies using the proper init functions
            _ = try physics.addBody(zixel.Body.initDynamic(.{ .circle = .{ .radius = 20 } }, .{ .x = 100, .y = 100 }, .{ .mass = 1.0 }));

            _ = try physics.addBody(zixel.Body.initDynamic(.{ .rectangle = .{ .x = 0, .y = 0, .width = 40, .height = 30 } }, .{ .x = 200, .y = 150 }, .{ .mass = 1.5 }));

            _ = try physics.addBody(zixel.Body.initDynamic(.{ .circle = .{ .radius = 15 } }, .{ .x = 300, .y = 200 }, .{ .mass = 0.8 }));
        }
    }

    pub fn deinit(self: *MenuScene, ctx: *zixel.SceneContext) void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *MenuScene, ctx: *zixel.SceneContext, dt: f32) !void {
        _ = dt;
        _ = self;

        if (ctx.input(MenuInputManager)) |input| {
            if (input.isActionTapped(.select)) {
                try ctx.switchScene("game");
            }

            if (input.isActionTapped(.back)) {
                try ctx.switchScene("game");
            }
        }
    }

    pub fn render(self: *MenuScene, ctx: *zixel.SceneContext) !void {
        // Draw floating physics objects (demonstrating zero gravity)
        if (ctx.physics()) |physics| {
            for (physics.bodies.items) |*body| {
                body.draw(zixel.Color.blue); // Draw floating objects in blue
            }
        }

        zixel.rl.drawText("MENU (Zero Gravity!)", 300, 200, 30, zixel.Color.black);

        for (self.menu_items, 0..) |item, i| {
            const y: i32 = @intCast(300 + i * 40);
            const color = if (i == self.selected_item) zixel.Color.red else zixel.Color.black;
            const item_cstr = std.fmt.allocPrintZ(ctx.alloc(), "{s}", .{item}) catch continue;
            defer ctx.alloc().free(item_cstr);
            zixel.rl.drawText(item_cstr, 300, y, 20, color);
        }

        zixel.rl.drawText("Enter: Select, Esc: Back", 300, 450, 16, zixel.Color.dark_gray);
        zixel.rl.drawText("Notice: Objects float in zero gravity!", 300, 480, 14, zixel.Color.gray);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = zixel.Engine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Perfect Clean Scene API Demo",
        },
        .physics = .{
            .gravity = .{ .x = 0, .y = 500 },
        },
    });
    defer engine.deinit();

    // User creates and owns input managers
    var game_input = GameInputManager.init(allocator);
    defer game_input.deinit();

    var menu_input = MenuInputManager.init(allocator);
    defer menu_input.deinit();

    // Configure bindings using the new bindMany syntax
    try game_input.bindMany(.{
        .move_left = .a,
        .move_right = .d,
        .move_up = .w,
        .move_down = .s,
        .jump = .space,
        .switch_to_menu = .escape,
        .zoom_in = .equal,
        .zoom_out = .minus,
    });

    try menu_input.bindMany(.{
        .select = .enter,
        .back = .escape,
    });

    // Register input managers
    try engine.registerInputManager("game", &game_input);
    try engine.registerInputManager("menu", &menu_input);

    try engine.registerScene("game", GameScene);
    try engine.registerScene("menu", MenuScene);

    try engine.switchToScene("game");
    try engine.run();
}
