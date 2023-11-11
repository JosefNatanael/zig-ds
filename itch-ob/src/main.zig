const std = @import("std");
const itch = @import("itch.zig");
const print = std.debug.print;
const expect = std.testing.expect;

pub fn main() !void {
    const t = itch.ItchMsgType.SYSEVENT;
    const t_int = @intFromEnum(t);
    const length = itch.netlen(t);
    print("t is {} {}\n", .{ t, length });
    print("t's value is {} {c}\n", .{ t_int, t_int });
    const defaultSysEventType = itch.DefaultItchMsg(itch.ItchMsgType.SYSEVENT);
    _ = defaultSysEventType;
}

test {
    std.testing.refAllDecls(@This());
}

test "simple test" {
    try std.testing.expect(true);
}
