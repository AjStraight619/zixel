const benchmark = @import("benchmark.zig");

test "benchmark: sparse moving circles" {
    try benchmark.run(.sparse);
}

test "benchmark: dense circle cloud" {
    try benchmark.run(.circles);
}

test "benchmark: broadphase positive coordinates" {
    try benchmark.run(.broadphase_positive);
}

test "benchmark: broadphase negative coordinates" {
    try benchmark.run(.broadphase_negative);
}
