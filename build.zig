const std = @import("std");
const cimgui = @import("cimgui");

fn projectVersionFromZon() []const u8 {
    return @import("build.zig.zon").version;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Only run tests whose name contains this text (may be repeated)",
    ) orelse &.{};
    // Compiles every program and test without installing or running anything,
    // for quick error checking and editor build-on-save.
    const check_step = b.step("check", "Compile everything without installing it");

    const buildinfo = b.addOptions();

    buildinfo.addOption([]const u8, "version", projectVersionFromZon());
    // Where this checkout lives, so `zixel new` can point new projects at it.
    buildinfo.addOption([]const u8, "source_dir", b.pathFromRoot("."));

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
    dep_sokol_editor.artifact("sokol_clib").root_module.addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    // Module A: For the Game (Lightweight)
    const zixel_game_mod = b.addModule("zixel_new", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zixel_game_mod.addImport("sokol", dep_sokol_game.module("sokol"));

    // Module B: For the Editor (Heavy)
    // It uses the SAME source code ("src/root.zig"), but imports the "Heavy" Sokol.
    // Private to this build: packages that depend on Zixel only see Module A.
    const zixel_editor_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zixel_editor_mod.addImport("sokol", dep_sokol_editor.module("sokol"));

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
    check_step.dependOn(&b.addExecutable(.{ .name = "zixel_editor", .root_module = editor_exe.root_module }).step);

    // Run Command for Editor
    const run_step = b.step("run", "Run the Zixel editor");
    const run_editor_step = b.step("editor", "Run the Zixel editor");
    const run_editor_cmd = b.addRunArtifact(editor_exe);
    run_step.dependOn(&run_editor_cmd.step);
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
    check_step.dependOn(&b.addExecutable(.{ .name = "zixel", .root_module = cli_exe.root_module }).step);

    const run_cli_step = b.step("cli", "Run the Zixel CLI");
    const run_cli_cmd = b.addRunArtifact(cli_exe);
    if (b.args) |args| {
        run_editor_cmd.addArgs(args);
        run_cli_cmd.addArgs(args);
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
        .{ .exe_name = "persist_example", .file = "samples/persist_example.zig", .run_step = "run-persist-example", .desc = "Run the persistence example (-- --headless for a transcript)" },
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
        check_step.dependOn(&b.addExecutable(.{ .name = s.exe_name, .root_module = sample_exe.root_module }).step);

        const run_sample_step = b.step(s.run_step, s.desc);
        const run_sample_cmd = b.addRunArtifact(sample_exe);
        if (b.args) |args| run_sample_cmd.addArgs(args);
        run_sample_step.dependOn(&run_sample_cmd.step);
    }

    // Headless physics benchmarks, separate from normal correctness tests.
    const benchmarks = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/bench_runner.zig"),
        .target = target,
        .optimize = optimize,
    }), .filters = &.{"benchmark:"} });
    const run_benchmarks = b.addRunArtifact(benchmarks);
    run_benchmarks.has_side_effects = true;
    const bench_step = b.step("bench", "Measure headless physics (use -Doptimize=ReleaseFast)");
    bench_step.dependOn(&run_benchmarks.step);

    // Tests: one binary per root file, all behind `zig build test`.
    const editor_args_mod = b.createModule(.{
        .root_source_file = b.path("editor/Args.zig"),
        .target = target,
        .optimize = optimize,
    });
    const editor_project_mod = b.createModule(.{
        .root_source_file = b.path("editor/project.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Editor state, built against the same engine module and UI library as the editor.
    const editor_state_mod = b.createModule(.{
        .root_source_file = b.path("editor/Editor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zixel_new", .module = zixel_editor_mod },
            .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_conf.module_name) },
        },
    });
    const cli_parse_mod = b.createModule(.{
        .root_source_file = b.path("cli/parse.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_parse_mod.addOptions("zixel_buildinfo", buildinfo);

    const test_step = b.step("test", "Run tests");
    const test_modules = [_]*std.Build.Module{
        zixel_game_mod,
        editor_args_mod,
        editor_project_mod,
        editor_state_mod,
        cli_parse_mod,
    };
    for (test_modules) |module| {
        const tests = b.addTest(.{ .root_module = module, .filters = test_filters });
        test_step.dependOn(&b.addRunArtifact(tests).step);
        check_step.dependOn(&b.addTest(.{ .root_module = module }).step);
    }
}
