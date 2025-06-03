const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;
const components = @import("components.zig");

/// Unique identifier for entities
pub const Entity = u64;

/// Type-erased component ID
pub const ComponentId = u32;

/// Version number for archetype changes
pub const ComponentVersion = u32;

/// Storage for a specific component type
pub const ComponentStorage = struct {
    /// Raw bytes storage
    data: ArrayList(u8),
    /// Element size in bytes
    element_size: usize,
    /// Type alignment
    alignment: usize,
    /// Number of elements
    count: usize,

    const Self = @This();

    pub fn init(alloc: Allocator, comptime T: type) Self {
        return Self{
            .data = ArrayList(u8).init(alloc),
            .element_size = @sizeOf(T),
            .alignment = @alignOf(T),
            .count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    pub fn push(self: *Self, component: anytype) !usize {
        const bytes = std.mem.asBytes(&component);

        // Ensure we have enough space and resize the items array
        const new_size: usize = (self.count + 1) * self.element_size;
        try self.data.ensureTotalCapacity(new_size);
        try self.data.resize(new_size);

        // Copy the component data
        const start_idx = self.count * self.element_size;
        @memcpy(self.data.items[start_idx .. start_idx + self.element_size], bytes);

        self.count += 1;

        return self.count - 1;
    }

    pub fn get(self: *const Self, comptime T: type, index: usize) *T {
        std.debug.assert(index < self.count);
        const start_idx = index * self.element_size;
        const slice = self.data.items[start_idx .. start_idx + self.element_size];
        return @as(*T, @ptrCast(@alignCast(slice.ptr)));
    }

    pub fn removeSwapLast(self: *Self, index: usize) void {
        if (index >= self.count) return;

        if (index < self.count - 1) {
            const last_start = (self.count - 1) * self.element_size;
            const target_start = index * self.element_size;

            @memcpy(self.data.items[target_start .. target_start + self.element_size], self.data.items[last_start .. last_start + self.element_size]);
        }

        self.count -= 1;
        self.data.resize(self.count * self.element_size) catch {};
    }
};

/// An archetype represents a unique combination of component types
pub const Archetype = struct {
    /// Component types in this archetype (sorted)
    component_ids: []ComponentId,
    /// Storage for each component type
    storages: AutoHashMap(ComponentId, ComponentStorage),
    /// Maps entity ID to index in storage arrays (shared across all components in this archetype)
    entity_to_index: AutoHashMap(Entity, usize),
    /// Maps index to entity ID
    index_to_entity: ArrayList(Entity),

    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator, component_ids: []const ComponentId) !Self {
        const sorted_ids = try alloc.dupe(ComponentId, component_ids);
        std.mem.sort(ComponentId, sorted_ids, {}, std.sort.asc(ComponentId));

        return Self{
            .component_ids = sorted_ids,
            .storages = AutoHashMap(ComponentId, ComponentStorage).init(alloc),
            .entity_to_index = AutoHashMap(Entity, usize).init(alloc),
            .index_to_entity = ArrayList(Entity).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.component_ids);

        var storage_iter = self.storages.valueIterator();
        while (storage_iter.next()) |storage| {
            storage.deinit();
        }
        self.storages.deinit();
        self.entity_to_index.deinit();
        self.index_to_entity.deinit();
    }

    pub fn addComponent(self: *Self, entity: Entity, component_id: ComponentId, component: anytype) !void {
        // Get or create entity index (shared across all components in this archetype)
        var entity_index: usize = undefined;

        if (self.entity_to_index.get(entity)) |existing_index| {
            // Entity already exists in this archetype
            entity_index = existing_index;
        } else {
            // New entity - assign the next available index
            entity_index = self.index_to_entity.items.len;
            try self.entity_to_index.put(entity, entity_index);
            try self.index_to_entity.append(entity);
        }

        // Ensure storage exists for this component type
        if (!self.storages.contains(component_id)) {
            const T = @TypeOf(component);
            try self.storages.put(component_id, ComponentStorage.init(self.alloc, T));
        }

        // Get storage and ensure it has enough capacity for this entity index
        var storage = self.storages.getPtr(component_id).?;

        // Ensure storage has enough capacity for this entity index
        const required_size = (entity_index + 1) * storage.element_size;
        try storage.data.ensureTotalCapacity(required_size);

        // Resize if needed
        if (storage.count <= entity_index) {
            try storage.data.resize(required_size);
            storage.count = entity_index + 1;
        }

        // Set the component at the correct index
        const bytes = std.mem.asBytes(&component);
        const start_idx = entity_index * storage.element_size;
        @memcpy(storage.data.items[start_idx .. start_idx + storage.element_size], bytes);
    }

    pub fn getComponent(self: *const Self, comptime T: type, entity: Entity, component_id: ComponentId) ?*T {
        const index = self.entity_to_index.get(entity) orelse return null;
        const storage = self.storages.get(component_id) orelse return null;
        if (index >= storage.count) return null;
        return storage.get(T, index);
    }

    pub fn removeEntity(self: *Self, entity: Entity) void {
        const index = self.entity_to_index.get(entity) orelse return;
        const last_index = self.index_to_entity.items.len - 1;

        if (index < last_index) {
            const last_entity = self.index_to_entity.items[last_index];
            self.index_to_entity.items[index] = last_entity;
            self.entity_to_index.put(last_entity, index) catch {};
        }

        _ = self.index_to_entity.pop();
        _ = self.entity_to_index.remove(entity);

        // Remove from all storages
        var storage_iter = self.storages.valueIterator();
        while (storage_iter.next()) |storage| {
            storage.removeSwapLast(index);
        }
    }

    pub fn hasComponents(self: *const Self, component_ids: []const ComponentId) bool {
        for (component_ids) |id| {
            if (!self.storages.contains(id)) return false;
        }
        return true;
    }
};

/// Query for entities with specific components
pub const Query = struct {
    /// Required component types
    with: []const ComponentId,
    /// Excluded component types
    without: []const ComponentId,

    pub fn init(with: []const ComponentId, without: []const ComponentId) Query {
        return Query{
            .with = with,
            .without = without,
        };
    }

    pub fn matches(self: *const Query, archetype: *const Archetype) bool {
        // Check if archetype has all required components
        for (self.with) |id| {
            if (!archetype.storages.contains(id)) return false;
        }

        // Check if archetype doesn't have any excluded components
        for (self.without) |id| {
            if (archetype.storages.contains(id)) return false;
        }

        return true;
    }
};

/// Iterator for query results
pub const QueryIterator = struct {
    world: *const World,
    query: Query,
    archetype_index: usize,
    entity_index: usize,

    pub fn next(self: *QueryIterator) ?Entity {
        while (self.archetype_index < self.world.archetypes.items.len) {
            const archetype = &self.world.archetypes.items[self.archetype_index];

            if (self.query.matches(archetype)) {
                if (self.entity_index < archetype.index_to_entity.items.len) {
                    const entity = archetype.index_to_entity.items[self.entity_index];
                    self.entity_index += 1;
                    return entity;
                }
            }

            self.archetype_index += 1;
            self.entity_index = 0;
        }

        return null;
    }
};

/// Main ECS World
pub const World = struct {
    alloc: Allocator,
    /// All archetypes in the world
    archetypes: ArrayList(Archetype),
    /// Next available entity ID
    next_entity_id: Entity,
    /// Maps entity to archetype index
    entity_to_archetype: AutoHashMap(Entity, usize),

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
            .archetypes = ArrayList(Archetype).init(alloc),
            .next_entity_id = 1, // 0 is reserved for null entity
            .entity_to_archetype = AutoHashMap(Entity, usize).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.archetypes.items) |*archetype| {
            archetype.deinit();
        }
        self.archetypes.deinit();
        self.entity_to_archetype.deinit();
    }

    /// Register a component type - now just validates the component is known at compile time
    pub fn registerComponent(self: *Self, comptime T: type) !ComponentId {
        // Get compile-time component ID
        const component_type = components.ComponentType.getId(T);
        const id = component_type.toU32();

        _ = self; // Mark self as unused since we don't need it
        return id;
    }

    /// Get component ID for a type - now always succeeds at compile time
    pub fn getComponentId(self: *const Self, comptime T: type) ?ComponentId {
        _ = self; // Mark self as unused
        const component_type = components.ComponentType.getId(T);
        return component_type.toU32();
    }

    /// Spawn a new entity
    pub fn spawnEntity(self: *Self) Entity {
        const entity = self.next_entity_id;
        self.next_entity_id += 1;
        return entity;
    }

    /// Add a component to an entity
    pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
        const T = @TypeOf(component);
        const component_id = try self.registerComponent(T);

        // Find or create archetype for this entity
        var new_components = ArrayList(ComponentId).init(self.alloc);
        defer new_components.deinit();

        try new_components.append(component_id);

        // If entity already exists, copy existing components and move to new archetype
        if (self.entity_to_archetype.get(entity)) |current_archetype_idx| {
            // IMPORTANT: Don't hold pointers to archetype data while the ArrayList might be reallocated!
            // First, collect all the component data we need
            var existing_component_ids = ArrayList(ComponentId).init(self.alloc);
            defer existing_component_ids.deinit();

            // Copy the component IDs (not pointers to them!)
            {
                const source_archetype = &self.archetypes.items[current_archetype_idx];

                for (source_archetype.component_ids) |existing_id| {
                    if (existing_id != component_id) {
                        try new_components.append(existing_id);
                        try existing_component_ids.append(existing_id);
                    }
                }
            }

            // Find or create the new archetype (this might reallocate the ArrayList!)
            const new_archetype_idx = try self.findOrCreateArchetype(new_components.items);

            // Now it's safe to get pointers again (after potential reallocation)
            const current_archetype = &self.archetypes.items[current_archetype_idx];
            var new_archetype = &self.archetypes.items[new_archetype_idx];

            // Copy all existing components to the new archetype
            for (existing_component_ids.items) |existing_id| {
                // Get the component data from the old archetype
                const old_storage = current_archetype.storages.get(existing_id).?;
                const entity_index = current_archetype.entity_to_index.get(entity).?;

                // Copy the raw component data
                const start_idx = entity_index * old_storage.element_size;
                const component_bytes = old_storage.data.items[start_idx .. start_idx + old_storage.element_size];

                // Create storage in new archetype if needed
                if (!new_archetype.storages.contains(existing_id)) {
                    // We need to create storage with the right type, but we don't know the type here
                    // This is a limitation of the current design - we need type information
                    // For now, create a generic storage with the same element size
                    const new_storage = ComponentStorage{
                        .data = ArrayList(u8).init(self.alloc),
                        .element_size = old_storage.element_size,
                        .alignment = old_storage.alignment,
                        .count = 0,
                    };
                    try new_archetype.storages.put(existing_id, new_storage);
                }

                // Get or create entity index in new archetype
                const new_entity_index: usize = if (new_archetype.entity_to_index.get(entity)) |existing_index|
                    existing_index
                else blk: {
                    const idx = new_archetype.index_to_entity.items.len;
                    try new_archetype.entity_to_index.put(entity, idx);
                    try new_archetype.index_to_entity.append(entity);
                    break :blk idx;
                };

                // Copy component data to new archetype
                var new_storage = new_archetype.storages.getPtr(existing_id).?;
                const required_size = (new_entity_index + 1) * new_storage.element_size;
                try new_storage.data.ensureTotalCapacity(required_size);

                if (new_storage.count <= new_entity_index) {
                    try new_storage.data.resize(required_size);
                    new_storage.count = new_entity_index + 1;
                }

                const new_start_idx = new_entity_index * new_storage.element_size;
                @memcpy(new_storage.data.items[new_start_idx .. new_start_idx + new_storage.element_size], component_bytes);
            }

            // Add the new component to the new archetype
            try new_archetype.addComponent(entity, component_id, component);

            // Remove entity from old archetype
            current_archetype.removeEntity(entity);

            // Update entity mapping
            try self.entity_to_archetype.put(entity, new_archetype_idx);
        } else {
            // Entity doesn't exist yet, create in new archetype
            const archetype_idx = try self.findOrCreateArchetype(new_components.items);
            var archetype = &self.archetypes.items[archetype_idx];

            try archetype.addComponent(entity, component_id, component);
            try self.entity_to_archetype.put(entity, archetype_idx);
        }
    }

    /// Get a component from an entity
    pub fn getComponent(self: *const Self, comptime T: type, entity: Entity) ?*T {
        const component_id = self.getComponentId(T) orelse return null;
        const archetype_idx = self.entity_to_archetype.get(entity) orelse return null;
        const archetype = &self.archetypes.items[archetype_idx];
        return archetype.getComponent(T, entity, component_id);
    }

    /// Remove a component from an entity
    pub fn removeComponent(self: *Self, comptime T: type, entity: Entity) !void {
        const component_id = self.getComponentId(T) orelse return;
        const archetype_idx = self.entity_to_archetype.get(entity) orelse return;

        // Create new archetype without this component
        var new_components = ArrayList(ComponentId).init(self.alloc);
        defer new_components.deinit();

        const current_archetype = &self.archetypes.items[archetype_idx];
        for (current_archetype.component_ids) |existing_id| {
            if (existing_id != component_id) {
                try new_components.append(existing_id);
            }
        }

        if (new_components.items.len == 0) {
            // Entity has no components, remove entirely
            current_archetype.removeEntity(entity);
            _ = self.entity_to_archetype.remove(entity);
        } else {
            // Move to new archetype
            const new_archetype_idx = try self.findOrCreateArchetype(new_components.items);
            // TODO: Copy other components to new archetype
            current_archetype.removeEntity(entity);
            try self.entity_to_archetype.put(entity, new_archetype_idx);
        }
    }

    /// Despawn an entity and all its components
    pub fn despawnEntity(self: *Self, entity: Entity) void {
        const archetype_idx = self.entity_to_archetype.get(entity) orelse return;
        var archetype = &self.archetypes.items[archetype_idx];
        archetype.removeEntity(entity);
        _ = self.entity_to_archetype.remove(entity);
    }

    /// Query entities with specific components
    pub fn query(self: *const Self, with: []const ComponentId, without: []const ComponentId) QueryIterator {
        return QueryIterator{
            .world = self,
            .query = Query.init(with, without),
            .archetype_index = 0,
            .entity_index = 0,
        };
    }

    /// Find or create an archetype with the given component types
    fn findOrCreateArchetype(self: *Self, component_ids: []const ComponentId) !usize {
        // Sort for comparison
        const sorted_ids = try self.alloc.dupe(ComponentId, component_ids);
        defer self.alloc.free(sorted_ids);
        std.mem.sort(ComponentId, sorted_ids, {}, std.sort.asc(ComponentId));

        // Look for existing archetype
        for (self.archetypes.items, 0..) |*archetype, i| {
            if (std.mem.eql(ComponentId, archetype.component_ids, sorted_ids)) {
                return i;
            }
        }

        // Create new archetype
        const new_archetype = try Archetype.init(self.alloc, sorted_ids);
        try self.archetypes.append(new_archetype);
        return self.archetypes.items.len - 1;
    }
};

/// Helper macro for creating component queries
pub fn With(comptime T: type) type {
    return struct {
        pub const component_type = T;
    };
}

pub fn Without(comptime T: type) type {
    return struct {
        pub const component_type = T;
    };
}
