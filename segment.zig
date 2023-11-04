//! efficient implementation
const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

pub fn SegmentTree(
    comptime Type: type,
    comptime OpFn: fn (Type, Type) Type,
) type {
    return struct {
        const Self = @This();
        backing: [*]Type,
        backing_length: u64,
        length: u64,
        allocator: Allocator,

        pub fn init(array: []Type, allocator: Allocator) !Self {
            const to_alloc = 2 * array.len - 1;
            var allocated = try allocator.alloc(Type, to_alloc);
            var onebefore: [*]Type = @ptrCast(allocated.ptr - 1);
            var tmp = Self{
                .backing = onebefore,
                .backing_length = to_alloc,
                .length = array.len,
                .allocator = allocator,
            };
            tmp.build(array);
            return tmp;
        }

        pub fn deinit(self: *Self) void {
            const slice = self.backing[1 .. self.backing_length + 1];
            self.allocator.free(slice);
        }

        pub fn update(self: *Self, index: u64, value: Type) void {
            const n = self.length;
            // set value at for node index
            self.backing[n + index] = value;

            // update parents
            var i: u64 = index + n;
            while (i > 1) : (i >>= 1) {
                self.backing[i >> 1] = OpFn(self.backing[i], self.backing[i ^ 1]);
            }
        }

        pub fn query(self: *Self, start: u64, end: u64) Type {
            var left = start + self.length;
            var right = end + self.length;
            // The left and right indices will move towards each other,
            var res: Type = undefined;
            var res_set = false;
            // first loop is to set res
            while (left < right) {
                if (left & 1 == 1) {
                    res_set = true;
                    res = self.backing[left];
                    left += 1;
                }
                if (right & 1 == 1) {
                    right -= 1;
                    res = if (res_set) OpFn(res, self.backing[right]) else self.backing[right];
                }
                left /= 2;
                right /= 2;
                if (res_set) {
                    break;
                }
            }
            // second loop performs the same thing, with res already set
            while (left < right) {
                // if you are a left child, go up
                // if you are a right child, closer to the other pointer
                if (left & 1 == 1) {
                    res = OpFn(res, self.backing[left]);
                    left += 1;
                }
                if (right & 1 == 1) {
                    right -= 1;
                    res = OpFn(res, self.backing[right]);
                }
                left /= 2;
                right /= 2;
            }
            return res;
        }

        pub fn printBacking(self: *Self) void {
            for (1..self.backing_length + 1) |idx| {
                print("{} ", .{self.backing[idx]});
            }
            print("\n", .{});
        }

        fn build(self: *Self, array: []Type) void {
            // insert leaf nodes in tree
            const n = array.len;
            for (array, 0..) |val, idx| {
                self.backing[n + idx] = val;
            }

            // build the tree upwards
            var i: u64 = n - 1;
            while (i > 0) : (i -= 1) {
                self.backing[i] = OpFn(self.backing[getLeft(i)], self.backing[getRight(i)]);
            }
        }

        inline fn getParent(pos: u64) u64 {
            return pos >> 1;
        }

        inline fn getLeft(pos: u64) u64 {
            return pos << 1;
        }

        inline fn getRight(pos: u64) u64 {
            return pos << 1 | 1;
        }
    };
}

fn sum(a: i64, b: i64) i64 {
    return a + b;
}

test "simple test" {
    const allocator = std.testing.allocator;
    var arr = [_]i64{ -1, 3, 4, 0, 2, 1 };
    var rsq = try SegmentTree(i64, sum).init(&arr, allocator);
    defer rsq.deinit();
    rsq.printBacking();
}

test "update test" {
    const allocator = std.testing.allocator;
    var arr = [_]i64{ -1, 3, 4, 0, 2, 1 };
    var rsq = try SegmentTree(i64, sum).init(&arr, allocator);
    defer rsq.deinit();
    rsq.printBacking();
    rsq.update(2, 5);
    rsq.printBacking();
}

test "query test" {
    const allocator = std.testing.allocator;
    var arr = [_]i64{ -1, 3, 4, 0, 2, 1 };
    var rsq = try SegmentTree(i64, sum).init(&arr, allocator);
    defer rsq.deinit();
    try expect(rsq.query(1, 3) == 7);
    try expect(rsq.query(1, 4) == 7);
    try expect(rsq.query(1, 5) == 9);
}
