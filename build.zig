const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // sokol-zig dependency
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const mod_sokol = dep_sokol.module("sokol");

    // Main library module
    const mod = b.addModule("zixel_new", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = mod_sokol },
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

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Sample: render_example
    const render_example = b.addExecutable(.{
        .name = "render_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("samples/render_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
                .{ .name = "sokol", .module = mod_sokol },
            },
        }),
    });
    b.installArtifact(render_example);

    const run_render_example = b.step("run-render-example", "Run the render example");
    const run_render_cmd = b.addRunArtifact(render_example);
    run_render_example.dependOn(&run_render_cmd.step);
    run_render_cmd.step.dependOn(b.getInstallStep());

    // Sample: physics_example
    const physics_example = b.addExecutable(.{
        .name = "physics_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("samples/physics_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
                .{ .name = "sokol", .module = mod_sokol },
            },
        }),
    });
    b.installArtifact(physics_example);

    const run_physics_example = b.step("run-physics-example", "Run the physics example");
    const run_physics_cmd = b.addRunArtifact(physics_example);
    run_physics_example.dependOn(&run_physics_cmd.step);
    run_physics_cmd.step.dependOn(b.getInstallStep());

    // Sample: ramps_example (circles rolling down ramps)
    const ramps_example = b.addExecutable(.{
        .name = "ramps_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("samples/ramps_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
                .{ .name = "sokol", .module = mod_sokol },
            },
        }),
    });
    b.installArtifact(ramps_example);

    const run_ramps_example = b.step("run-ramps-example", "Run the ramps example");
    const run_ramps_cmd = b.addRunArtifact(ramps_example);
    run_ramps_example.dependOn(&run_ramps_cmd.step);
    run_ramps_cmd.step.dependOn(b.getInstallStep());

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
