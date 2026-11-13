const std = @import("std");
const Vec2 = @import("../math/Vec2.zig");
const Body = @import("Body.zig");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Rectangle = @import("../math/shapes.zig").Rectangle;

/// Contact information for collision response
pub const ContactManifold = struct {
    point: Vec2, // Centre of the contact area in world space
    normal: Vec2, // Collision normal (pointing from body1 to body2)
    penetration: f32, // How deep the overlap is
    /// Where the bodies touch. Two flat faces meeting give the two ends of the
    /// shared edge, which is what lets a box resist tipping; everything else
    /// gives the single point `point`.
    points: [2]Vec2,
    point_count: u8 = 1,

    pub fn init(point: Vec2, normal: Vec2, penetration: f32) ContactManifold {
        return .{
            .point = point,
            .normal = normal,
            .penetration = penetration,
            .points = .{ point, point },
        };
    }

    pub fn contactPoints(self: *const ContactManifold) []const Vec2 {
        return self.points[0..self.point_count];
    }

    /// The same contact seen from the other body.
    pub fn flipped(self: ContactManifold) ContactManifold {
        var result = self;
        result.normal = self.normal.negate();
        return result;
    }
};

/// Contact points closer together than this are treated as one.
const min_contact_spread: f32 = 0.5;

/// Narrow phase collision detection - precise collision testing between specific shape pairs
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

/// project a polygon onto an axis and return min/max projection values
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

// project a circle onto an axis
fn projectCircle(center: Vec2, radius: f32, axis: Vec2) Projection {
    const center_proj = center.dot(axis);
    return .{ .min = center_proj - radius, .max = center_proj + radius };
}

/// The shortest way to separate two shapes along one axis.
const Separation = struct {
    /// Unit vector pointing the way the second shape has to move.
    axis: Vec2,
    depth: f32,

    const none = Separation{ .axis = Vec2.zero, .depth = std.math.inf(f32) };

    /// Null when the projections do not overlap. The second shape can leave
    /// in either direction along the axis; the shorter way is taken, so a
    /// shape lying wholly inside another is pushed out through the nearest
    /// face rather than by the length it covers. `centre_diff`, from the first
    /// shape's centre to the second's, settles an exact tie.
    fn along(axis: Vec2, first: Projection, second: Projection, centre_diff: Vec2) ?Separation {
        const forward = first.max - second.min;
        const backward = second.max - first.min;
        if (forward <= 0.0 or backward <= 0.0) return null;
        const goes_forward = if (forward == backward) axis.dot(centre_diff) >= 0.0 else forward < backward;
        return if (goes_forward)
            .{ .axis = axis, .depth = forward }
        else
            .{ .axis = axis.negate(), .depth = backward };
    }
};

/// Whether a world-space point lies inside a rectangle given by its corners
/// (in getRectangleCorners order), with a small tolerance. Works on the edge
/// vectors directly, so it needs no trigonometry or square roots.
fn rectangleContainsPoint(rect: Rectangle, corners: *const [4]Vec2, point: Vec2) bool {
    const tolerance = 0.01;
    const rel = point.sub(corners[0]);
    // Distance along each edge from corner 0, scaled by that edge's length.
    const along_w = rel.dot(corners[1].sub(corners[0]));
    const along_h = rel.dot(corners[3].sub(corners[0]));
    return along_w >= -tolerance * rect.width and along_w <= (rect.width + tolerance) * rect.width and
        along_h >= -tolerance * rect.height and along_h <= (rect.height + tolerance) * rect.height;
}

/// Corners of either rectangle that lie inside the other.
const ContainedCorners = struct {
    corners: [8]Vec2 = undefined,
    count: usize = 0,

    fn find(rect1: Rectangle, corners1: *const [4]Vec2, rect2: Rectangle, corners2: *const [4]Vec2) ContainedCorners {
        var result = ContainedCorners{};
        for (corners1) |corner| {
            if (rectangleContainsPoint(rect2, corners2, corner)) result.add(corner);
        }
        for (corners2) |corner| {
            if (rectangleContainsPoint(rect1, corners1, corner)) result.add(corner);
        }
        return result;
    }

    fn add(self: *ContainedCorners, corner: Vec2) void {
        self.corners[self.count] = corner;
        self.count += 1;
    }

    /// Their centre. It always falls inside the overlap and does not depend on
    /// which rectangle is passed first, so a small box on a wide floor gets a
    /// contact under the box rather than at the floor's centre.
    fn centre(self: *const ContainedCorners) Vec2 {
        var sum = Vec2.zero;
        for (self.corners[0..self.count]) |corner| sum = sum.add(corner);
        return sum.scale(1.0 / @as(f32, @floatFromInt(self.count)));
    }

    /// The two corners furthest apart along `tangent`: the ends of the edge
    /// the rectangles share. Null when they are closer than `min_spread`.
    fn ends(self: *const ContainedCorners, tangent: Vec2, min_spread: f32) ?[2]Vec2 {
        var low = self.corners[0];
        var high = self.corners[0];
        var low_proj = low.dot(tangent);
        var high_proj = low_proj;
        for (self.corners[1..self.count]) |corner| {
            const proj = corner.dot(tangent);
            if (proj < low_proj) {
                low_proj = proj;
                low = corner;
            }
            if (proj > high_proj) {
                high_proj = proj;
                high = corner;
            }
        }
        return if (high_proj - low_proj >= min_spread) .{ low, high } else null;
    }
};

fn satRectangleRectangle(rect1: PhysicsShape, pos1: Vec2, rot1: f32, rect2: PhysicsShape, pos2: Vec2, rot2: f32) ?ContactManifold {
    const corners1 = getRectangleCorners(rect1.rectangle, pos1, rot1);
    const corners2 = getRectangleCorners(rect2.rectangle, pos2, rot2);

    // Kept pointing from rect1 to rect2.
    var least = Separation.none;
    const center_diff = pos2.sub(pos1);

    // 0 = Axis came from Rect1, 1 = Axis came from Rect2
    var axis_source: u8 = 0;

    //  Test axes from Rectangle 1
    inline for (0..2) |i| {
        const edge = corners1[(i + 1) % 4].sub(corners1[i]);
        const axis = edge.perpendicular().normalize();

        const proj1 = projectPolygon(&corners1, axis);
        const proj2 = projectPolygon(&corners2, axis);

        const separation = Separation.along(axis, proj1, proj2, center_diff) orelse return null;
        if (separation.depth < least.depth) {
            least = separation;
            axis_source = 0; // Rect 1 provided this axis
        }
    }

    //  Test axes from Rectangle 2
    inline for (0..2) |i| {
        const edge = corners2[(i + 1) % 4].sub(corners2[i]);
        const axis = edge.perpendicular().normalize();

        const proj1 = projectPolygon(&corners1, axis);
        const proj2 = projectPolygon(&corners2, axis);

        const separation = Separation.along(axis, proj1, proj2, center_diff) orelse return null;
        if (separation.depth < least.depth) {
            least = separation;
            axis_source = 1; // Rect 2 provided this axis
        }
    }

    const separation_axis = least.axis;
    const min_overlap = least.depth;

    // Determine the contact points from the corners inside the overlap.
    const contained = ContainedCorners.find(rect1.rectangle, &corners1, rect2.rectangle, &corners2);
    if (contained.count == 0) {
        // No corner of either rectangle is inside the other (two bars
        // crossing). Fall back to the deepest vertex of the incident body
        // against the reference face.
        const fallback = if (axis_source == 0)
            // Axis from Rect1 (reference): deepest point of Rect2 against the normal.
            findSupportPoint(&corners2, separation_axis.negate())
        else
            // Axis from Rect2 (reference): deepest point of Rect1 along the normal.
            findSupportPoint(&corners1, separation_axis);
        return ContactManifold.init(fallback, separation_axis, min_overlap);
    }

    var manifold = ContactManifold.init(contained.centre(), separation_axis, min_overlap);
    const tangent = Vec2{ .x = -separation_axis.y, .y = separation_axis.x };
    if (contained.ends(tangent, min_contact_spread)) |ends| {
        manifold.points = ends;
        manifold.point_count = 2;
    }
    return manifold;
}

/// Separating Axis Theorem (SAT) collision detection for circle vs rotated rectangle
fn satCircleRectangle(circle: PhysicsShape, circle_pos: Vec2, rect: PhysicsShape, rect_pos: Vec2, rect_rot: f32) ?ContactManifold {
    const corners = getRectangleCorners(rect.rectangle, rect_pos, rect_rot);
    const radius = circle.circle.radius;

    // Kept pointing from the circle to the rectangle.
    var least = Separation.none;
    const center_diff = rect_pos.sub(circle_pos);

    // Test rectangle edge normals
    inline for (0..2) |i| {
        const edge = corners[(i + 1) % 4].sub(corners[i]);
        const axis = edge.perpendicular().normalize();

        const rect_proj = projectPolygon(&corners, axis);
        const circle_proj = projectCircle(circle_pos, radius, axis);

        const separation = Separation.along(axis, circle_proj, rect_proj, center_diff) orelse return null;
        if (separation.depth < least.depth) least = separation;
    }

    // Test axis from circle center to closest point on rectangle
    var closest_point = corners[0];
    var min_dist_sq: f32 = std.math.inf(f32);

    // Check distance to each corner
    inline for (corners) |corner| {
        const dist_sq = corner.distanceSqr(circle_pos);
        if (dist_sq < min_dist_sq) {
            min_dist_sq = dist_sq;
            closest_point = corner;
        }
    }

    // Check distance to each edge
    inline for (0..4) |i| {
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

        const separation = Separation.along(axis, circle_proj, rect_proj, center_diff) orelse return null;
        if (separation.depth < least.depth) least = separation;
    }

    return ContactManifold.init(closest_point, least.axis, least.depth);
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
                    const manifold = checkCircleRectangle(shape2, pos2, shape1, pos1, rot1) orelse return null;
                    return manifold.flipped();
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

/// Find the support point.
/// If multiple vertices are equally deep (e.g. flat edge), returns their average.
fn findSupportPoint(corners: *const [4]Vec2, direction: Vec2) Vec2 {
    var max_proj: f32 = -std.math.inf(f32);

    //  Find the absolute deepest depth
    inline for (corners) |c| {
        const proj = c.dot(direction);
        if (proj > max_proj) {
            max_proj = proj;
        }
    }

    //  Average all vertices that are "close enough" to that depth
    // This creates a stable contact point in the middle of a flat edge.
    var sum = Vec2.zero;
    var count: f32 = 0.0;

    // If corners are within 0.5 pixels depth of each other, treat them as a flat edge.
    const tolerance = 0.5;

    inline for (corners) |c| {
        const proj = c.dot(direction);
        if (proj >= max_proj - tolerance) {
            sum = sum.add(c);
            count += 1.0;
        }
    }

    return sum.scale(1.0 / count);
}

test "box on a wide floor gets a contact under the box in either body order" {
    const box = PhysicsShape.rect(20, 20);
    const floor = PhysicsShape.rect(1200, 20);
    const box_pos = Vec2.init(500, 0);
    const floor_pos = Vec2.init(0, 19);

    const box_first = checkShapesCollision(box, box_pos, 0, floor, floor_pos, 0).?;
    const floor_first = checkShapesCollision(floor, floor_pos, 0, box, box_pos, 0).?;

    for ([_]ContactManifold{ box_first, floor_first }) |m| {
        try std.testing.expectApproxEqAbs(@as(f32, 500), m.point.x, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 10), m.point.y, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 1), m.penetration, 0.001);
    }
    // The normal always points from the first shape to the second.
    try std.testing.expectApproxEqAbs(@as(f32, 1), box_first.normal.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), floor_first.normal.y, 0.001);
}

test "box overhanging a ledge is contacted inside the overlap, not under its centre" {
    // The ledge ends at x = 10; the box spans x = 5..25, so only 5..10 is supported.
    const m = checkShapesCollision(
        PhysicsShape.rect(20, 20),
        Vec2.init(15, 0),
        0,
        PhysicsShape.rect(100, 20),
        Vec2.init(-40, 19),
        0,
    ).?;
    try std.testing.expectApproxEqAbs(@as(f32, 7.5), m.point.x, 0.001);
    try std.testing.expect(m.point.x < 15);
}

test "crossing bars with no contained corners still produce a contact" {
    const m = checkShapesCollision(
        PhysicsShape.rect(100, 10),
        Vec2.zero,
        0,
        PhysicsShape.rect(10, 100),
        Vec2.zero,
        0,
    ).?;
    try std.testing.expect(std.math.isFinite(m.point.x) and std.math.isFinite(m.point.y));
    try std.testing.expect(m.penetration > 0);
}

test "rotated boxes: a single penetrating corner is the contact" {
    // A square rotated 45 degrees, its lowest corner dipping 1 unit into a floor.
    const half_diagonal = 10.0 * std.math.sqrt2;
    const m = checkShapesCollision(
        PhysicsShape.rect(20, 20),
        Vec2.init(30, -half_diagonal + 1),
        std.math.pi / 4.0,
        PhysicsShape.rect(400, 20),
        Vec2.init(0, 10),
        0,
    ).?;
    try std.testing.expectApproxEqAbs(@as(f32, 30), m.point.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.point.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.penetration, 0.01);
}

test "a box resting flat is contacted at both ends of the shared edge" {
    const box = PhysicsShape.rect(20, 20);
    const floor = PhysicsShape.rect(1200, 20);
    for ([_]bool{ false, true }) |floor_first| {
        const m = if (floor_first)
            checkShapesCollision(floor, Vec2.init(0, 19), 0, box, Vec2.init(500, 0), 0).?
        else
            checkShapesCollision(box, Vec2.init(500, 0), 0, floor, Vec2.init(0, 19), 0).?;
        try std.testing.expectEqual(@as(u8, 2), m.point_count);
        const xs = [_]f32{ @min(m.points[0].x, m.points[1].x), @max(m.points[0].x, m.points[1].x) };
        try std.testing.expectApproxEqAbs(@as(f32, 490), xs[0], 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 510), xs[1], 0.001);
        for (m.contactPoints()) |point| try std.testing.expectApproxEqAbs(@as(f32, 10), point.y, 0.001);
        // The summary point stays at the centre of the contact.
        try std.testing.expectApproxEqAbs(@as(f32, 500), m.point.x, 0.001);
    }
}

test "boxes stacked half a width apart are contacted at the ends of their overlap" {
    // Upper box spans x = 10..30, lower box x = 0..20: they share x = 10..20.
    const m = checkShapesCollision(
        PhysicsShape.rect(20, 20),
        Vec2.init(20, 0),
        0,
        PhysicsShape.rect(20, 20),
        Vec2.init(10, 19),
        0,
    ).?;
    try std.testing.expectEqual(@as(u8, 2), m.point_count);
    try std.testing.expectApproxEqAbs(@as(f32, 10), @min(m.points[0].x, m.points[1].x), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), @max(m.points[0].x, m.points[1].x), 0.001);
}

test "a corner, a circle and crossing bars each give a single contact point" {
    const half_diagonal = 10.0 * std.math.sqrt2;
    const corner = checkShapesCollision(
        PhysicsShape.rect(20, 20),
        Vec2.init(30, -half_diagonal + 1),
        std.math.pi / 4.0,
        PhysicsShape.rect(400, 20),
        Vec2.init(0, 10),
        0,
    ).?;
    const circle = checkShapesCollision(PhysicsShape.circ(10), Vec2.init(0, -9), 0, PhysicsShape.rect(400, 20), Vec2.init(0, 10), 0).?;
    const flipped = checkShapesCollision(PhysicsShape.rect(400, 20), Vec2.init(0, 10), 0, PhysicsShape.circ(10), Vec2.init(0, -9), 0).?;
    const bars = checkShapesCollision(PhysicsShape.rect(100, 10), Vec2.zero, 0, PhysicsShape.rect(10, 100), Vec2.zero, 0).?;
    for ([_]ContactManifold{ corner, circle, flipped, bars }) |m| {
        try std.testing.expectEqual(@as(u8, 1), m.point_count);
        try std.testing.expectEqual(m.point, m.contactPoints()[0]);
    }
    // Flipping a manifold reverses the normal and keeps the points.
    try std.testing.expectEqual(circle.point, flipped.point);
    try std.testing.expectApproxEqAbs(-circle.normal.y, flipped.normal.y, 0.0001);
}

test "a ball inside a thick wall is pushed back out through the nearest face" {
    // 8 px into the left face of a wall 300 wide and 1950 tall, well below
    // the wall's centre. The way out is to the left, by the 16 px it takes to
    // clear the face, not up or down the wall.
    const ball = PhysicsShape.circ(8);
    const wall = PhysicsShape.rect(300, 1950);
    const manifold = checkShapesCollision(ball, Vec2.init(908, 450), 0, wall, Vec2.init(1050, 325), 0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1), manifold.normal.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), manifold.normal.y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 16), manifold.penetration, 1e-3);

    // The same pair in the other order points the other way.
    const reversed = checkShapesCollision(wall, Vec2.init(1050, 325), 0, ball, Vec2.init(908, 450), 0).?;
    try std.testing.expectApproxEqAbs(@as(f32, -1), reversed.normal.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 16), reversed.penetration, 1e-3);
}

test "a box inside a thick wall is pushed back out through the nearest face" {
    const box = PhysicsShape.rect(20, 20);
    const wall = PhysicsShape.rect(300, 1950);
    // Wholly inside: its right edge is 30 px from the wall's left face.
    const manifold = checkShapesCollision(box, Vec2.init(920, 450), 0, wall, Vec2.init(1050, 325), 0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1), manifold.normal.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), manifold.normal.y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 30), manifold.penetration, 1e-3);
}
