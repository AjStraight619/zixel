const std = @import("std");
const cimgui = @import("cimgui");

fn projectVersionFromZon() []const u8 {
    const zon_text = @embedFile("build.zig.zon");

    var buf: [64 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const parsed = std.zon.parse.fromSlice(
        struct { version: []const u8 },
        fba.allocator(),
        zon_text,
        null,
        .{ .ignore_unknown_fields = true },
    ) catch @panic("Invalid build.zig.zon (could not parse .version)");

    return parsed.version;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build info
    const buildinfo = b.addOptions();
    buildinfo.addOption([]const u8, "version", projectVersionFromZon());

    const cimgui_conf = cimgui.getConfig(false);
    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    const dep_sokol_game = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = false,
    });

    const dep_sokol_editor = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    // Link CImGui to the Editor's Sokol
    dep_sokol_editor.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    // Module A: For the Game (Lightweight)
    const zixel_game_mod = b.addModule("zixel_new", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zixel_game_mod.addImport("sokol", dep_sokol_game.module("sokol"));

    // Module B: For the Editor (Heavy)
    // It uses the SAME source code ("src/root.zig"), but imports the "Heavy" Sokol.
    const zixel_editor_mod = b.addModule("zixel_editor_lib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zixel_editor_mod.addImport("sokol", dep_sokol_editor.module("sokol"));

    const game_exe = b.addExecutable(.{
        .name = "zixel_game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    game_exe.root_module.addImport("zixel_new", zixel_game_mod); // Use Game Module
    game_exe.root_module.addImport("sokol", dep_sokol_game.module("sokol"));
    game_exe.root_module.addOptions("zixel_buildinfo", buildinfo);
    b.installArtifact(game_exe);

    // Run Command for Game
    const run_step = b.step("run", "Run the game");
    const run_cmd = b.addRunArtifact(game_exe);
    run_step.dependOn(&run_cmd.step);

    const editor_exe = b.addExecutable(.{
        .name = "zixel_editor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("editor/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // The Editor uses the "Editor" version of the library + CImGui
    editor_exe.root_module.addImport("zixel_new", zixel_editor_mod);
    editor_exe.root_module.addImport("sokol", dep_sokol_editor.module("sokol"));
    editor_exe.root_module.addImport("cimgui", dep_cimgui.module(cimgui_conf.module_name));
    editor_exe.root_module.addOptions("zixel_buildinfo", buildinfo);
    b.installArtifact(editor_exe);

    // Run Command for Editor
    const run_editor_step = b.step("editor", "Run the Zixel editor");
    const run_editor_cmd = b.addRunArtifact(editor_exe);
    run_editor_step.dependOn(&run_editor_cmd.step);

    const cli_exe = b.addExecutable(.{
        .name = "zixel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cli_exe.root_module.addImport("zixel_new", zixel_game_mod);
    cli_exe.root_module.addOptions("zixel_buildinfo", buildinfo);
    b.installArtifact(cli_exe);

    const run_cli_step = b.step("cli", "Run the Zixel CLI");
    const run_cli_cmd = b.addRunArtifact(cli_exe);
    if (b.args) |args| {
        run_editor_cmd.addArgs(args);
    }
    run_cli_step.dependOn(&run_cli_cmd.step);

    const Sample = struct {
        exe_name: []const u8,
        file: []const u8,
        run_step: []const u8,
        desc: []const u8,
    };

    const samples = [_]Sample{
        .{ .exe_name = "render_example", .file = "samples/render_example.zig", .run_step = "run-render-example", .desc = "Run the render example" },
        .{ .exe_name = "physics_example", .file = "samples/physics_example.zig", .run_step = "run-physics-example", .desc = "Run the physics example" },
        .{ .exe_name = "ramps_example", .file = "samples/ramps_example.zig", .run_step = "run-ramps-example", .desc = "Run the ramps example" },
        .{ .exe_name = "angular_vel_example", .file = "samples/angular_vel_example.zig", .run_step = "run-angular-vel-example", .desc = "Run the angular velocity example" },
        .{ .exe_name = "astar_example", .file = "samples/astar_example.zig", .run_step = "run-astar-example", .desc = "Run the astar example" },
    };

    inline for (samples) |s| {
        const sample_exe = b.addExecutable(.{
            .name = s.exe_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(s.file),
                .target = target,
                .optimize = optimize,
            }),
        });
        // Samples use the Game Module (Lightweight)
        sample_exe.root_module.addImport("zixel_new", zixel_game_mod);
        sample_exe.root_module.addImport("sokol", dep_sokol_game.module("sokol"));
        sample_exe.root_module.addOptions("zixel_buildinfo", buildinfo);

        b.installArtifact(sample_exe);

        const run_sample_step = b.step(s.run_step, s.desc);
        const run_sample_cmd = b.addRunArtifact(sample_exe);
        run_sample_step.dependOn(&run_sample_cmd.step);
    }

    // Tests
    const mod_tests = b.addTest(.{ .root_module = zixel_game_mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
