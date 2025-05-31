const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const Engine = @import("../engine/engine.zig").Engine;

pub const DebugPanel = struct {
    show_aabb: bool = false,
    show_contacts: bool = false,
    show_joints: bool = false,
    show_physics_info: bool = true,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn render(self: *Self, engine: *Engine, content_rect: rl.Rectangle) void {
        var y_offset: f32 = 10;
        const item_height: f32 = 25;
        const margin: f32 = 10;

        // AABB Debug Toggle
        const aabb_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 120,
            .height = item_height,
        };
        _ = rlg.checkBox(aabb_rect, "Show AABB", &self.show_aabb);
        y_offset += item_height + 5;

        // Contacts Debug Toggle
        const contacts_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 120,
            .height = item_height,
        };
        _ = rlg.checkBox(contacts_rect, "Show Contacts", &self.show_contacts);
        y_offset += item_height + 5;

        // Joints Debug Toggle
        const joints_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 120,
            .height = item_height,
        };
        _ = rlg.checkBox(joints_rect, "Show Joints", &self.show_joints);
        y_offset += item_height + 10;

        // Physics Info Toggle
        const info_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 120,
            .height = item_height,
        };
        _ = rlg.checkBox(info_rect, "Show Physics Info", &self.show_physics_info);
        y_offset += item_height + 10;

        // Physics Info Display
        if (self.show_physics_info) {
            const gravity = engine.getGravity();
            const step_count = engine.getPhysicsStepCount();

            const info_text = std.fmt.allocPrintZ(std.heap.page_allocator, "Gravity: ({d:.1}, {d:.1})\nSteps: {d}", .{ gravity.x, gravity.y, step_count }) catch "Error displaying info";
            defer std.heap.page_allocator.free(info_text);

            const text_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = content_rect.width - 2 * margin,
                .height = 40,
            };
            _ = rlg.label(text_rect, @ptrCast(info_text));
        }

        // Update engine debug settings
        engine.enableDebugDrawing(self.show_aabb, self.show_contacts, self.show_joints);
    }
};
