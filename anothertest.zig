const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

test {
    for (0..15) |i| {
        print("printing: {}\n", .{i});
    }
}
