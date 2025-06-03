const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const Allocator = std.mem.Allocator;
const Engine = @import("../ecs/engine.zig").Engine;
const components = @import("../ecs/components.zig");
const LayoutInfo = @import("gui_manager.zig").LayoutInfo;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;

pub const BodyType = enum {
    static,
    dynamic,
};

pub const ShapeType = enum {
    rectangle,
    circle,
};

pub const ObjectCreation = struct {
    alloc: Allocator,
    selected_body_type: BodyType = .dynamic,
    selected_shape_type: ShapeType = .rectangle,
    // Parameters for object creation
    object_width: f32 = 50.0,
    object_height: f32 = 50.0,
    object_radius: f32 = 25.0,
    mass: f32 = 1.0,
    restitution: f32 = 0.3,
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
        // For now, create a mock layout info - in a real implementation you'd pass this from GUI manager
        const layout_info = LayoutInfo{
            .is_compact = content_rect.width < 350 or content_rect.height < 500,
            .is_narrow = content_rect.width < 350,
            .is_short = content_rect.height < 500,
            .available_width = content_rect.width,
            .available_height = content_rect.height,
        };

        if (layout_info.is_compact) {
            self.renderCompactLayout(engine, content_rect, layout_info);
        } else {
            self.renderNormalLayout(engine, content_rect, layout_info);
        }
    }

    fn renderNormalLayout(self: *Self, engine: *Engine, content_rect: rl.Rectangle, layout_info: LayoutInfo) void {
        var y_offset: f32 = 5;
        const item_height: f32 = 25;
        const margin: f32 = 10;
        const label_width: f32 = 100;
        const control_width: f32 = layout_info.available_width - label_width - 3 * margin;

        // Body Type Selection (Static vs Dynamic)
        const body_type_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = item_height,
        };
        _ = rlg.label(body_type_label_rect, "Body Type:");
        y_offset += item_height + 2;

        // Calculate appropriate width for toggle buttons (fit text + padding)
        const toggle_width = @min(120.0, (layout_info.available_width - 4 * margin) / 2);

        const body_type_toggle_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = toggle_width,
            .height = item_height,
        };

        var active_body_type: i32 = @intFromEnum(self.selected_body_type);
        const body_type_result = rlg.toggleGroup(body_type_toggle_rect, "Static;Dynamic", &active_body_type);
        if (body_type_result >= 0) {
            self.selected_body_type = @enumFromInt(active_body_type);
        }
        y_offset += item_height + 8;

        // Shape Type Selection (Circle vs Rectangle)
        const shape_type_label_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = item_height,
        };
        _ = rlg.label(shape_type_label_rect, "Shape Type:");
        y_offset += item_height + 2;

        const shape_type_toggle_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = toggle_width,
            .height = item_height,
        };

        var active_shape_type: i32 = @intFromEnum(self.selected_shape_type);
        const shape_type_result = rlg.toggleGroup(shape_type_toggle_rect, "Rectangle;Circle", &active_shape_type);
        if (shape_type_result >= 0) {
            self.selected_shape_type = @enumFromInt(active_shape_type);
        }
        y_offset += item_height + 8;

        y_offset = self.renderShapeParameters(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width);
        y_offset = self.renderPhysicsParameters(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width);
        y_offset = self.renderSpawnPosition(content_rect, y_offset, layout_info, item_height, margin, label_width, control_width);
        self.renderCreateButton(engine, content_rect, y_offset, layout_info, item_height, margin);
    }

    fn renderCompactLayout(self: *Self, engine: *Engine, content_rect: rl.Rectangle, layout_info: LayoutInfo) void {
        // For compact layout, use smaller spacing and potentially two columns
        var y_offset: f32 = 3;
        const item_height: f32 = 22;
        const margin: f32 = 6;
        const small_spacing: f32 = 3;

        // Body Type and Shape Type in one row if wide enough
        if (!layout_info.is_narrow) {
            // Two column layout for selections
            const col_width = (layout_info.available_width - 3 * margin) / 2;
            const toggle_width = @min(col_width - 5, 80.0); // Ensure buttons fit in columns

            // Body Type (left column)
            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = col_width,
                .height = item_height,
            }, "Body:");

            var active_body_type: i32 = @intFromEnum(self.selected_body_type);
            const body_toggle_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset + item_height + 1,
                .width = toggle_width,
                .height = item_height,
            };
            _ = rlg.toggleGroup(body_toggle_rect, "Static;Dynamic", &active_body_type);
            self.selected_body_type = @enumFromInt(active_body_type);

            // Shape Type (right column)
            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin + col_width + margin,
                .y = content_rect.y + y_offset,
                .width = col_width,
                .height = item_height,
            }, "Shape:");

            var active_shape_type: i32 = @intFromEnum(self.selected_shape_type);
            const shape_toggle_rect = rl.Rectangle{
                .x = content_rect.x + margin + col_width + margin,
                .y = content_rect.y + y_offset + item_height + 1,
                .width = toggle_width,
                .height = item_height,
            };
            _ = rlg.toggleGroup(shape_toggle_rect, "Rect;Circle", &active_shape_type);
            self.selected_shape_type = @enumFromInt(active_shape_type);

            y_offset += 2 * item_height + 6;
        } else {
            // Narrow layout - stack vertically but compact
            const toggle_width = @min(layout_info.available_width - 2 * margin - 10, 100.0);

            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = layout_info.available_width - 2 * margin,
                .height = item_height,
            }, "Body Type:");
            y_offset += item_height + 1;

            var active_body_type: i32 = @intFromEnum(self.selected_body_type);
            const body_toggle_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = toggle_width,
                .height = item_height,
            };
            _ = rlg.toggleGroup(body_toggle_rect, "Static;Dynamic", &active_body_type);
            self.selected_body_type = @enumFromInt(active_body_type);
            y_offset += item_height + small_spacing;

            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = layout_info.available_width - 2 * margin,
                .height = item_height,
            }, "Shape:");
            y_offset += item_height + 1;

            var active_shape_type: i32 = @intFromEnum(self.selected_shape_type);
            const shape_toggle_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = toggle_width,
                .height = item_height,
            };
            _ = rlg.toggleGroup(shape_toggle_rect, "Rect;Circle", &active_shape_type);
            self.selected_shape_type = @enumFromInt(active_shape_type);
            y_offset += item_height + small_spacing;
        }

        y_offset = self.renderShapeParametersCompact(content_rect, y_offset, layout_info, item_height, margin);
        y_offset = self.renderPhysicsParametersCompact(content_rect, y_offset, layout_info, item_height, margin);
        y_offset = self.renderSpawnPositionCompact(content_rect, y_offset, layout_info, item_height, margin);
        self.renderCreateButtonCompact(engine, content_rect, y_offset, layout_info, item_height, margin);
    }

    fn renderShapeParameters(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32) f32 {
        var y_offset = y_start;
        const spacing: f32 = if (layout_info.is_compact) 2.0 else 5.0;

        _ = rlg.line(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = layout_info.available_width - 2 * margin,
            .height = 1,
        }, "Shape Parameters");
        y_offset += if (layout_info.is_compact) 12.0 else 15.0;

        switch (self.selected_shape_type) {
            .rectangle => {
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
                    .x = content_rect.x + label_width + 2 * margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                };
                _ = rlg.slider(height_slider_rect, "10", "200", &self.object_height, 10.0, 200.0);
                y_offset += item_height + spacing;
            },
            .circle => {
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
                y_offset += item_height + spacing;
            },
        }

        return y_offset;
    }

    fn renderPhysicsParameters(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32) f32 {
        var y_offset = y_start;
        const spacing: f32 = if (layout_info.is_compact) 2.0 else 5.0;

        // Physics Parameters (only for dynamic objects)
        if (self.selected_body_type == .dynamic) {
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
                .x = content_rect.x + label_width + 2 * margin,
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
                .x = content_rect.x + label_width + 2 * margin,
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
                .x = content_rect.x + label_width + 2 * margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            };
            _ = rlg.slider(friction_slider_rect, "0", "1", &self.friction, 0.0, 1.0);
            y_offset += item_height + spacing;
        }

        return y_offset;
    }

    fn renderSpawnPosition(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32, label_width: f32, control_width: f32) f32 {
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
            .x = content_rect.x + label_width + 2 * margin,
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
            .x = content_rect.x + label_width + 2 * margin,
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
        // Create transform
        const transform = components.Transform{
            .position = self.spawn_position,
        };

        // Create physics shape based on selection
        const physics_shape = switch (self.selected_shape_type) {
            .rectangle => PhysicsShape{ .rectangle = rl.Rectangle{ .x = 0, .y = 0, .width = self.object_width, .height = self.object_height } },
            .circle => PhysicsShape{ .circle = .{ .radius = self.object_radius } },
        };

        // Create physics entity using new API
        const entity = if (self.selected_body_type == .static)
            engine.createStaticBody(transform, physics_shape, if (self.selected_shape_type == .rectangle) rl.Color.brown else rl.Color.maroon) catch return
        else
            engine.createDynamicBody(transform, physics_shape, if (self.selected_shape_type == .rectangle) rl.Color.green else rl.Color.lime) catch return;

        // Apply custom physics parameters for dynamic bodies
        if (self.selected_body_type == .dynamic) {
            if (engine.getComponent(components.PhysicsBodyRef, entity)) |physics_ref| {
                const physics_world = engine.getPhysicsWorld();
                if (physics_world.getBody(physics_ref.body_id)) |body| {
                    body.kind.Dynamic.mass = self.mass;
                    body.kind.Dynamic.restitution = self.restitution;
                    body.kind.Dynamic.friction = self.friction;
                    body.kind.Dynamic.gravity_scale = 1.0; // Ensure gravity is applied
                    std.log.info("Applied custom physics: mass={d:.2}, restitution={d:.2}, friction={d:.2}", .{ self.mass, self.restitution, self.friction });
                }
            }
        }

        // Add a tag for identification
        var tag = components.Tag{};
        tag.add(.Obstacle);
        engine.addComponent(entity, tag) catch return;

        const body_type_str = if (self.selected_body_type == .static) "static" else "dynamic";
        const shape_type_str = if (self.selected_shape_type == .rectangle) "rectangle" else "circle";

        std.log.info("Created {s} {s} at ({d:.1}, {d:.1})", .{ body_type_str, shape_type_str, self.spawn_position.x, self.spawn_position.y });
    }

    // Compact layout versions
    fn renderShapeParametersCompact(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32) f32 {
        var y_offset = y_start;
        const label_width: f32 = 50;
        const control_width: f32 = layout_info.available_width - label_width - 3 * margin;

        switch (self.selected_shape_type) {
            .rectangle => {
                // Width & Height in compact layout
                _ = rlg.label(rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                }, "W:");
                _ = rlg.slider(rl.Rectangle{
                    .x = content_rect.x + label_width + margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                }, "10", "200", &self.object_width, 10.0, 200.0);
                y_offset += item_height + 2;

                _ = rlg.label(rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                }, "H:");
                _ = rlg.slider(rl.Rectangle{
                    .x = content_rect.x + label_width + margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                }, "10", "200", &self.object_height, 10.0, 200.0);
                y_offset += item_height + 2;
            },
            .circle => {
                _ = rlg.label(rl.Rectangle{
                    .x = content_rect.x + margin,
                    .y = content_rect.y + y_offset,
                    .width = label_width,
                    .height = item_height,
                }, "R:");
                _ = rlg.slider(rl.Rectangle{
                    .x = content_rect.x + label_width + margin,
                    .y = content_rect.y + y_offset,
                    .width = control_width,
                    .height = item_height,
                }, "5", "100", &self.object_radius, 5.0, 100.0);
                y_offset += item_height + 2;
            },
        }

        return y_offset;
    }

    fn renderPhysicsParametersCompact(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32) f32 {
        var y_offset = y_start;
        const label_width: f32 = 50;
        const control_width: f32 = layout_info.available_width - label_width - 3 * margin;

        if (self.selected_body_type == .dynamic) {
            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            }, "M:");
            _ = rlg.slider(rl.Rectangle{
                .x = content_rect.x + label_width + margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            }, "0.1", "10", &self.mass, 0.1, 10.0);
            y_offset += item_height + 2;

            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            }, "B:");
            _ = rlg.slider(rl.Rectangle{
                .x = content_rect.x + label_width + margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            }, "0", "1", &self.restitution, 0.0, 1.0);
            y_offset += item_height + 2;

            _ = rlg.label(rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = label_width,
                .height = item_height,
            }, "F:");
            _ = rlg.slider(rl.Rectangle{
                .x = content_rect.x + label_width + margin,
                .y = content_rect.y + y_offset,
                .width = control_width,
                .height = item_height,
            }, "0", "1", &self.friction, 0.0, 1.0);
            y_offset += item_height + 2;
        }

        return y_offset;
    }

    fn renderSpawnPositionCompact(self: *Self, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32) f32 {
        var y_offset = y_start;
        const label_width: f32 = 50;
        const control_width: f32 = layout_info.available_width - label_width - 3 * margin;

        _ = rlg.label(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        }, "X:");
        _ = rlg.slider(rl.Rectangle{
            .x = content_rect.x + label_width + margin,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        }, "0", "800", &self.spawn_position.x, 0.0, 800.0);
        y_offset += item_height + 2;

        _ = rlg.label(rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = label_width,
            .height = item_height,
        }, "Y:");
        _ = rlg.slider(rl.Rectangle{
            .x = content_rect.x + label_width + margin,
            .y = content_rect.y + y_offset,
            .width = control_width,
            .height = item_height,
        }, "0", "600", &self.spawn_position.y, 0.0, 600.0);
        y_offset += item_height + 3;

        return y_offset;
    }

    fn renderCreateButtonCompact(self: *Self, engine: *Engine, content_rect: rl.Rectangle, y_start: f32, layout_info: LayoutInfo, item_height: f32, margin: f32) void {
        const button_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_start,
            .width = layout_info.available_width - 2 * margin,
            .height = item_height,
        };

        if (rlg.button(button_rect, "Create")) {
            self.createObject(engine);
        }
    }
};
