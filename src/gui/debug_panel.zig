const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const ECSEngine = @import("../ecs/engine.zig").ECSEngine;
const components = @import("../ecs/components.zig");

pub const DebugPanel = struct {
    show_colliders: bool = false,
    show_velocities: bool = false,
    show_entity_ids: bool = false,
    show_ecs_info: bool = true,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn render(self: *Self, engine: *ECSEngine, content_rect: rl.Rectangle) void {
        var y_offset: f32 = 10;
        const item_height: f32 = 25;
        const margin: f32 = 10;

        // Colliders Debug Toggle
        const colliders_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 150,
            .height = item_height,
        };
        _ = rlg.checkBox(colliders_rect, "Show Colliders", &self.show_colliders);
        y_offset += item_height + 5;

        // Velocities Debug Toggle
        const velocities_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 150,
            .height = item_height,
        };
        _ = rlg.checkBox(velocities_rect, "Show Velocities", &self.show_velocities);
        y_offset += item_height + 5;

        // Entity IDs Debug Toggle
        const ids_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 150,
            .height = item_height,
        };
        _ = rlg.checkBox(ids_rect, "Show Entity IDs", &self.show_entity_ids);
        y_offset += item_height + 10;

        // ECS Info Toggle
        const info_rect = rl.Rectangle{
            .x = content_rect.x + margin,
            .y = content_rect.y + y_offset,
            .width = 150,
            .height = item_height,
        };
        _ = rlg.checkBox(info_rect, "Show ECS Info", &self.show_ecs_info);
        y_offset += item_height + 10;

        // ECS Info Display
        if (self.show_ecs_info) {
            // Count entities by type
            var player_count: u32 = 0;
            var enemy_count: u32 = 0;
            var total_entities: u32 = 0;

            const world = engine.getWorld();
            const tag_id = world.getComponentId(components.Tag);

            if (tag_id) |tid| {
                var query_iter = world.query(&[_]@TypeOf(tid){tid}, &[_]@TypeOf(tid){});
                while (query_iter.next()) |entity| {
                    total_entities += 1;
                    if (world.getComponent(components.Tag, entity)) |tag| {
                        if (tag.has(.Player)) player_count += 1;
                        if (tag.has(.Enemy)) enemy_count += 1;
                    }
                }
            }

            const info_text = std.fmt.allocPrintZ(std.heap.page_allocator, "Total Entities: {d}\nPlayers: {d}\nEnemies: {d}\nArchetypes: {d}", .{ total_entities, player_count, enemy_count, world.archetypes.items.len }) catch "Error displaying info";
            defer std.heap.page_allocator.free(info_text);

            const text_rect = rl.Rectangle{
                .x = content_rect.x + margin,
                .y = content_rect.y + y_offset,
                .width = content_rect.width - 2 * margin,
                .height = 60,
            };
            _ = rlg.label(text_rect, @ptrCast(info_text));
        }
    }
};
