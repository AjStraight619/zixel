const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../../Editor.zig");
const sapp = @import("sokol").app;
const new_scene = @import("new_scene.zig");

var new_scene_dialog = new_scene.NewSceneDialog.init();

pub fn draw(editor: *Editor, is_playing: *bool) void {
    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenu("File")) {
            if (ig.igMenuItem("New Scene")) {
                new_scene_dialog.open();
            }
            if (ig.igMenuItem("Save Scene")) editor.log("Saved");
            ig.igSeparator();
            if (ig.igMenuItem("Exit")) sapp.requestQuit();
            ig.igEndMenu();
        }

        new_scene_dialog.draw();

        if (ig.igBeginMenu("View")) {
            if (ig.igMenuItem("Hierarchy")) {
                editor.show_hierarchy = !editor.show_hierarchy;
            }
            if (ig.igMenuItem("Inspector")) {
                editor.show_inspector = !editor.show_inspector;
            }
            if (ig.igMenuItem("Console")) {
                editor.show_console = !editor.show_console;
            }
            ig.igEndMenu();
        }

        ig.igSeparator();

        if (is_playing.*) {
            if (ig.igMenuItem("STOP")) is_playing.* = false;
        } else {
            if (ig.igMenuItem("PLAY")) is_playing.* = true;
        }

        ig.igEndMainMenuBar();
    }
}
