const std = @import("std");
const ig = @import("cimgui");
const sapp = @import("sokol").app;

const Editor = @import("../Editor.zig");
const log = std.log.scoped(.zixel_scene);

pub fn draw(editor: *Editor) void {
    if (ig.igBeginMenu("File")) {
        if (ig.igMenuItem("New Scene")) {
            // Trigger the state change in the editor
            editor.new_scene_dialog.open();
        }

        if (ig.igMenuItem("Save Scene")) {
            log.warn("Saving scenes is not implemented yet", .{});
        }

        ig.igSeparator();

        if (ig.igMenuItem("Exit")) {
            sapp.requestQuit();
        }

        ig.igEndMenu();
    }
}
