const std = @import("std");
const ig = @import("cimgui");
const Editor = @import("../Editor.zig");
const logging = @import("../logging.zig");
const Logger = @import("zixel_new").logging.Logger;

// UI-thread-only snapshot and filter state. Log producers never call ImGui.
// The snapshot is refreshed only when the log changes, not copied every frame.
var records: [256]Logger.Record = undefined;
var record_count: usize = 0;
var seen_revision: u64 = 0;
var scope_filter: [128]u8 = @splat(0);
var max_level: c_int = 3;

pub fn draw(editor: *Editor) void {
    if (!editor.show_console) return;

    ig.igSetNextWindowPos(.{ .x = 10, .y = 540 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 600, .y = 150 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Console", &editor.show_console, 0)) {
        if (ig.igButton("Clear")) {
            if (logging.active) |logger| logger.clear();
        }
        _ = ig.igCombo("Level", &max_level, "Error\x00Warning\x00Info\x00Debug\x00\x00");
        _ = ig.igInputText("Scope", &scope_filter, scope_filter.len, ig.ImGuiInputTextFlags_None);
        ig.igSeparator();

        _ = ig.igBeginChild("ScrollingRegion", .{ .x = 0, .y = 0 }, 0, 0);
        if (logging.active) |logger| {
            const filter = std.mem.sliceTo(&scope_filter, 0);
            if (logger.snapshotIfChanged(&seen_revision, &records)) |fresh| record_count = fresh.len;
            for (records[0..record_count]) |*record| {
                if (@intFromEnum(record.level) > max_level) continue;
                if (filter.len != 0 and std.mem.indexOf(u8, record.scope, filter) == null) continue;
                const text = std.mem.trimEnd(u8, record.text(), "\n");
                ig.igTextUnformattedEx(text.ptr, text.ptr + text.len);
            }
        }
        ig.igEndChild();
    }
    ig.igEnd();
}
