const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const NewArgs = @import("NewArgs.zig");

const build_zig_tmpl =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {{
    \\    const target = b.standardTargetOptions(.{{}});
    \\    const optimize = b.standardOptimizeOption(.{{}});
    \\
    \\    const exe = b.addExecutable(.{{
    \\        .name = "{s}",
    \\        .root_source_file = b.path("src/main.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    }});
    \\
    \\    // Link against the Zixel engine
    \\    const zixel_dep = b.dependency("zixel", .{{
    \\        .target = target,
    \\        .optimize = optimize,
    \\    }});
    \\    exe.root_module.addImport("zixel", zixel_dep.module("zixel"));
    \\
    \\    b.installArtifact(exe);
    \\
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    if (b.args) |args| run_cmd.addArgs(args);
    \\    const run_step = b.step("run", "Run the app");
    \\    run_step.dependOn(&run_cmd.step);
    \\}}
;

const zon_tmpl =
    \\.{{
    \\    .name = "{s}",
    \\    .version = "0.1.0",
    \\    .dependencies = .{{
    \\        .zixel = .{{
    \\            .path = "../zixel_new"
    \\        }},
    \\    }},
    \\    .paths = .{{""}},
    \\}}
;

const main_zig_tmpl =
    \\const std = @import("std");
    \\const zixel = @import("zixel");
    \\
    \\pub fn main() !void {{
    \\    // Initialize the engine with default settings
    \\    var engine = try zixel.Engine.init(std.heap.c_allocator, .{{
    \\        .window = .{{
    \\            .title = "{s}",
    \\            .width = 1280,
    \\            .height = 720,
    \\        }},
    \\    }});
    \\    defer engine.deinit();
    \\
    \\    // Run the game loop
    \\    engine.run();
    \\}}
;

const project_json_tmpl =
    \\{{
    \\    "name": "{s}",
    \\    "version": "0.1.0",
    \\    "start_scene": "assets/scenes/main.json"
    \\}}
;

const main_scene_json =
    \\{{
    \\    "entities": [],
    \\    "meta": {{ "created_at": "now" }}
    \\}}
;

pub fn run(alloc: Allocator, stdout: anytype, args: NewArgs) !void {
    // const cwd = fs.cwd();
    // const name = args.name;

    _ = alloc;
    _ = stdout;
    _ = args;

    // if (cwd.openDir(name, .{ .iterate = true })) |*existing_dir| {
    //     defer existing_dir.close();
    //     var it = existing_dir.iterate();
    //     if (try it.next()) |_| {
    //         try stdout.print("Error: Directory '{s}' already exists and is not empty.\n", .{name});
    //         return;
    //     }
    // } else |_| {
    //     // Directory doesn't exist, which is good. Create it.
    //     try cwd.makePath(name);
    // }

    // try stdout.print("Scaffolding Zixel project: {s}...\n", .{name});

    // var dir = try cwd.openDir(name, .{});
    // defer dir.close();

    // try dir.makePath("src");

    // // Write build.zig
    // const build_content = try std.fmt.allocPrint(alloc, build_zig_tmpl, .{name});
    // defer alloc.free(build_content);
    // try dir.writeFile(.{ .sub_path = "build.zig", .data = build_content });

    // // Write build.zig.zon
    // const zon_content = try std.fmt.allocPrint(alloc, zon_tmpl, .{name});
    // defer alloc.free(zon_content);
    // try dir.writeFile(.{ .sub_path = "build.zig.zon", .data = zon_content });

    // // Write src/main.zig
    // const main_content = try std.fmt.allocPrint(alloc, main_zig_tmpl, .{name});
    // defer alloc.free(main_content);
    // try dir.writeFile(.{ .sub_path = "src/main.zig", .data = main_content });

    // // Write .gitignore
    // try dir.writeFile(.{ .sub_path = ".gitignore", .data = "zig-cache/\nzig-out/\n" });

    // try dir.makePath("assets");
    // try dir.makePath("assets/scenes");
    // try dir.makePath("assets/sprites");
    // try dir.makePath("settings");

    // // Create 'settings/project.json'
    // const proj_content = try std.fmt.allocPrint(alloc, project_json_tmpl, .{name});
    // defer alloc.free(proj_content);
    // try dir.writeFile(.{ .sub_path = "settings/project.json", .data = proj_content });

    // try dir.writeFile(.{ .sub_path = "assets/scenes/main.json", .data = main_scene_json });

    // try stdout.print("Done! Project ready.\n", .{});
}
