//! implementation of some segment tree algorithms
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
        backing: []Type,
        allocator: Allocator,
        length: u64,

        pub fn init(array: []Type, allocator: Allocator) !Self {
            var allocated = try allocator.alloc(Type, getCapacity(array.len));
            var tmp = Self{ .backing = allocated, .allocator = allocator, .length = array.len };
            tmp.build(array, 0, array.len - 1, 0);
            return tmp;
        }

        pub fn deinit(self: *Self) void {
            if (self.backing.len == 0) {
                return;
            }
            self.allocator.free(self.backing);
        }

        fn build(self: *Self, array: []Type, low: u64, high: u64, pos: u64) void {
            if (low == high) {
                self.backing[pos] = array[low];
                return;
            }
            const mid = getMid(low, high);
            const leftIdx = getLeft(pos);
            const rightIdx = getRight(pos);
            self.build(array, low, mid, leftIdx);
            self.build(array, mid + 1, high, rightIdx);
            self.backing[pos] = OpFn(self.backing[leftIdx], self.backing[rightIdx]);
        }

        pub fn update(self: *Self, index: u64, value: Type) void {
            self.updateRecursive(index, value, 0, self.length - 1, 0);
        }

        fn updateRecursive(self: *Self, index: u64, value: Type, start: u64, end: u64, pos: u64) void {
            if (start == end) {
                self.backing[pos] = value;
                return;
            }
            const mid = getMid(start, end);
            const leftIdx = getLeft(pos);
            const rightIdx = getRight(pos);
            if (index > mid) {
                self.updateRecursive(index, value, mid + 1, end, rightIdx);
            } else {
                self.updateRecursive(index, value, start, mid, leftIdx);
            }
            self.backing[pos] = OpFn(self.backing[leftIdx], self.backing[rightIdx]);
        }

        pub fn query(self: *Self, start: u64, end: u64) Type {
            return self.queryRecursive(start, end, 0, self.length - 1, 0);
        }

        fn queryRecursive(self: *Self, qstart: u64, qend: u64, start: u64, end: u64, pos: u64) Type {
            if (qstart == start and qend == end) {
                return self.backing[pos];
            }
            const mid = getMid(start, end);
            if (qstart > mid) {
                return self.queryRecursive(qstart, qend, mid + 1, end, getRight(pos));
            } else if (qend <= mid) {
                return self.queryRecursive(qstart, qend, start, mid, getLeft(pos));
            }
            const left = self.queryRecursive(qstart, mid, start, mid, getLeft(pos));
            const right = self.queryRecursive(mid + 1, qend, mid + 1, end, getRight(pos));
            return OpFn(left, right);
        }

        // algo: x = closest power of 2 >= n
        // return 2x - 1
        fn getCapacity(n: u64) u64 {
            if (n > 1) {
                const leadingZeroes: u7 = @clz(n - 1);
                const shift: u6 = @intCast(64 - leadingZeroes + 1);
                const one: u64 = 1;
                return (one << shift) - 1;
            }
            return 1;
        }

        inline fn getMid(low: u64, high: u64) u64 {
            assert(low <= high);
            return low + (high - low) / 2;
        }

        inline fn getParent(idx: u64) u64 {
            return idx / 2;
        }

        inline fn getLeft(idx: u64) u64 {
            return 2 * idx + 1;
        }

        inline fn getRight(idx: u64) u64 {
            return 2 * idx + 2;
        }
    };
}

fn lessThan(a: i8, b: i8) i8 {
    return if (a < b) a else b;
}

fn sum(a: i8, b: i8) i8 {
    return a + b;
}

test "Test find all" {
    const allocator = std.testing.allocator;
    var arr = [_]i8{ 5, 3, 7, 1, 4, 2 };
    var rsq = try SegmentTree(i8, sum).init(&arr, allocator);
    defer rsq.deinit();
    try expect(rsq.query(0, 5) == 22);
}

test "Test find middle" {
    const allocator = std.testing.allocator;
    var arr = [_]i8{ 5, 3, 7, 1, 4, 2 };
    var rsq = try SegmentTree(i8, sum).init(&arr, allocator);
    defer rsq.deinit();
    try expect(rsq.query(2, 4) == 12);
}

test "Test find ends" {
    const allocator = std.testing.allocator;
    var arr = [_]i8{ 5, 3, 7, 1, 4, 2 };
    var rsq = try SegmentTree(i8, sum).init(&arr, allocator);
    defer rsq.deinit();
    try expect(rsq.query(0, 2) == 15);
    try expect(rsq.query(3, 5) == 7);
}

test "Test minimum" {
    const allocator = std.testing.allocator;
    var arr = [_]i8{ 5, 3, 7, 1, 4, 2 };
    var rmq = try SegmentTree(i8, lessThan).init(&arr, allocator);
    defer rmq.deinit();
    try expect(rmq.query(0, 2) == 3);
    try expect(rmq.query(3, 5) == 1);
    try expect(rmq.query(0, 5) == 1);
    try expect(rmq.query(1, 4) == 1);
    try expect(rmq.query(4, 5) == 2);
}

test "test update" {
    const allocator = std.testing.allocator;
    var arr = [_]i8{ 0, 2, 3, 1, 2, 1 };
    var rmq = try SegmentTree(i8, lessThan).init(&arr, allocator);
    defer rmq.deinit();
    rmq.update(0, 5);
    rmq.update(1, 3);
    rmq.update(2, 7);
    rmq.update(3, 1);
    rmq.update(4, 4);
    rmq.update(5, 2);
    try expect(rmq.query(0, 2) == 3);
    try expect(rmq.query(3, 5) == 1);
    try expect(rmq.query(0, 5) == 1);
    try expect(rmq.query(1, 4) == 1);
    try expect(rmq.query(4, 5) == 2);
}
