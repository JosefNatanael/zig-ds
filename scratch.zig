const std = @import("std");
const print = std.debug.print;

pub fn Data() type {
    return struct {
        data: u8 = 69,

        pub fn init() @This() {
            return .{ .data = 0 };
        }

        pub fn get(self: @This()) u8 {
            return self.data;
        }
    };
}

test "test data" {
    var hi = Data().init();

    print("1: {}\n", .{hi.get()});
}

test "size of " {
    print("Size usize: {}\n", .{@sizeOf(usize)});
    print("Size isize: {}\n", .{@sizeOf(isize)});
}

fn hihi(hi: []const u8) void {
    const size = @sizeOf(@TypeOf(hi));
    const length = hi.len;
    const pointer = hi.ptr;
    const size2 = @sizeOf(@TypeOf(pointer));
    print("Size: {}\n", .{size});
    print("Size ptr: {}\n", .{size2});
    print("Length: {}\n", .{length});
}

fn hey(h: *[3]u8) void {
    const size = @sizeOf(@TypeOf(h));
    const length = h.len;
    print("Size: {}\n", .{size});
    print("Length: {}\n", .{length});
    h[0] = 69;
}

pub fn main() !void {
    var arr1 = [_]u8{ 1, 2, 3 };
    const arr2 = [_]u8{ 1, 2, 3, 4, 5 };
    const size1 = @sizeOf(@TypeOf(arr1));
    const size2 = @sizeOf(@TypeOf(arr2));

    hihi(&arr1);
    hihi(&arr2);

    print("Size: {}\n", .{size1});
    print("Size: {}\n", .{size2});

    hey(&arr1);

    print("{any}\n", .{arr1});
    print("{any}\n", .{arr2});
}
