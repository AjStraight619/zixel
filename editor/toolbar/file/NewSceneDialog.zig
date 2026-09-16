const std = @import("std");
const ig = @import("cimgui");

const NewSceneDialog = @This();

input_buffer: [128]u8 = [_]u8{0} ** 128,
is_open: bool = false,

pub fn init() NewSceneDialog {
    return .{};
}

pub fn open(self: *NewSceneDialog) void {
    self.is_open = true;
    // Zero out the buffer so it's empty next time
    @memset(&self.input_buffer, 0);
}

pub fn draw(self: *NewSceneDialog) void {
    if (self.is_open) {
        ig.igOpenPopup("New Scene", ig.ImGuiPopupFlags_None);
        self.is_open = false; // We passed the command, now let ImGui handle the state
    }

    // ImGui needs a bool pointer
    var open_dummy = true;
    if (ig.igBeginPopupModal("New Scene", &open_dummy, ig.ImGuiWindowFlags_AlwaysAutoResize)) {
        ig.igText("Enter a name for the new scene:");

        _ = ig.igInputText("##scene_name", &self.input_buffer, self.input_buffer.len, ig.ImGuiInputTextFlags_None);

        ig.igSeparator();

        if (ig.igButton("Create")) {
            // Get the string slice (cutting off null terminators)
            const name = std.mem.sliceTo(&self.input_buffer, 0);
            std.debug.print("Creating Scene: {s}\n", .{name});

            ig.igCloseCurrentPopup();
        }

        ig.igSameLine();

        if (ig.igButton("Cancel")) {
            ig.igCloseCurrentPopup();
        }

        ig.igEndPopup();
    }
}

pub fn createScene(self: *NewSceneDialog, game_dir: []const u8) void {
    const name = std.mem.sliceTo(&self.input_buffer, 0);
    std.debug.print("Creating Scene: {s}\n", .{name});

    _ = game_dir;
}
