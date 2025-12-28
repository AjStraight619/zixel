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
                    const entity = &world.slots.items[idx].entity;
                    const body = &entity.body;

                    // Show name if it has one
                    if (entity.name) |n| {
                        ig.igText("Name: %s", n.ptr);
                    } else {
                        ig.igText("Entity ID: %d", @as(c_int, @intCast(idx)));
                    }

                    switch (entity.owner) {
                        .none => ig.igTextDisabled("Owner: persistent"),
                        .scene => |s| ig.igText("Owner: %s", s.ptr),
                    }

                    ig.igSeparator();

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

                    if (entity.sprite) |*sprite| {
                        if (ig.igCollapsingHeader("Sprite", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                            var col: [4]f32 = .{ sprite.color.r, sprite.color.g, sprite.color.b, sprite.color.a };
                            if (ig.igColorEdit4("Color", &col, 0)) {
                                sprite.color.r = col[0];
                                sprite.color.g = col[1];
                                sprite.color.b = col[2];
                                sprite.color.a = col[3];
                            }
                        }
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
