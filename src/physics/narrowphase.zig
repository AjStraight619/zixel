const std = @import("std");
const rl = @import("raylib");
const Body = @import("body.zig").Body;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;
const Vector2 = rl.Vector2;

/// Contact information for collision response
pub const ContactManifold = struct {
    point: Vector2, // Contact point in world space
    normal: Vector2, // Collision normal (pointing from body1 to body2)
    penetration: f32, // How deep the overlap is
    body1_id: usize, // First body involved
    body2_id: usize, // Second body involved

    pub fn init(point: Vector2, normal: Vector2, penetration: f32, id1: usize, id2: usize) ContactManifold {
        return ContactManifold{
            .point = point,
            .normal = normal,
            .penetration = penetration,
            .body1_id = id1,
            .body2_id = id2,
        };
    }
};

/// Narrow phase collision detection - precise collision testing between specific shape pairs
pub const NarrowPhase = struct {
    /// Projection result for SAT algorithm
    const Projection = struct {
        min: f32,
        max: f32,
    };

    /// Get perpendicular vector (rotate 90 degrees)
    fn perpendicular(v: Vector2) Vector2 {
        return Vector2{ .x = -v.y, .y = v.x };
    }

    /// Get the four corners of a rotated rectangle
    fn getRectangleCorners(rect: rl.Rectangle, center: Vector2, rotation: f32) [4]Vector2 {
        const half_width = rect.width / 2.0;
        const half_height = rect.height / 2.0;
        const cos_rot = @cos(rotation);
        const sin_rot = @sin(rotation);

        // Local corners (relative to center)
        const local_corners = [4]Vector2{
            Vector2{ .x = -half_width, .y = -half_height }, // Top-left
            Vector2{ .x = half_width, .y = -half_height }, // Top-right
            Vector2{ .x = half_width, .y = half_height }, // Bottom-right
            Vector2{ .x = -half_width, .y = half_height }, // Bottom-left
        };

        var world_corners: [4]Vector2 = undefined;
        for (local_corners, 0..) |local, i| {
            // Rotate and translate to world space
            world_corners[i] = Vector2{
                .x = center.x + (local.x * cos_rot - local.y * sin_rot),
                .y = center.y + (local.x * sin_rot + local.y * cos_rot),
            };
        }

        return world_corners;
    }

    /// Project a polygon onto an axis and return min/max projection values
    fn projectPolygon(corners: []const Vector2, axis: Vector2) Projection {
        var min_proj = corners[0].dotProduct(axis);
        var max_proj = min_proj;

        for (corners[1..]) |corner| {
            const proj = corner.dotProduct(axis);
            min_proj = @min(min_proj, proj);
            max_proj = @max(max_proj, proj);
        }

        return Projection{ .min = min_proj, .max = max_proj };
    }

    // Project a circle onto an axis
    fn projectCircle(center: Vector2, radius: f32, axis: Vector2) Projection {
        const center_proj = center.dotProduct(axis);
        return Projection{ .min = center_proj - radius, .max = center_proj + radius };
    }

    /// Check if two projection ranges overlap and return overlap amount
    fn getOverlap(proj1: Projection, proj2: Projection) ?f32 {
        const overlap = @min(proj1.max, proj2.max) - @max(proj1.min, proj2.min);
        return if (overlap > 0.0) overlap else null;
    }

    /// SAT collision detection for two rectangles
    fn satRectangleRectangle(rect1: PhysicsShape, pos1: Vector2, rot1: f32, rect2: PhysicsShape, pos2: Vector2, rot2: f32, id1: usize, id2: usize) ?ContactManifold {
        const corners1 = getRectangleCorners(rect1.rectangle, pos1, rot1);
        const corners2 = getRectangleCorners(rect2.rectangle, pos2, rot2);

        var min_overlap: f32 = std.math.inf(f32);
        var separation_axis: Vector2 = undefined;
        var separating = false;

        // Test axes from rectangle 1 (2 unique axes)
        for (0..2) |i| {
            const edge = corners1[(i + 1) % 4].subtract(corners1[i]);
            const axis = perpendicular(edge).normalize();

            const proj1 = projectPolygon(&corners1, axis);
            const proj2 = projectPolygon(&corners2, axis);

            if (getOverlap(proj1, proj2)) |overlap| {
                if (overlap < min_overlap) {
                    min_overlap = overlap;
                    separation_axis = axis;
                }
            } else {
                separating = true;
                break;
            }
        }

        if (separating) return null;

        // Test axes from rectangle 2 (2 unique axes)
        for (0..2) |i| {
            const edge = corners2[(i + 1) % 4].subtract(corners2[i]);
            const axis = perpendicular(edge).normalize();

            const proj1 = projectPolygon(&corners1, axis);
            const proj2 = projectPolygon(&corners2, axis);

            if (getOverlap(proj1, proj2)) |overlap| {
                if (overlap < min_overlap) {
                    min_overlap = overlap;
                    separation_axis = axis;
                }
            } else {
                return null;
            }
        }

        // Ensure normal points from rect1 to rect2
        const center_diff = pos2.subtract(pos1);
        if (separation_axis.dotProduct(center_diff) < 0.0) {
            separation_axis = separation_axis.negate();
        }

        // Calculate contact point (approximate as midpoint between centers)
        const contact_point = Vector2{
            .x = (pos1.x + pos2.x) / 2.0,
            .y = (pos1.y + pos2.y) / 2.0,
        };

        return ContactManifold.init(contact_point, separation_axis, min_overlap, id1, id2);
    }

    /// SAT collision detection for circle vs rotated rectangle
    fn satCircleRectangle(circle: PhysicsShape, circle_pos: Vector2, rect: PhysicsShape, rect_pos: Vector2, rect_rot: f32, id1: usize, id2: usize) ?ContactManifold {
        const corners = getRectangleCorners(rect.rectangle, rect_pos, rect_rot);
        const radius = circle.circle.radius;

        var min_overlap: f32 = std.math.inf(f32);
        var separation_axis: Vector2 = undefined;

        // Test rectangle edge normals
        for (0..4) |i| {
            const edge = corners[(i + 1) % 4].subtract(corners[i]);
            const axis = perpendicular(edge).normalize();

            const rect_proj = projectPolygon(&corners, axis);
            const circle_proj = projectCircle(circle_pos, radius, axis);

            if (getOverlap(rect_proj, circle_proj)) |overlap| {
                if (overlap < min_overlap) {
                    min_overlap = overlap;
                    separation_axis = axis;
                }
            } else {
                return null;
            }
        }

        // Test axis from circle center to closest point on rectangle
        var closest_point = corners[0];
        var min_dist_sq: f32 = std.math.inf(f32);

        // Check distance to each corner
        for (corners) |corner| {
            const dist_sq = corner.distanceSqr(circle_pos);
            if (dist_sq < min_dist_sq) {
                min_dist_sq = dist_sq;
                closest_point = corner;
            }
        }

        // Check distance to each edge
        for (0..4) |i| {
            const edge_start = corners[i];
            const edge_end = corners[(i + 1) % 4];
            const edge_vec = edge_end.subtract(edge_start);
            const to_circle = circle_pos.subtract(edge_start);

            const edge_length_sq = edge_vec.lengthSqr();
            if (edge_length_sq > 0.0) {
                const t = @max(0.0, @min(1.0, to_circle.dotProduct(edge_vec) / edge_length_sq));
                const point_on_edge = edge_start.add(edge_vec.scale(t));

                const dist_sq = point_on_edge.distanceSqr(circle_pos);
                if (dist_sq < min_dist_sq) {
                    min_dist_sq = dist_sq;
                    closest_point = point_on_edge;
                }
            }
        }

        // Test axis from circle center to closest point
        const to_closest = closest_point.subtract(circle_pos);
        if (to_closest.x != 0.0 or to_closest.y != 0.0) {
            const axis = to_closest.normalize();

            const rect_proj = projectPolygon(&corners, axis);
            const circle_proj = projectCircle(circle_pos, radius, axis);

            if (getOverlap(rect_proj, circle_proj)) |overlap| {
                if (overlap < min_overlap) {
                    min_overlap = overlap;
                    separation_axis = axis;
                }
            } else {
                return null;
            }
        }

        // Ensure normal points from circle to rectangle
        const center_diff = rect_pos.subtract(circle_pos);
        if (separation_axis.dotProduct(center_diff) < 0.0) {
            separation_axis = separation_axis.negate();
        }

        return ContactManifold.init(closest_point, separation_axis, min_overlap, id1, id2);
    }

    /// Check collision between two bodies and return contact manifold if colliding
    pub fn checkBodiesCollision(body1: *const Body, body2: *const Body) ?ContactManifold {
        // Use the shape-specific collision detection
        return checkShapesCollision(body1.getShape(), body1.getPosition(), body1.getRotation(), body1.id, body2.getShape(), body2.getPosition(), body2.getRotation(), body2.id);
    }

    /// Check collision between two shapes with positions and rotations
    pub fn checkShapesCollision(shape1: PhysicsShape, pos1: Vector2, rot1: f32, id1: usize, shape2: PhysicsShape, pos2: Vector2, rot2: f32, id2: usize) ?ContactManifold {
        switch (shape1) {
            .circle => {
                switch (shape2) {
                    .circle => {
                        return checkCircleCircle(shape1, pos1, shape2, pos2, id1, id2);
                    },
                    .rectangle => {
                        return checkCircleRectangle(shape1, pos1, shape2, pos2, rot2, id1, id2);
                    },
                }
            },
            .rectangle => {
                switch (shape2) {
                    .circle => {
                        // Flip the result for circle-rectangle collision
                        if (checkCircleRectangle(shape2, pos2, shape1, pos1, rot1, id2, id1)) |manifold| {
                            return ContactManifold.init(manifold.point, Vector2{ .x = -manifold.normal.x, .y = -manifold.normal.y }, // Flip normal
                                manifold.penetration, id1, id2 // Keep original IDs
                            );
                        }
                        return null;
                    },
                    .rectangle => {
                        return checkRectangleRectangle(shape1, pos1, rot1, shape2, pos2, rot2, id1, id2);
                    },
                }
            },
        }
    }

    /// Circle vs Circle collision using Raylib - optimized
    fn checkCircleCircle(circle1: PhysicsShape, pos1: Vector2, circle2: PhysicsShape, pos2: Vector2, id1: usize, id2: usize) ?ContactManifold {
        const c1 = circle1.circle;
        const c2 = circle2.circle;

        // Use raylib for fast collision check
        if (rl.checkCollisionCircles(pos1, c1.radius, pos2, c2.radius)) {
            // Calculate collision details manually (raylib doesn't provide getCollisionCircles)
            const dx = pos2.x - pos1.x;
            const dy = pos2.y - pos1.y;
            const distance = @sqrt(dx * dx + dy * dy);

            if (distance == 0.0) {
                // Circles are exactly on top of each other - rare edge case
                return ContactManifold.init(pos1, Vector2{ .x = 1.0, .y = 0.0 }, // Arbitrary separation direction
                    c1.radius + c2.radius, id1, id2);
            }

            const normal = Vector2{ .x = dx / distance, .y = dy / distance };
            const penetration = (c1.radius + c2.radius) - distance;
            const contact_point = Vector2{
                .x = pos1.x + normal.x * c1.radius,
                .y = pos1.y + normal.y * c1.radius,
            };

            return ContactManifold.init(contact_point, normal, penetration, id1, id2);
        }
        return null;
    }

    /// Circle vs Rectangle collision using SAT - consistent for all rectangles
    fn checkCircleRectangle(circle: PhysicsShape, circle_pos: Vector2, rect: PhysicsShape, rect_pos: Vector2, rect_rot: f32, id1: usize, id2: usize) ?ContactManifold {
        // Always use SAT for consistent behavior
        return satCircleRectangle(circle, circle_pos, rect, rect_pos, rect_rot, id1, id2);
    }

    /// Rectangle vs Rectangle collision using raylib - fully optimized
    fn checkRectangleRectangle(rect1: PhysicsShape, pos1: Vector2, rot1: f32, rect2: PhysicsShape, pos2: Vector2, rot2: f32, id1: usize, id2: usize) ?ContactManifold {
        // For axis-aligned rectangles, use Raylib functions fully
        if (rot1 == 0.0 and rot2 == 0.0) {
            const r1 = rect1.rectangle;
            const r2 = rect2.rectangle;

            const rect1_raylib = rl.Rectangle{
                .x = pos1.x - r1.width / 2.0,
                .y = pos1.y - r1.height / 2.0,
                .width = r1.width,
                .height = r1.height,
            };
            const rect2_raylib = rl.Rectangle{
                .x = pos2.x - r2.width / 2.0,
                .y = pos2.y - r2.height / 2.0,
                .width = r2.width,
                .height = r2.height,
            };

            // Use raylib for collision check
            if (rl.checkCollisionRecs(rect1_raylib, rect2_raylib)) {
                // Use raylib to get the actual overlap rectangle!
                const overlap = rl.getCollisionRec(rect1_raylib, rect2_raylib);

                // Calculate separation direction based on overlap dimensions
                const center1 = Vector2{ .x = rect1_raylib.x + rect1_raylib.width / 2.0, .y = rect1_raylib.y + rect1_raylib.height / 2.0 };
                const center2 = Vector2{ .x = rect2_raylib.x + rect2_raylib.width / 2.0, .y = rect2_raylib.y + rect2_raylib.height / 2.0 };

                // Determine separation direction based on which axis has smaller overlap
                const normal: Vector2 = if (overlap.width < overlap.height) blk: {
                    // Separate horizontally
                    if (center1.x < center2.x) {
                        break :blk Vector2{ .x = -1.0, .y = 0.0 };
                    } else {
                        break :blk Vector2{ .x = 1.0, .y = 0.0 };
                    }
                } else blk: {
                    // Separate vertically
                    if (center1.y < center2.y) {
                        break :blk Vector2{ .x = 0.0, .y = -1.0 };
                    } else {
                        break :blk Vector2{ .x = 0.0, .y = 1.0 };
                    }
                };

                // Contact point is center of overlap
                const contact_point = Vector2{
                    .x = overlap.x + overlap.width / 2.0,
                    .y = overlap.y + overlap.height / 2.0,
                };

                // Penetration is the smaller overlap dimension
                const penetration = @min(overlap.width, overlap.height);

                return ContactManifold.init(contact_point, normal, penetration, id1, id2);
            }
        } else {
            // Use SAT for rotated rectangle vs rectangle collision
            return satRectangleRectangle(rect1, pos1, rot1, rect2, pos2, rot2, id1, id2);
        }

        return null;
    }
};
