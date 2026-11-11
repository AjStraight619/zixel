const std = @import("std");
const Allocator = std.mem.Allocator;

const Scene = @This();

/// Pointer to the allocated scene data.
ptr: *anyopaque,
/// Function pointers for the scene's interface.
vtable: *const VTable,

/// Unique identifier for the scene.
name: []const u8,
/// Prevents scenes underneath from updating when true.
is_blocking: bool,
/// Prevents scenes underneath from rendering when true.
is_opaque: bool,

/// Nested scenes owned by this scene.
children: std.ArrayListUnmanaged(Scene),

pub const VTable = struct {
    update: *const fn (ctx: *anyopaque, dt: f32) void,
    render: *const fn (ctx: *anyopaque) void,
    deinit: *const fn (ctx: *anyopaque, alloc: Allocator) void,
};

/// Executes the scene's update logic.
pub inline fn update(self: *Scene, dt: f32) void {
    self.vtable.update(self.ptr, dt);
}

/// Executes the scene's render logic.
pub inline fn render(self: *Scene) void {
    self.vtable.render(self.ptr);
}

/// Recursively frees the scene and all nested children.
pub fn deinit(self: *Scene, alloc: Allocator) void {
    var i: usize = self.children.items.len;
    while (i > 0) {
        i -= 1;
        self.children.items[i].deinit(alloc);
    }
    self.children.deinit(alloc);

    self.vtable.deinit(self.ptr, alloc);
}

/// Wraps a pointer to a struct into a Scene.
///
/// Ownership: `ptr` must have been created with the allocator later passed to
/// `Scene.deinit` (the engine's allocator). When the scene is torn down, the
/// wrapper calls `T.deinit(self, alloc)` and then destroys `ptr` itself, so
/// `T.deinit` releases only what the scene owns and must not destroy `self`.
pub fn init(ptr: anytype) Scene {
    const info = @typeInfo(@TypeOf(ptr));
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("Scene.init expects a *T pointer");
    }

    const T = info.pointer.child;

    comptime {
        const required = .{ "name", "is_blocking", "is_opaque", "update", "render", "deinit" };
        for (required) |decl| {
            if (!@hasDecl(T, decl)) {
                @compileError("Missing 'pub " ++ decl ++ "' in " ++ @typeName(T));
            }
        }
    }

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = vtableFor(T),
        .name = T.name,
        .is_blocking = T.is_blocking,
        .is_opaque = T.is_opaque,
        .children = .empty,
    };
}

/// Attaches a child scene to the hierarchy.
pub fn addChild(self: *Scene, alloc: Allocator, child: Scene) !void {
    try self.children.append(alloc, child);
}

/// Helper to create and attach a child scene.
pub fn createChild(self: *Scene, alloc: Allocator, comptime T: type, ctx: anytype) !void {
    const instance = try alloc.create(T);
    errdefer alloc.destroy(instance);
    instance.* = try T.init(ctx);
    errdefer T.deinit(instance, alloc);
    try self.addChild(alloc, Scene.init(instance));
}

pub fn removeChild(self: *Scene, alloc: Allocator, name: []const u8) bool {
    for (self.children.items, 0..) |*child, i| {
        if (std.mem.eql(u8, child.name, name)) {
            child.deinit(alloc);
            _ = self.children.orderedRemove(i);
            return true;
        }
        // Recursively check deeper
        if (child.removeChild(alloc, name)) return true;
    }
    return false;
}

fn vtableFor(comptime T: type) *const VTable {
    const Impl = struct {
        fn vUpdate(ctx: *anyopaque, dt: f32) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.update(self, dt);
        }
        fn vRender(ctx: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.render(self);
        }
        fn vDeinit(ctx: *anyopaque, alloc: Allocator) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.deinit(self, alloc);
            alloc.destroy(self);
        }

        pub const vtable = VTable{
            .update = vUpdate,
            .render = vRender,
            .deinit = vDeinit,
        };
    };
    return &Impl.vtable;
}

const TestScene = struct {
    pub const name = "test";
    pub const is_blocking = false;
    pub const is_opaque = false;

    buffer: []u8,

    pub fn init(alloc: Allocator) !TestScene {
        return .{ .buffer = try alloc.alloc(u8, 16) };
    }
    pub fn update(_: *TestScene, _: f32) void {}
    pub fn render(_: *TestScene) void {}
    pub fn deinit(self: *TestScene, alloc: Allocator) void {
        alloc.free(self.buffer);
    }
};

test "scene teardown frees each scene object exactly once" {
    const alloc = std.testing.allocator;
    const root_ptr = try alloc.create(TestScene);
    root_ptr.* = try TestScene.init(alloc);
    var root = Scene.init(root_ptr);
    try root.createChild(alloc, TestScene, alloc);
    try root.createChild(alloc, TestScene, alloc);
    try std.testing.expect(root.removeChild(alloc, "test"));
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    // std.testing.allocator reports both leaks and double frees.
    root.deinit(alloc);
}

fn createChildWithFailures(alloc: Allocator) !void {
    const root_ptr = try alloc.create(TestScene);
    root_ptr.* = TestScene.init(alloc) catch |err| {
        alloc.destroy(root_ptr);
        return err;
    };
    var root = Scene.init(root_ptr);
    defer root.deinit(alloc);
    try root.createChild(alloc, TestScene, alloc);
}

test "createChild cleans up when any allocation fails" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, createChildWithFailures, .{});
}
