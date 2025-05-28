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
        .name = "zig2d",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Tests - using dedicated test runner
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

    // Basic example
    const basic_mod = b.createModule(.{
        .root_source_file = b.path("examples/basic/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_mod.addImport("zig2d", lib_mod);
    basic_mod.addImport("raylib", raylib);
    basic_mod.addImport("raygui", raygui);

    const basic_exe = b.addExecutable(.{
        .name = "example_basic",
        .root_module = basic_mod,
    });
    b.installArtifact(basic_exe);
    basic_exe.linkLibrary(raylib_artifact);

    const run_basic = b.addRunArtifact(basic_exe);
    const run_basic_step = b.step("run-basic", "Run the basic example");
    run_basic_step.dependOn(&run_basic.step);

    // Advanced example
    const advanced_mod = b.createModule(.{
        .root_source_file = b.path("examples/advanced/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    advanced_mod.addImport("zig2d", lib_mod);
    advanced_mod.addImport("raylib", raylib);
    advanced_mod.addImport("raygui", raygui);

    const advanced_exe = b.addExecutable(.{
        .name = "example_advanced",
        .root_module = advanced_mod,
    });
    b.installArtifact(advanced_exe);
    advanced_exe.linkLibrary(raylib_artifact);

    const run_advanced = b.addRunArtifact(advanced_exe);
    const run_advanced_step = b.step("run-advanced", "Run the advanced example");
    run_advanced_step.dependOn(&run_advanced.step);

    // Physics Verification Tests
    const physics_verification_mod = b.createModule(.{
        .root_source_file = b.path("examples/physics_verification.zig"),
        .target = target,
        .optimize = optimize,
    });
    physics_verification_mod.addImport("zig2d", lib_mod);
    physics_verification_mod.addImport("raylib", raylib);
    physics_verification_mod.addImport("raygui", raygui);

    const physics_verification_exe = b.addExecutable(.{
        .name = "physics_verification",
        .root_module = physics_verification_mod,
    });
    b.installArtifact(physics_verification_exe);
    physics_verification_exe.linkLibrary(raylib_artifact);

    const run_physics_verification = b.addRunArtifact(physics_verification_exe);
    const run_physics_verification_step = b.step("run-physics-tests", "Run the physics verification tests");
    run_physics_verification_step.dependOn(&run_physics_verification.step);
}
