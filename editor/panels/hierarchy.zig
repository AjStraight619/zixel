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

                // "##<slot>" keeps ImGui ids unique when entities share a name
                // (or a name is too long to fit) without showing in the label.
                var buf: [96]u8 = undefined;
                const label = if (slot.entity.name) |n|
                    std.fmt.bufPrintZ(&buf, "{s}##{d}", .{ n[0..@min(n.len, 64)], i })
                else
                    std.fmt.bufPrintZ(&buf, "Entity {d}", .{i});

                if (ig.igSelectable((label catch continue).ptr)) {
                    editor.selected_entity = .{ .index = @intCast(i), .generation = slot.generation };
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
