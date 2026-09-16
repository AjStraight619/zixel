const ig = @import("cimgui");
const Editor = @import("../../Editor.zig");

pub fn draw(editor: *Editor) void {
    if (ig.igBeginMenu("View")) {

        // Reverted to standard igMenuItem
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
}
