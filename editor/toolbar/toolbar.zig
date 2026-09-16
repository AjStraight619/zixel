const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");

const file_menu = @import("file/file_menu.zig");
const view_menu = @import("view/view_menu.zig");
const asset_menu = @import("asset/asset_menu.zig");
const play_controls = @import("play_controls.zig");

pub fn draw(editor: *Editor, is_playing: *bool) void {
    if (ig.igBeginMainMenuBar()) {
        file_menu.draw(editor);
        view_menu.draw(editor);
        asset_menu.draw(editor);

        ig.igSeparator();
        play_controls.draw(is_playing);

        ig.igEndMainMenuBar();
    }
}
