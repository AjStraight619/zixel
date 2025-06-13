#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
  PROJECT_NAME='Project'
else
  PROJECT_NAME=$1
fi

mkdir "$PROJECT_NAME" && cd "$PROJECT_NAME" || exit
touch build.zig
echo "Generating project files..."

zig init
rm build.zig
rm src/root.zig

echo 'const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const zixel_dep = b.dependency("zixel", .{
        .target = target,
        .optimize = optimize,
    });

    const zixel = zixel_dep.module("zixel");

    const exe = b.addExecutable(.{ .name = "'$PROJECT_NAME'", .root_source_file = b.path("src/main.zig"), .optimize = optimize, .target = target });

    exe.root_module.addImport("zixel", zixel);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run '$PROJECT_NAME'");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}' >> build.zig

zig fetch --save git+https://github.com/AjStraight619/zixel#main

mkdir resources
touch resources/placeholder.txt

echo 'const std = @import("std");
const zixel = @import("zixel");
const rl = zixel.raylib;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try zixel.ECSEngine.init(allocator, .{
        .window_title = "My Zixel Game",
        .window_width = 800,
        .window_height = 600,
    });
    defer engine.deinit();

    // Create a simple player entity
    const player = try engine.createPlayer(rl.Vector2.init(400, 300));
    
    // Add a shape to make it visible
    try engine.addComponent(player, zixel.components.Shape.circle(25, true));

    try engine.run();
}' > src/main.zig

# Create .gitignore
cat > .gitignore << 'EOF'
zig-cache/
zig-out/
.zig-cache/
*.exe
*.dll
*.so
*.dylib
.DS_Store
EOF

echo "Project '$PROJECT_NAME' created successfully!"
echo ""
echo "To get started:"
echo "  cd $PROJECT_NAME"
echo "  zig build run"
echo ""
echo "To update dependencies:"
echo "  zig fetch --save git+https://github.com/AjStraight619/zixel#main" 