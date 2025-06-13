const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options for compile-time configuration
    const options = b.addOptions();

    // Log level based on build mode
    const log_level: std.log.Level = switch (optimize) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast, .ReleaseSmall => .warn,
    };
    options.addOption(std.log.Level, "log_level", log_level);

    // Enable/disable debug features
    const enable_debug_features = optimize == .Debug;
    options.addOption(bool, "enable_debug_features", enable_debug_features);

    // Enable/disable performance profiling
    const enable_profiling = b.option(bool, "profiling", "Enable performance profiling") orelse false;
    options.addOption(bool, "enable_profiling", enable_profiling);

    // Physics debug options
    const physics_debug = b.option(bool, "physics-debug", "Enable physics debug rendering") orelse enable_debug_features;
    options.addOption(bool, "physics_debug", physics_debug);

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("raylib", raylib);
    lib_mod.addImport("raygui", raygui);
    lib_mod.addOptions("build_options", options);

    const lib = b.addLibrary(.{
        .name = "zixel",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Helper function to reduce repetition (updated to include build_options)
    const createExampleExe = struct {
        fn call(
            builder: *std.Build,
            name: []const u8,
            source_path: []const u8,
            lib_module: *std.Build.Module,
            raylib_mod: *std.Build.Module,
            raygui_mod: *std.Build.Module,
            raylib_art: *std.Build.Step.Compile,
            build_target: std.Build.ResolvedTarget,
            build_optimize: std.builtin.OptimizeMode,
            build_options: *std.Build.Step.Options,
        ) *std.Build.Step.Compile {
            const mod = builder.createModule(.{
                .root_source_file = builder.path(source_path),
                .target = build_target,
                .optimize = build_optimize,
            });
            mod.addImport("zixel", lib_module);
            mod.addImport("raylib", raylib_mod);
            mod.addImport("raygui", raygui_mod);
            mod.addOptions("build_options", build_options);

            const exe = builder.addExecutable(.{
                .name = name,
                .root_module = mod,
            });
            builder.installArtifact(exe);
            exe.linkLibrary(raylib_art);
            return exe;
        }
    }.call;

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("raylib", raylib);
    lib_unit_tests.root_module.addImport("raygui", raygui);
    lib_unit_tests.root_module.addOptions("build_options", options);
    lib_unit_tests.linkLibrary(raylib_artifact);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Examples - updated to include build_options
    const basic_exe = createExampleExe(b, "example_basic", "examples/basic/main.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize, options);
    const run_basic = b.addRunArtifact(basic_exe);
    const run_basic_step = b.step("run-basic", "Run the basic example");
    run_basic_step.dependOn(&run_basic.step);

    const advanced_exe = createExampleExe(b, "example_advanced", "examples/advanced/main.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize, options);
    const run_advanced = b.addRunArtifact(advanced_exe);
    const run_advanced_step = b.step("run-advanced", "Run the advanced example");
    run_advanced_step.dependOn(&run_advanced.step);

    const circle_vs_rect_exe = createExampleExe(b, "circle_vs_rect", "tests/rectvscircle.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize, options);
    const run_circle_vs_rect = b.addRunArtifact(circle_vs_rect_exe);
    const run_circle_vs_rect_step = b.step("run-circle-vs-rect", "Run the circle vs rect test");
    run_circle_vs_rect_step.dependOn(&run_circle_vs_rect.step);

    const physics_verification_exe = createExampleExe(b, "physics_verification", "examples/physics_verification.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize, options);
    const run_physics_verification = b.addRunArtifact(physics_verification_exe);
    const run_physics_verification_step = b.step("run-physics-tests", "Run the physics verification tests");
    run_physics_verification_step.dependOn(&run_physics_verification.step);
}
