const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");

pub fn draw(editor: *Editor) void {
    if (!editor.show_console) return;

    ig.igSetNextWindowPos(.{ .x = 10, .y = 540 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 600, .y = 150 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Console", &editor.show_console, 0)) {
        // FIXED: Only passing the label
        if (ig.igButton("Clear")) {
            editor.clearLog();
        }
        ig.igSeparator();

        if (ig.igBeginChild("ScrollingRegion", .{ .x = 0, .y = 0 }, 0, 0)) {
            for (editor.console_lines.items) |line| {
                ig.igTextUnformatted(line.ptr);
            }
        }
        ig.igEndChild();
    }
    ig.igEnd();
}
