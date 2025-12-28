const std = @import("std");
const fs = std.fs;

pub const Project = struct {
    pub fn scaffold(alloc: std.mem.Allocator, root_path: []const u8) !void {
        const cwd = fs.cwd();
        try cwd.makePath(root_path);

        const folders = [_][]const u8{
            "assets",
            "assets/scenes",
            "assets/sprites",
            "settings",
        };

        for (folders) |f| {
            const full_path = try std.fs.path.join(alloc, &.{ root_path, f });
            defer alloc.free(full_path);
            try cwd.makePath(full_path);
        }

        const default_config =
            \\{
            \\    "name": "New Project",
            \\    "version": "0.1.0",
            \\    "start_scene": "assets/scenes/main.json"
            \\}
        ;

        const default_scene =
            \\{
            \\    "entities": [],
            \\    "meta": { "created_at": "now" }
            \\}
        ;

        const project_json_path = try std.fs.path.join(alloc, &.{ root_path, "settings/project.json" });
        defer alloc.free(project_json_path);
        try cwd.writeFile(.{ .sub_path = project_json_path, .data = default_config });

        const main_scene_path = try std.fs.path.join(alloc, &.{ root_path, "assets/scenes/main.json" });
        defer alloc.free(main_scene_path);
        try cwd.writeFile(.{ .sub_path = main_scene_path, .data = default_scene });
    }
};
