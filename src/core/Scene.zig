const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Scene = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    update: *const fn (ctx: *anyopaque, dt: f32) void,
    render: *const fn (ctx: *anyopaque) void,
    deinit: *const fn (ctx: *anyopaque, alloc: Allocator) void,
};

pub inline fn update(self: Scene, dt: f32) void {
    self.vtable.update(self.ptr, dt);
}

pub inline fn render(self: Scene) void {
    self.vtable.render(self.ptr);
}

pub inline fn deinit(self: Scene, alloc: Allocator) void {
    self.vtable.deinit(self.ptr, alloc);
}

pub fn init(ptr: anytype) Scene {
    const info = @typeInfo(@TypeOf(ptr));
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("Scene.init expects a *T pointer");
    }

    const T = info.pointer.child;

    // Require the type to implement these methods:
    comptime {
        if (!@hasDecl(T, "update")) {
            @compileError("Scene type must have pub fn update(self: *T, dt: f32) void");
        }
        if (!@hasDecl(T, "render")) {
            @compileError("Scene type must have pub fn render(self: *T) void");
        }
        if (!@hasDecl(T, "deinit")) {
            @compileError("Scene type must have pub fn deinit(self: *T, alloc: Allocator) void");
        }
    }

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = vtableFor(T),
    };
}

// Build a vtable for a given scene type T.
fn vtableFor(comptime T: type) *const VTable {
    const Impl = struct {
        fn v_update(ctx: *anyopaque, dt: f32) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.update(self, dt);
        }

        fn v_render(ctx: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.render(self);
        }

        fn v_deinit(ctx: *anyopaque, alloc: Allocator) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.deinit(self, alloc);
        }

        pub const vtable = VTable{
            .update = v_update,
            .render = v_render,
            .deinit = v_deinit,
        };
    };

    return &Impl.vtable;
}
