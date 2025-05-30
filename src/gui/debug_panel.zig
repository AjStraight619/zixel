const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const Engine = @import("../engine/engine.zig").Engine;

pub const DebugPanel = struct {
    show_panel: bool = true,
    show_aabb: bool = false,
    show_contacts: bool = false,
    show_joints: bool = false,
    show_physics_info: bool = true,
    panel_rect: rl.Rectangle,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .panel_rect = rl.Rectangle{
                .x = 10,
                .y = 10,
                .width = 250,
                .height = 200,
            },
        };
    }

    pub fn update(self: *Self, engine: *Engine) void {
        if (!self.show_panel) return;

        // Begin GUI panel with close button
        const close_result = rlg.windowBox(self.panel_rect, "Debug Panel");

        if (close_result == 1) {
            self.show_panel = false;
            return;
        }

        var y_offset: f32 = 35;
        const item_height: f32 = 25;
        const margin: f32 = 10;
        const checkbox_width: f32 = 120; // Reduced width for checkboxes

        // AABB Debug Toggle
        const aabb_rect = rl.Rectangle{
            .x = self.panel_rect.x + margin,
            .y = self.panel_rect.y + y_offset,
            .width = checkbox_width,
            .height = item_height,
        };

        _ = rlg.checkBox(aabb_rect, "Show AABB", &self.show_aabb);
        y_offset += item_height + 5;

        // Contacts Debug Toggle
        const contacts_rect = rl.Rectangle{
            .x = self.panel_rect.x + margin,
            .y = self.panel_rect.y + y_offset,
            .width = checkbox_width,
            .height = item_height,
        };

        _ = rlg.checkBox(contacts_rect, "Show Contacts", &self.show_contacts);
        y_offset += item_height + 5;

        // Joints Debug Toggle
        const joints_rect = rl.Rectangle{
            .x = self.panel_rect.x + margin,
            .y = self.panel_rect.y + y_offset,
            .width = checkbox_width,
            .height = item_height,
        };

        _ = rlg.checkBox(joints_rect, "Show Joints", &self.show_joints);
        y_offset += item_height + 10;

        // Physics Info Toggle
        const info_rect = rl.Rectangle{
            .x = self.panel_rect.x + margin,
            .y = self.panel_rect.y + y_offset,
            .width = checkbox_width,
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
                .x = self.panel_rect.x + margin,
                .y = self.panel_rect.y + y_offset,
                .width = self.panel_rect.width - 2 * margin,
                .height = 40,
            };

            _ = rlg.label(text_rect, @ptrCast(info_text));
        }

        // Update engine debug settings when checkboxes change
        engine.enableDebugDrawing(self.show_aabb, self.show_contacts, self.show_joints);
    }

    pub fn toggleVisibility(self: *Self) void {
        self.show_panel = !self.show_panel;
    }

    pub fn isVisible(self: *const Self) bool {
        return self.show_panel;
    }
};
