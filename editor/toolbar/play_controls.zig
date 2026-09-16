const ig = @import("cimgui");

pub const PlayControls = struct {
    pub fn draw(is_playing: *bool) void {
        // Simple toggle logic
        if (is_playing.*) {
            if (ig.igMenuItem("STOP")) {
                is_playing.* = false;
            }
        } else {
            if (ig.igMenuItem("PLAY")) {
                is_playing.* = true;
            }
        }
    }
};
