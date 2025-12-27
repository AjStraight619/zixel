const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");

pub fn draw(editor: *Editor) void {
    if (!editor.show_hierarchy) return;

    ig.igSetNextWindowPos(.{ .x = 10, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 230, .y = 300 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Hierarchy", &editor.show_hierarchy, 0)) {
        if (editor.world) |world| {
            var count: usize = 0;

            for (world.slots.items, 0..) |slot, i| {
                if (!slot.alive) continue;

                var buf: [64]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "Entity {d}\x00", .{i}) catch "Entity\x00";

                if (ig.igSelectable(label.ptr)) {
                    editor.selected_entity = i;
                }
                count += 1;
            }

            if (count == 0) ig.igTextDisabled("World is empty.");
        } else {
            ig.igTextDisabled("No World Context");
        }
    }
    ig.igEnd();
}
