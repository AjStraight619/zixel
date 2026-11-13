const std = @import("std");
const Allocator = std.mem.Allocator;
const Vec2 = @import("../math/Vec2.zig");
const Color = @import("Color.zig");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Body = @import("../physics/Body.zig");
const BodyKind = Body.BodyKind;

const Entity = @This();

name: ?[]const u8 = null,

tags: []const []const u8 = &.{},

/// Who owns this entity - determines cleanup behavior
owner: Owner = .none,

/// Physics body (handles position, velocity, collision)
body: Body,

/// Optional visual
sprite: ?SpriteData = null,

/// Game-defined data owned by this entity. See `UserData`.
user_data: UserData = .none,

pub const Owner = union(enum) {
    /// Persistent - survives scene changes
    none,
    /// Owned by a scene - removed when scene deinits
    scene: []const u8,
};

pub const SpriteData = struct {
    color: Color = Color.white,
    texture_path: ?[]const u8 = null,
};

/// Game-defined data attached to an entity. The world releases it with its own
/// allocator when the entity is removed, so the data lives exactly as long as
/// the entity does, whichever scene attached it.
///
///     entity.user_data = try .init(world.alloc, Stats, .{});
///     if (entity.user_data.as(Stats)) |stats| stats.coins += 1;
///
/// Assigning over existing data does not release it; call `deinit` first.
pub const UserData = struct {
    erased: ?Erased = null,

    pub const none: UserData = .{};

    const Erased = struct {
        ptr: *anyopaque,
        type_id: *const anyopaque,
        drop: *const fn (ptr: *anyopaque, alloc: Allocator) void,
    };

    /// Moves `value` into a new allocation. `alloc` must be the allocator of
    /// the world the entity lives in. If `T` declares
    /// `deinit(self: *T, alloc: Allocator) void`, it runs on release.
    pub fn init(alloc: Allocator, comptime T: type, value: T) !UserData {
        const ptr = try alloc.create(T);
        ptr.* = value;
        const Drop = struct {
            fn drop(erased: *anyopaque, a: Allocator) void {
                const typed: *T = @ptrCast(@alignCast(erased));
                if (comptime hasDeinit(T)) typed.deinit(a);
                a.destroy(typed);
            }
        };
        return .{ .erased = .{ .ptr = ptr, .type_id = typeId(T), .drop = Drop.drop } };
    }

    /// The data as a `T`. Null if there is none or it was stored as another type.
    pub fn as(self: UserData, comptime T: type) ?*T {
        const erased = self.erased orelse return null;
        if (erased.type_id != typeId(T)) return null;
        return @ptrCast(@alignCast(erased.ptr));
    }

    /// Releases the data, if any, and leaves `none` behind.
    pub fn deinit(self: *UserData, alloc: Allocator) void {
        if (self.erased) |erased| erased.drop(erased.ptr, alloc);
        self.* = .none;
    }

    fn hasDeinit(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "deinit"),
            else => false,
        };
    }

    /// An address that is distinct for every type.
    fn typeId(comptime T: type) *const anyopaque {
        const Marker = struct {
            const Tagged = T;
            // Mutable so identical constants cannot be merged into one address.
            var byte: u8 = 0;
        };
        return &Marker.byte;
    }
};

/// Creates an owned snapshot for serialization. Call deinit on the result.
/// User data is not part of a definition and is not copied.
pub fn toDef(self: Entity, alloc: Allocator) !OwnedEntityDef {
    const def = EntityDef{
        .name = self.name,
        .tags = self.tags,
        .owner = self.owner,
        .position = self.body.position,
        .rotation = self.body.rotation,
        .body = .{
            .kind = self.body.kind,
            .shape = self.body.shape,
            .mass = self.body.mass,
            .friction = self.body.friction,
            .restitution = self.body.restitution,
            .velocity = self.body.velocity,
            .inertia = self.body.inertia,
        },
        .sprite = self.sprite,
    };
    return def.clone(alloc);
}

/// Borrowed description for spawning or saving an entity. Strings may be literals.
/// The caller keeps referenced data alive while the definition or spawned entity uses it.
pub const EntityDef = struct {
    name: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    owner: Entity.Owner = .none,
    position: Vec2 = Vec2.zero,
    rotation: f32 = 0,
    body: ?BodyDef = null,
    sprite: ?Entity.SpriteData = null,

    pub const BodyDef = struct {
        kind: BodyKind = .dynamic,
        shape: PhysicsShape,
        mass: f32 = 1.0,
        friction: f32 = 0.5,
        restitution: f32 = 0.5,
        velocity: Vec2 = Vec2.zero,
        inertia: ?f32 = null,
    };

    pub fn init() EntityDef {
        return .{};
    }

    /// Deep-copies all strings into an independently owned definition.
    pub fn clone(self: EntityDef, alloc: Allocator) !OwnedEntityDef {
        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const storage = arena.allocator();
        var value = self;
        if (self.name) |name| value.name = try storage.dupe(u8, name);
        const tags = try storage.alloc([]const u8, self.tags.len);
        for (self.tags, 0..) |tag, i| tags[i] = try storage.dupe(u8, tag);
        value.tags = tags;
        value.owner = switch (self.owner) {
            .none => .none,
            .scene => |name| .{ .scene = try storage.dupe(u8, name) },
        };
        if (self.sprite) |sprite| {
            if (sprite.texture_path) |path| value.sprite.?.texture_path = try storage.dupe(u8, path);
        }
        return .{ .value = value, .arena = arena };
    }
};

/// Owns a snapshot's storage. Pass value to spawn/save and keep this owner alive
/// until all borrowers are finished. Transfer ownership instead of copying it.
pub const OwnedEntityDef = struct {
    value: EntityDef,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *OwnedEntityDef) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Generational handle for safely referencing entities.
pub const EntityHandle = struct {
    index: u32,
    generation: u32,

    pub const invalid = EntityHandle{
        .index = std.math.maxInt(u32),
        .generation = 0,
    };

    pub fn isValid(self: EntityHandle) bool {
        return self.index != std.math.maxInt(u32);
    }

    pub fn eql(self: EntityHandle, other: EntityHandle) bool {
        return self.index == other.index and self.generation == other.generation;
    }
};

test "entity snapshot owns strings independently of its source" {
    var name = "Player".*;
    var tag = "hero".*;
    var scene = "Level1".*;
    var texture = "hero.png".*;
    const tags = [_][]const u8{&tag};
    const entity = Entity{
        .name = &name,
        .tags = &tags,
        .owner = .{ .scene = &scene },
        .body = Body.initDynamic(PhysicsShape.rect(10, 20), Vec2.init(30, 40), .{
            .mass = 2,
            .rotation = 0.5,
            .velocity = Vec2.init(3, 4),
        }),
        .sprite = .{ .color = Color.red, .texture_path = &texture },
    };
    var snapshot = try entity.toDef(std.testing.allocator);
    defer snapshot.deinit();
    name[0] = 'X';
    tag[0] = 'X';
    scene[0] = 'X';
    texture[0] = 'X';
    const def = snapshot.value;
    try std.testing.expectEqualStrings("Player", def.name.?);
    try std.testing.expectEqualStrings("hero", def.tags[0]);
    try std.testing.expectEqualStrings("Level1", def.owner.scene);
    try std.testing.expectEqualStrings("hero.png", def.sprite.?.texture_path.?);
    try std.testing.expectEqualDeep(entity.body.position, def.position);
    try std.testing.expectEqual(entity.body.rotation, def.rotation);
    try std.testing.expectEqualDeep(entity.body.shape, def.body.?.shape);
    try std.testing.expectEqual(entity.body.mass, def.body.?.mass);
    try std.testing.expectEqualDeep(entity.body.velocity, def.body.?.velocity);
    try std.testing.expectEqualDeep(Color.red, def.sprite.?.color);
}

test "user data is typed and runs its own cleanup" {
    const Inventory = struct {
        items: []u8,
        dropped: *u32,

        pub fn deinit(self: *@This(), alloc: Allocator) void {
            alloc.free(self.items);
            self.dropped.* += 1;
        }
    };
    const alloc = std.testing.allocator;
    var dropped: u32 = 0;
    var data: UserData = try .init(alloc, Inventory, .{
        .items = try alloc.dupe(u8, "sword"),
        .dropped = &dropped,
    });
    try std.testing.expectEqualStrings("sword", data.as(Inventory).?.items);
    // Asking for another type never reinterprets the bytes.
    try std.testing.expect(data.as(u32) == null);
    try std.testing.expect(data.as(struct { items: []u8, dropped: *u32 }) == null);
    data.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 1), dropped);
    // Released data reads as absent, and releasing again does nothing.
    try std.testing.expect(data.as(Inventory) == null);
    data.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 1), dropped);

    // Types without a deinit are simply freed.
    var plain: UserData = try .init(alloc, u32, 7);
    try std.testing.expectEqual(@as(u32, 7), plain.as(u32).?.*);
    try std.testing.expect(plain.as(i32) == null);
    plain.deinit(alloc);
}

fn cloneWithAllocationFailures(alloc: Allocator) !void {
    const source = EntityDef{
        .name = "Player",
        .tags = &.{ "hero", "controllable" },
        .owner = .{ .scene = "Level1" },
        .sprite = .{ .texture_path = "assets/hero.png" },
    };
    var owned = try source.clone(alloc);
    defer owned.deinit();
    try std.testing.expectEqualDeep(source, owned.value);
}

test "definition clone cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneWithAllocationFailures, .{});
}

test "empty borrowed definition can be cloned and freed" {
    const source = EntityDef.init();
    var owned = try source.clone(std.testing.allocator);
    defer owned.deinit();
    try std.testing.expectEqualDeep(source, owned.value);
}
