const std = @import("std");

const ig = @import("cimgui");
const sapp = @import("sokol").app;

const Editor = @import("../Editor.zig");

pub fn draw(editor: *Editor) void {
    if (ig.igBeginMenu("Assets")) {
        _ = editor;
        ig.igEndMenu();
    }
}
