const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");

pub fn draw(editor: *Editor) void {
    if (!editor.show_inspector) return;

    ig.igSetNextWindowPos(.{ .x = 1060, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 400 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Inspector", &editor.show_inspector, 0)) {
        if (editor.selected_entity) |idx| {
            if (editor.world) |world| {
                if (idx < world.slots.items.len and world.slots.items[idx].alive) {
                    const body = &world.slots.items[idx].body;

                    ig.igText("Entity ID: %d", @as(c_int, @intCast(idx)));
                    ig.igSeparator();

                    // FIXED: Changed function name to igCollapsingHeader
                    if (ig.igCollapsingHeader("Transform", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                        _ = ig.igDragFloat("X", &body.position.x);
                        _ = ig.igDragFloat("Y", &body.position.y);
                        _ = ig.igDragFloat("Rotation", &body.rotation);
                    }

                    if (ig.igCollapsingHeader("Physics", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                        ig.igText("Mass: %.2f", body.mass);
                        _ = ig.igDragFloat("Friction", &body.friction);
                        _ = ig.igDragFloat("Restitution", &body.restitution);
                    }
                } else {
                    editor.selected_entity = null;
                }
            }
        } else {
            ig.igTextDisabled("Select an entity to inspect.");
        }
    }
    ig.igEnd();
}
