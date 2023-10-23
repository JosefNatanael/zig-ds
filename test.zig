const std = @import("std");
const print = std.debug.print;

test {
    var x: u64 = 3;
    print("{} {}\n", .{ x, x / 2 });
}
