const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// pub fn SlotMap(comptime T: type, comptime Handle: type) type {
//     return struct {
//         const Self = @This();

//         pub const Slot = struct {
//             dense_idx: u32,
//             generation: u32,
//         };

//         dense_data: []T,
//         reverse_map: []u32,
//         slots: []Slot,

//         capacity: u32,
//         count: u32,
//         free_head: ?u32,
//     };
// }
