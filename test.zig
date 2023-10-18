const std = @import("std");
const print = std.debug.print;

test "vecs" {
    const num: u8 = 2;
    const a: @Vector(16, i8) = @splat(num);
    const b = @Vector(16, i8){ 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 1, 1, 1, 1 };
    const c: @Vector(16, bool) = a == b;
    print("C: {}\n", .{c});
    const d: u16 = @bitCast(c);
    print("D: {}\n", .{d});
    const e: u64 = d;
    print("E: {}\n", .{e});
}

test "bitcasting" {
    var a1: i8 = -128;
    var a2: i8 = -2;
    var a3: i8 = -1;

    var b1: u8 = @bitCast(a1);
    var b2: u8 = @bitCast(a2);
    var b3: u8 = @bitCast(a3);

    print("{} {} {}\n", .{ a1, a2, a3 });
    print("{} {} {}\n", .{ b1, b2, b3 });
}

const Hihi = struct { a: i8, b: i8 };

fn something(hi: *Hihi) u64 {
    return @intFromPtr(hi) >> 12;
}

fn something2(hi: [*]Hihi) u64 {
    return @intFromPtr(hi) >> 12;
}

test "ptrs" {
    var a: Hihi = .{ .a = 5, .b = 4 };
    const b: u64 = something(&a);
    print("{}\n", .{@intFromPtr(&a)});
    print("{}\n", .{b});

    var c = [_]Hihi{ .{ .a = 1, .b = 2 }, .{ .a = 3, .b = 4 } };
    const d: u64 = something2(&c);
    print("{}\n", .{@intFromPtr(&c)});
    print("{}\n", .{d});
}

test "more ptrs" {
    const TestOnly = struct { hi: [*]u8 };
    const TestOnly2 = struct { hi: *[5]u8 };
    const size = @sizeOf(TestOnly);
    const size2 = @sizeOf(TestOnly2);
    print("size many: {}, size many2: {}\n", .{ size, size2 });
}

fn josef1(hi: *[16]Hihi) void {
    _ = hi;
}

fn josef2(hi: [*]Hihi) void {
    _ = hi;
}

test "is it convertible?" {
    var a: [8]Hihi = [_]Hihi{.{ .a = 1, .b = 1 }} ** 8;
    var b: [16]Hihi = [_]Hihi{.{ .a = 1, .b = 1 }} ** 16;
    var c: [32]Hihi = [_]Hihi{.{ .a = 1, .b = 1 }} ** 32;

    // josef1(&a);
    // josef1(&a);
    josef1(&b);
    // josef1(&c);
    // josef2(&a);
    josef2(&a);
    josef2(&b);
    josef2(&c);
}

fn testmemcpy(hi: [*]Hihi) void {
    var arr1: [4]Hihi = undefined;
    print("arr1: {any}\n", .{arr1});
    @memcpy(&arr1, hi);
    print("arr1: {any}\n", .{arr1});
}

fn testmemcpy2(hi: [*]Hihi, hello: [*]Hihi) void {
    var tmp: *[4]Hihi = @ptrCast(hello);
    print("hi: {any}\n", .{hi[0]});
    @memcpy(hi, tmp);
    print("hi: {any}\n", .{hi[0]});
}

test "memcpy?" {
    var arr = [_]Hihi{.{ .a = 5, .b = 3 }} ** 4;
    var arr2 = [_]Hihi{.{ .a = 6, .b = 4 }} ** 4;
    testmemcpy(&arr);
    testmemcpy2(&arr, &arr2);
}

test "size max int" {
    const sz = std.math.maxInt(u64);
    print("size: {}\n", .{sz});
}

pub inline fn normalizeCapacity(n: u64) u64 {
    // converts n into the next valid capacity
    if (n > 0) {
        return std.math.maxInt(u64) >> @clz(n);
    }
    return 1;
}

test "normalize?" {
    print("normalize: {}\n", .{normalizeCapacity(0)});
    print("normalize: {}\n", .{normalizeCapacity(10)});
    print("normalize: {}\n", .{normalizeCapacity(100)});
    print("normalize: {}\n", .{normalizeCapacity(1000)});
}
