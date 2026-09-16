const benchmark = @import("benchmark.zig");

test "benchmark: mixed enclosure always awake" {
    try benchmark.run(.mixed_awake);
}

test "benchmark: mixed enclosure with sleeping" {
    try benchmark.run(.mixed_sleeping);
}
