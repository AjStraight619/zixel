const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const lib = b.addLibrary(.{
        .name = "zixel",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Helper function to reduce repetition
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
        ) *std.Build.Step.Compile {
            const mod = builder.createModule(.{
                .root_source_file = builder.path(source_path),
                .target = build_target,
                .optimize = build_optimize,
            });
            mod.addImport("zixel", lib_module);
            mod.addImport("raylib", raylib_mod);
            mod.addImport("raygui", raygui_mod);

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
    lib_unit_tests.linkLibrary(raylib_artifact);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Examples - much cleaner now!
    const basic_exe = createExampleExe(b, "example_basic", "examples/basic/main.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    const run_basic = b.addRunArtifact(basic_exe);
    const run_basic_step = b.step("run-basic", "Run the basic example");
    run_basic_step.dependOn(&run_basic.step);

    const advanced_exe = createExampleExe(b, "example_advanced", "examples/advanced/main.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    const run_advanced = b.addRunArtifact(advanced_exe);
    const run_advanced_step = b.step("run-advanced", "Run the advanced example");
    run_advanced_step.dependOn(&run_advanced.step);

    const ecs_demo_exe = createExampleExe(b, "ecs_demo", "examples/ecs_demo/main.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    const run_ecs_demo = b.addRunArtifact(ecs_demo_exe);
    const run_ecs_demo_step = b.step("run-ecs-demo", "Run the ECS demo");
    run_ecs_demo_step.dependOn(&run_ecs_demo.step);

    // Legacy examples (temporarily disabled while focusing on ECS)
    // const circle_vs_rect_exe = createExampleExe(b, "circle_vs_rect", "tests/rectvscircle.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    // const run_circle_vs_rect = b.addRunArtifact(circle_vs_rect_exe);
    // const run_circle_vs_rect_step = b.step("run-circle-vs-rect", "Run the circle vs rect test");
    // run_circle_vs_rect_step.dependOn(&run_circle_vs_rect.step);

    // const physics_verification_exe = createExampleExe(b, "physics_verification", "examples/physics_verification.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    // const run_physics_verification = b.addRunArtifact(physics_verification_exe);
    // const run_physics_verification_step = b.step("run-physics-tests", "Run the physics verification tests");
    // run_physics_verification_step.dependOn(&run_physics_verification.step);

    // Debug application for testing rendering
    const debug_render_exe = createExampleExe(b, "debug_render", "debug_render.zig", lib_mod, raylib, raygui, raylib_artifact, target, optimize);
    const run_debug_render = b.addRunArtifact(debug_render_exe);
    const debug_step = b.step("debug-render", "Run debug render test");
    debug_step.dependOn(&run_debug_render.step);
}
