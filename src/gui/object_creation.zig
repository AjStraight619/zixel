const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const Allocator = std.mem.Allocator;
const Engine = @import("../engine/engine.zig").Engine;
const LayoutInfo = @import("gui_manager.zig").LayoutInfo;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Body = @import("../physics/body.zig").Body;

pub const ObjectCreation = struct {
    alloc: Allocator,
    selected_body_is_dynamic: bool = true,
    selected_shape_is_rectangle: bool = true,
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
        // Create layout info
        const layout_info = LayoutInfo{
            .is_compact = content_rect.width < 350 or content_rect.height < 500,
            .is_narrow = content_rect.width < 350,
            .is_short = content_rect.height < 500,
            .available_width = content_rect.width,
            .available_height = content_rect.height,
        };

        var y_offset: f32 = 5;
        const item_height: f32 = 25;
        const margin: f32 = 10;
        const label_width: f32 = 80; // Reduced from 100
        const gap: f32 = 5; // Smaller gap between label and slider
        const value_text_space: f32 = 40; // Space for value text on right
        const control_width: f32 = layout_info.available_width - label_width - gap - margin - value_text_space;

        // Body Type in first row
        _ = rlg.label(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = item_height,
        }, "Body Type:");
        y_offset += item_height + 2;

        // Body Type toggles - constrain width properly
        const toggle_width = layout_info.available_width - 2 * margin;
        const body_type_toggle_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = toggle_width / 2,
            .height = item_height,
        };

        var active_body_type: i32 = if (self.selected_body_is_dynamic) 1 else 0;
        const body_type_result = rlg.toggleGroup(body_type_toggle_rect, "Static;Dynamic", &active_body_type);
        if (body_type_result >= 0) {
            self.selected_body_is_dynamic = (active_body_type == 1);
        }
        y_offset += item_height + 8;

        // Shape Type in second row
        _ = rlg.label(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = toggle_width,
            .height = item_height,
        }, "Shape Type:");
        y_offset += item_height + 2;

        // Shape Type toggles - constrain width properly
        const shape_type_toggle_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = toggle_width / 2,
            .height = item_height,
        };

        var active_shape_type: i32 = if (self.selected_shape_is_rectangle) 0 else 1;
        const shape_type_result = rlg.toggleGroup(shape_type_toggle_rect, "Rectangle;Circle", &active_shape_type);
        if (shape_type_result >= 0) {
            self.selected_shape_is_rectangle = (active_shape_type == 0);
        }
        y_offset += item_height + 8;

        y_offset = self.renderShapeParameters(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width, gap);
        y_offset = self.renderPhysicsParameters(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width, gap);
        y_offset = self.renderSpawnPosition(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width, gap);
        self.renderCreateButton(engine, content_rect, y_offset, layout_info, item_height, margin);
    }

    fn renderShapeParameters(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32, gap: f32) f32 {
        var y_offset = y_start;
        const spacing: f32 = if (layout_info.is_compact) 2.0 else 5.0;

        _ = rlg.line(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = 1,
        }, "Shape Parameters");
        y_offset += if (layout_info.is_compact) 12.0 else 15.0;

        if (self.selected_shape_is_rectangle) {
            // Width
            const width_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(width_label_rect, "Width:");

            const width_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(width_slider_rect, "10", "200", &self.object_width, 10.0, 200.0);
            y_offset += item_height + spacing;

            // Height
            const height_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(height_label_rect, "Height:");

            const height_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(height_slider_rect, "10", "200", &self.object_height, 10.0, 200.0);
            y_offset += item_height + spacing;
        } else {
            // Radius
            const radius_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(radius_label_rect, "Radius:");

            const radius_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(radius_slider_rect, "5", "100", &self.object_radius, 5.0, 100.0);
            y_offset += item_height + spacing;
        }

        return y_offset;
    }

    fn renderPhysicsParameters(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32, gap: f32) f32 {
        var y_offset = y_start;
        const spacing: f32 = if (layout_info.is_compact) 2.0 else 5.0;

        // Physics Parameters (only for dynamic objects)
        if (self.selected_body_is_dynamic) {
            _ = rlg.line(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = layout_info.available_width - 2 * margin,
                .height = 1,
            }, "Physics Parameters");
            y_offset += if (layout_info.is_compact) 12.0 else 15.0;

            // Mass
            const mass_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(mass_label_rect, "Mass:");

            const mass_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(mass_slider_rect, "0.1", "10", &self.mass, 0.1, 10.0);
            y_offset += item_height + spacing;

            // Restitution (bounciness)
            const restitution_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(restitution_label_rect, if (layout_info.is_compact) "Bounce:" else "Bounciness:");

            const restitution_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(restitution_slider_rect, "0", "1", &self.restitution, 0.0, 1.0);
            y_offset += item_height + spacing;

            // Friction
            const friction_label_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            };
            _ = rlg.label(friction_label_rect, "Friction:");

            const friction_slider_rect = rl.Rectangle{
                .x = content_rect.x + margin + label_width + gap,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(friction_slider_rect, "0", "1", &self.friction, 0.0, 1.0);
            y_offset += item_height + spacing;
        }

        return y_offset;
    }

    fn renderSpawnPosition(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32, gap: f32) f32 {
        var y_offset = y_start;
        const spacing: f32 = if (layout_info.is_compact) 2.0 else 5.0;

        // Spawn Position
        _ = rlg.line(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = 1,
        }, "Spawn Position");
        y_offset += if (layout_info.is_compact) 12.0 else 15.0;

        // X Position
        const x_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        };
        _ = rlg.label(x_label_rect, "X Position:");

        const x_slider_rect = rl.Rectangle{
            .x = content_rect.x + margin + label_width + gap,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        };
        _ = rlg.slider(x_slider_rect, "0", "800", &self.spawn_position.x, 0.0, 800.0);
        y_offset += item_height + spacing;

        // Y Position
        const y_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        };
        _ = rlg.label(y_label_rect, "Y Position:");

        const y_slider_rect = rl.Rectangle{
            .x = content_rect.x + margin + label_width + gap,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        };
        _ = rlg.slider(y_slider_rect, "0", "600", &self.spawn_position.y, 0.0, 600.0);

        const final_spacing: f32 = if (layout_info.is_compact) 5.0 else 10.0;
        y_offset += item_height + final_spacing;

        return y_offset;
    }

    fn renderCreateButton(self: *Self, engine: *Engine, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32) void {
        // Create Object Button
        const extra_height: f32 = if (layout_info.is_compact) 3.0 else 5.0;
        const button_height: f32 = item_height + extra_height;
        const create_button_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_start,
            .width = layout_info.available_width - 2 * margin,
            .height = button_height,
        };

        if (rlg.button(create_button_rect, "Create Object")) {
            self.createObject(engine);
        }
    }

    fn createObject(self: *Self, engine: *Engine) void {
        // Create the physics shape
        const shape = if (self.selected_shape_is_rectangle)
            PhysicsShape{
                .rectangle = rl.Rectangle{
                    .x = 0, // Position is handled separately
                    .y = 0,
                    .width = self.object_width,
                    .height = self.object_height,
                },
            }
        else
            PhysicsShape{ .circle = .{ .radius = self.object_radius } };

        // Create the body
        const body = if (self.selected_body_is_dynamic)
            Body.initDynamic(shape, self.spawn_position, .{
                .mass = self.mass,
                .restitution = self.restitution,
                .friction = self.friction,
            })
        else
            Body.initStatic(shape, self.spawn_position, .{
                .restitution = self.restitution,
                .friction = self.friction,
            });

        // Add to physics world
        if (engine.getCurrentPhysics()) |physics| {
            _ = physics.addBody(body) catch |err| {
                std.log.err("Failed to create object: {}", .{err});
                return;
            };
        } else {
            std.log.err("No physics world available to create object in", .{});
            return;
        }

        // Log the creation
        const body_type_str = if (self.selected_body_is_dynamic) "dynamic" else "static";
        const shape_type_str = if (self.selected_shape_is_rectangle) "rectangle" else "circle";

        if (self.selected_shape_is_rectangle) {
            if (self.selected_body_is_dynamic) {
                std.log.info("Created {s} {s}: {}x{} at ({d:.1}, {d:.1}), mass: {d:.2}, restitution: {d:.2}, friction: {d:.2}", .{ body_type_str, shape_type_str, self.object_width, self.object_height, self.spawn_position.x, self.spawn_position.y, self.mass, self.restitution, self.friction });
            } else {
                std.log.info("Created {s} {s}: {}x{} at ({d:.1}, {d:.1})", .{ body_type_str, shape_type_str, self.object_width, self.object_height, self.spawn_position.x, self.spawn_position.y });
            }
        } else {
            if (self.selected_body_is_dynamic) {
                std.log.info("Created {s} {s}: radius {d:.1} at ({d:.1}, {d:.1}), mass: {d:.2}, restitution: {d:.2}, friction: {d:.2}", .{ body_type_str, shape_type_str, self.object_radius, self.spawn_position.x, self.spawn_position.y, self.mass, self.restitution, self.friction });
            } else {
                std.log.info("Created {s} {s}: radius {d:.1} at ({d:.1}, {d:.1})", .{ body_type_str, shape_type_str, self.object_radius, self.spawn_position.x, self.spawn_position.y });
            }
        }
    }
};
