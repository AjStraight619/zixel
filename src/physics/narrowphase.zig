const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Rectangle = @import("../math/shapes.zig").Rectangle;

/// Contact information for collision response
pub const ContactManifold = struct {
    point: Vec2, // Contact point in world space
    normal: Vec2, // Collision normal (pointing from body1 to body2)
    penetration: f32, // How deep the overlap is

    pub fn init(point: Vec2, normal: Vec2, penetration: f32) ContactManifold {
        return .{
            .point = point,
            .normal = normal,
            .penetration = penetration,
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

    /// Get the four corners of a rotated rectangle
    fn getRectangleCorners(rect: Rectangle, center: Vec2, rotation: f32) [4]Vec2 {
        const half_width = rect.width / 2.0;
        const half_height = rect.height / 2.0;
        const cos_rot = @cos(rotation);
        const sin_rot = @sin(rotation);

        // Local corners (relative to center)
        const local_corners = [4]Vec2{
            Vec2.init(-half_width, -half_height), // Top-left
            Vec2.init(half_width, -half_height), // Top-right
            Vec2.init(half_width, half_height), // Bottom-right
            Vec2.init(-half_width, half_height), // Bottom-left
        };

        var world_corners: [4]Vec2 = undefined;
        for (local_corners, 0..) |local, i| {
            // Rotate and translate to world space
            world_corners[i] = Vec2{
                .x = center.x + (local.x * cos_rot - local.y * sin_rot),
                .y = center.y + (local.x * sin_rot + local.y * cos_rot),
            };
        }

        return world_corners;
    }

    /// Project a polygon onto an axis and return min/max projection values
    fn projectPolygon(corners: []const Vec2, axis: Vec2) Projection {
        var min_proj = corners[0].dot(axis);
        var max_proj = min_proj;

        for (corners[1..]) |corner| {
            const proj = corner.dot(axis);
            min_proj = @min(min_proj, proj);
            max_proj = @max(max_proj, proj);
        }

        return .{ .min = min_proj, .max = max_proj };
    }

    // Project a circle onto an axis
    fn projectCircle(center: Vec2, radius: f32, axis: Vec2) Projection {
        const center_proj = center.dot(axis);
        return .{ .min = center_proj - radius, .max = center_proj + radius };
    }

    /// Check if two projection ranges overlap and return overlap amount
    fn getOverlap(proj1: Projection, proj2: Projection) ?f32 {
        const overlap = @min(proj1.max, proj2.max) - @max(proj1.min, proj2.min);
        return if (overlap > 0.0) overlap else null;
    }

    /// Separating Axis Theorem (SAT) collision detection for two rectangles
    fn satRectangleRectangle(rect1: PhysicsShape, pos1: Vec2, rot1: f32, rect2: PhysicsShape, pos2: Vec2, rot2: f32) ?ContactManifold {
        const corners1 = getRectangleCorners(rect1.rectangle, pos1, rot1);
        const corners2 = getRectangleCorners(rect2.rectangle, pos2, rot2);

        var min_overlap: f32 = std.math.inf(f32);
        var separation_axis: Vec2 = undefined;
        var separating = false;

        // Test axes from rectangle 1 (2 unique axes)
        for (0..2) |i| {
            const edge = corners1[(i + 1) % 4].sub(corners1[i]);
            const axis = edge.perpendicular().normalize();

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
            const edge = corners2[(i + 1) % 4].sub(corners2[i]);
            const axis = edge.perpendicular().normalize();

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
        const center_diff = pos2.sub(pos1);
        if (separation_axis.dot(center_diff) < 0.0) {
            separation_axis = separation_axis.negate();
        }

        // Calculate contact point (approximate as midpoint between centers)
        const contact_point = Vec2{
            .x = (pos1.x + pos2.x) / 2.0,
            .y = (pos1.y + pos2.y) / 2.0,
        };

        return ContactManifold.init(contact_point, separation_axis, min_overlap);
    }

    /// Separating Axis Theorem (SAT) collision detection for circle vs rotated rectangle
    fn satCircleRectangle(circle: PhysicsShape, circle_pos: Vec2, rect: PhysicsShape, rect_pos: Vec2, rect_rot: f32) ?ContactManifold {
        const corners = getRectangleCorners(rect.rectangle, rect_pos, rect_rot);
        const radius = circle.circle.radius;

        var min_overlap: f32 = std.math.inf(f32);
        var separation_axis: Vec2 = undefined;

        // Test rectangle edge normals
        for (0..4) |i| {
            const edge = corners[(i + 1) % 4].sub(corners[i]);
            const axis = edge.perpendicular().normalize();

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
            const edge_vec = edge_end.sub(edge_start);
            const to_circle = circle_pos.sub(edge_start);

            const edge_length_sq = edge_vec.lengthSqr();
            if (edge_length_sq > 0.0) {
                const t = std.math.clamp(to_circle.dot(edge_vec) / edge_length_sq, 0.0, 1.0);
                const point_on_edge = edge_start.add(edge_vec.scale(t));

                const dist_sq = point_on_edge.distanceSqr(circle_pos);
                if (dist_sq < min_dist_sq) {
                    min_dist_sq = dist_sq;
                    closest_point = point_on_edge;
                }
            }
        }

        // Test axis from circle center to closest point
        const to_closest = closest_point.sub(circle_pos);
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
        const center_diff = rect_pos.sub(circle_pos);
        if (separation_axis.dot(center_diff) < 0.0) {
            separation_axis = separation_axis.negate();
        }

        return ContactManifold.init(closest_point, separation_axis, min_overlap);
    }

    /// Check collision between two bodies and return contact manifold if colliding
    pub fn checkBodiesCollision(body1: *const Body, body2: *const Body) ?ContactManifold {
        return checkShapesCollision(
            body1.shape,
            body1.position,
            body1.rotation,
            body2.shape,
            body2.position,
            body2.rotation,
        );
    }

    /// Check collision between two shapes with positions and rotations
    pub fn checkShapesCollision(shape1: PhysicsShape, pos1: Vec2, rot1: f32, shape2: PhysicsShape, pos2: Vec2, rot2: f32) ?ContactManifold {
        switch (shape1) {
            .circle => {
                switch (shape2) {
                    .circle => {
                        return checkCircleCircle(shape1, pos1, shape2, pos2);
                    },
                    .rectangle => {
                        return checkCircleRectangle(shape1, pos1, shape2, pos2, rot2);
                    },
                }
            },
            .rectangle => {
                switch (shape2) {
                    .circle => {
                        // Flip the result for circle-rectangle collision
                        if (checkCircleRectangle(shape2, pos2, shape1, pos1, rot1)) |manifold| {
                            return ContactManifold.init(
                                manifold.point,
                                manifold.normal.negate(), // Flip normal
                                manifold.penetration,
                            );
                        }
                        return null;
                    },
                    .rectangle => {
                        return checkRectangleRectangle(shape1, pos1, rot1, shape2, pos2, rot2);
                    },
                }
            },
        }
    }

    /// Circle vs Circle collision
    fn checkCircleCircle(circle1: PhysicsShape, pos1: Vec2, circle2: PhysicsShape, pos2: Vec2) ?ContactManifold {
        const c1 = circle1.circle;
        const c2 = circle2.circle;

        const dx = pos2.x - pos1.x;
        const dy = pos2.y - pos1.y;
        const distance_sq = dx * dx + dy * dy;
        const radius_sum = c1.radius + c2.radius;

        if (distance_sq >= radius_sum * radius_sum) {
            return null; // No collision
        }

        const distance = @sqrt(distance_sq);

        if (distance == 0.0) {
            // Circles are exactly on top of each other - rare edge case
            return ContactManifold.init(
                pos1,
                Vec2{ .x = 1.0, .y = 0.0 }, // Arbitrary separation direction
                radius_sum,
            );
        }

        const normal = Vec2{ .x = dx / distance, .y = dy / distance };
        const penetration = radius_sum - distance;
        const contact_point = Vec2{
            .x = pos1.x + normal.x * c1.radius,
            .y = pos1.y + normal.y * c1.radius,
        };

        return ContactManifold.init(contact_point, normal, penetration);
    }

    /// Circle vs Rectangle collision using SAT
    fn checkCircleRectangle(circle: PhysicsShape, circle_pos: Vec2, rect: PhysicsShape, rect_pos: Vec2, rect_rot: f32) ?ContactManifold {
        return satCircleRectangle(circle, circle_pos, rect, rect_pos, rect_rot);
    }

    /// Rectangle vs Rectangle collision using SAT
    fn checkRectangleRectangle(rect1: PhysicsShape, pos1: Vec2, rot1: f32, rect2: PhysicsShape, pos2: Vec2, rot2: f32) ?ContactManifold {
        return satRectangleRectangle(rect1, pos1, rot1, rect2, pos2, rot2);
    }
};
