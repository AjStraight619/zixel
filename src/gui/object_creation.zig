const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const Allocator = std.mem.Allocator;
const Engine = @import("../engine/engine.zig").Engine;

pub const ObjectType = enum {
    rectangle,
    circle,
    static_rect,
    static_circle,
};

pub const ObjectCreation = struct {
    alloc: Allocator,
    selected_object_type: ObjectType = .rectangle,
    // Parameters for object creation
    object_width: f32 = 50.0,
    object_height: f32 = 50.0,
    object_radius: f32 = 25.0,
    mass: f32 = 1.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,
    spawn_position: rl.Vector2 = .{ .x = 400, .y = 300 },

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn render(self: *Self, engine: *Engine, content_rect: rl.Rectangle) void {
        var y_offset: f32 = 5;
        const item_height: f32 = 25;
        const margin: f32 = 10;
        const label_width: f32 = 100;
        const control_width: f32 = content_rect.width - label_width - 3 * margin;

        // Object Type Selection
        const type_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = content_rect.width - 2 * margin,
            .height = item_height,
        };
        _ = rlg.label(type_label_rect, "Object Type:");
        y_offset += item_height + 2;

        const type_toggle_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = (content_rect.width - 3 * margin) / 4,
            .height = item_height,
        };

        var active_type: i32 = @intFromEnum(self.selected_object_type);
        const type_result = rlg.toggleGroup(type_toggle_rect, "Rect;Circle;Static Rect;Static Circle", &active_type);
        if (type_result >= 0) {
            self.selected_object_type = @enumFromInt(active_type);
        }
        y_offset += item_height + 8;

        // Shape Parameters
        _ = rlg.line(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = content_rect.width - 2 * margin,
            .height = 1,
        }, "Shape Parameters");
        y_offset += 15;

        switch (self.selected_object_type) {
            .rectangle, .static_rect => {
                // Width
                const width_label_rect = rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                };
                _ = rlg.label(width_label_rect, "Width:");

                const width_slider_rect = rl.Rectangle{
                    .x = content_rect.x + label_width + 2 * margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                };
                _ = rlg.slider(width_slider_rect, "10", "200", &self.object_width, 10.0, 200.0);
                y_offset += item_height + 5;

                // Height
                const height_label_rect = rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                };
                _ = rlg.label(height_label_rect, "Height:");

                const height_slider_rect = rl.Rectangle{
                    .x = content_rect.x + label_width + 2 * margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                };
                _ = rlg.slider(height_slider_rect, "10", "200", &self.object_height, 10.0, 200.0);
                y_offset += item_height + 5;
            },
            .circle, .static_circle => {
                // Radius
                const radius_label_rect = rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                };
                _ = rlg.label(radius_label_rect, "Radius:");

                const radius_slider_rect = rl.Rectangle{
                    .x = content_rect.x + label_width + 2 * margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                };
                _ = rlg.slider(radius_slider_rect, "5", "100", &self.object_radius, 5.0, 100.0);
                y_offset += item_height + 5;
            },
        }

        // Physics Parameters (only for dynamic objects)
        if (self.selected_object_type == .rectangle or self.selected_object_type == .circle) {
            _ = rlg.line(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = content_rect.width - 2 * margin,
                .height = 1,
            }, "Physics Parameters");
            y_offset += 15;

            // Mass
            const mass_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(mass_label_rect, "Mass:");

            const mass_slider_rect = rl.Rectangle{
                .x = content_rect.x + label_width + 2 * margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(mass_slider_rect, "0.1", "10", &self.mass, 0.1, 10.0);
            y_offset += item_height + 5;

            // Restitution (bounciness)
            const restitution_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(restitution_label_rect, "Bounciness:");

            const restitution_slider_rect = rl.Rectangle{
                .x = content_rect.x + label_width + 2 * margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(restitution_slider_rect, "0", "1", &self.restitution, 0.0, 1.0);
            y_offset += item_height + 5;

            // Friction
            const friction_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(friction_label_rect, "Friction:");

            const friction_slider_rect = rl.Rectangle{
                .x = content_rect.x + label_width + 2 * margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(friction_slider_rect, "0", "1", &self.friction, 0.0, 1.0);
            y_offset += item_height + 5;
        }

        // Spawn Position
        _ = rlg.line(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = content_rect.width - 2 * margin,
            .height = 1,
        }, "Spawn Position");
        y_offset += 15;

        // X Position
        const x_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        };
        _ = rlg.label(x_label_rect, "X Position:");

        const x_slider_rect = rl.Rectangle{
            .x = content_rect.x + label_width + 2 * margin,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        };
        _ = rlg.slider(x_slider_rect, "0", "800", &self.spawn_position.x, 0.0, 800.0);
        y_offset += item_height + 5;

        // Y Position
        const y_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        };
        _ = rlg.label(y_label_rect, "Y Position:");

        const y_slider_rect = rl.Rectangle{
            .x = content_rect.x + label_width + 2 * margin,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        };
        _ = rlg.slider(y_slider_rect, "0", "600", &self.spawn_position.y, 0.0, 600.0);
        y_offset += item_height + 10;

        // Create Object Button
        const create_button_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = content_rect.width - 2 * margin,
            .height = item_height + 5,
        };

        if (rlg.button(create_button_rect, "Create Object")) {
            self.createObject(engine);
        }
    }

    fn createObject(self: *Self, engine: *Engine) void {
        _ = engine; // TODO: Implement object creation

        // For now, just print what would be created
        switch (self.selected_object_type) {
            .rectangle => {
                std.log.info("Creating dynamic rectangle: {}x{} at ({d:.1}, {d:.1}), mass: {d:.2}, restitution: {d:.2}, friction: {d:.2}", .{ self.object_width, self.object_height, self.spawn_position.x, self.spawn_position.y, self.mass, self.restitution, self.friction });
            },
            .circle => {
                std.log.info("Creating dynamic circle: radius {d:.1} at ({d:.1}, {d:.1}), mass: {d:.2}, restitution: {d:.2}, friction: {d:.2}", .{ self.object_radius, self.spawn_position.x, self.spawn_position.y, self.mass, self.restitution, self.friction });
            },
            .static_rect => {
                std.log.info("Creating static rectangle: {}x{} at ({d:.1}, {d:.1})", .{ self.object_width, self.object_height, self.spawn_position.x, self.spawn_position.y });
            },
            .static_circle => {
                std.log.info("Creating static circle: radius {d:.1} at ({d:.1}, {d:.1})", .{ self.object_radius, self.spawn_position.x, self.spawn_position.y });
            },
        }
    }
};
