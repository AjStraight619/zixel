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

<<<<<<< HEAD
    // Build info (available to code as @import("zixel_buildinfo"))
    const buildinfo = b.addOptions();
    buildinfo.addOption([]const u8, "version", projectVersionFromZon());
=======
    // Editor is enabled by default in Debug, disabled in Release
    const enable_editor = b.option(bool, "editor", "Enable built-in editor overlay") orelse (optimize == .Debug);
>>>>>>> db6c019 (feat(editor): add compile-time optional editor overlay)

    // cimgui config (non-docking version)
    const cimgui_conf = cimgui.getConfig(false);

    // cimgui dependency
    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    // We need sokol with imgui for both the main module (when editor enabled)
    // and always for the standalone editor
    const dep_sokol_with_imgui = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    dep_sokol_with_imgui.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const dep_sokol_no_imgui = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = false,
    });

    // Select which sokol to use based on editor flag
    const mod_sokol = if (enable_editor)
        dep_sokol_with_imgui.module("sokol")
    else
        dep_sokol_no_imgui.module("sokol");

    // Build options module (passed to engine so it knows if editor is enabled)
    const options = b.addOptions();
    options.addOption(bool, "enable_editor", enable_editor);

    // Main library module
    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    try imports.append(b.allocator, .{ .name = "sokol", .module = mod_sokol });
    try imports.append(b.allocator, .{ .name = "zixel_options", .module = options.createModule() });
    if (enable_editor) {
        try imports.append(b.allocator, .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_conf.module_name) });
    }

    const mod = b.addModule("zixel_new", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports.items,
    });

    // Standalone editor module (always has editor enabled)
    const editor_options = b.addOptions();
    editor_options.addOption(bool, "enable_editor", true);

    const mod_editor = b.addModule("zixel_editor", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol_with_imgui.module("sokol") },
            .{ .name = "zixel_options", .module = editor_options.createModule() },
            .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_conf.module_name) },
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zixel_new",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
                .{ .name = "sokol", .module = mod_sokol },
            },
        }),
    });
    exe.root_module.addOptions("zixel_buildinfo", buildinfo);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    // CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "zixel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
            },
        }),
    });
    cli_exe.root_module.addOptions("zixel_buildinfo", buildinfo);

    b.installArtifact(cli_exe);

    const run_cli_step = b.step("cli", "Run the Zixel CLI");
    const run_cli_cmd = b.addRunArtifact(cli_exe);
    run_cli_step.dependOn(&run_cli_cmd.step);
    run_cli_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cli_cmd.addArgs(args);

<<<<<<< HEAD
    // Editor
=======
    // ---------------------------------------------------------------------
    // Standalone Editor (always has editor enabled)
    // ---------------------------------------------------------------------
>>>>>>> db6c019 (feat(editor): add compile-time optional editor overlay)
    const editor_exe = b.addExecutable(.{
        .name = "zixel-editor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("editor/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod_editor },
                .{ .name = "sokol", .module = dep_sokol_with_imgui.module("sokol") },
            },
        }),
    });
    editor_exe.root_module.addOptions("zixel_buildinfo", buildinfo);

    b.installArtifact(editor_exe);

    const run_editor_step = b.step("editor", "Run the Zixel editor");
    const run_editor_cmd = b.addRunArtifact(editor_exe);
    run_editor_step.dependOn(&run_editor_cmd.step);
    run_editor_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_editor_cmd.addArgs(args);

    // Samples
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
                .imports = &.{
                    .{ .name = "zixel_new", .module = mod },
                    .{ .name = "sokol", .module = mod_sokol },
                },
            }),
        });
        sample_exe.root_module.addOptions("zixel_buildinfo", buildinfo);

        b.installArtifact(sample_exe);

        const run_sample_step = b.step(s.run_step, s.desc);
        const run_sample_cmd = b.addRunArtifact(sample_exe);
        run_sample_step.dependOn(&run_sample_cmd.step);
        run_sample_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_sample_cmd.addArgs(args);
    }

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
