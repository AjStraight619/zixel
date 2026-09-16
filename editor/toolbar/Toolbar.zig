const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");

const FileMenu = @import("file/file_menu.zig").FileMenu;
const ViewMenu = @import("view/view_menu.zig").ViewMenu;
const AssetMenu = @import("asset/asset_menu.zig").AssetMenu;
const PlayControls = @import("play_controls.zig").PlayControls;

pub const Toolbar = struct {
    pub fn draw(editor: *Editor, is_playing: *bool) void {
        if (ig.igBeginMainMenuBar()) {
            FileMenu.draw(editor);
            ViewMenu.draw(editor);
            AssetMenu.draw(editor);

            ig.igSeparator();
            PlayControls.draw(is_playing);

            ig.igEndMainMenuBar();
        }
    }
};
