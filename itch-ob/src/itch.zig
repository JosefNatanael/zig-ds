const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const meta = std.meta;
const bigToNative = std.mem.bigToNative;

pub const ItchMsgType = enum(u8) {
    SYSEVENT = 'S',
    STOCK_DIRECTORY = 'R',
    TRADING_ACTION = 'H',
    REG_SHO_RESTRICT = 'Y', // 20
    MPID_POSITION = 'L', // 26
    MWCB_DECLINE = 'V', // market wide circuit breaker // 35
    MWCB_STATUS = 'W',
    IPO_QUOTE_UPDATE = 'K', // 28
    ADD_ORDER = 'A', // 36
    ADD_ORDER_MPID = 'F',
    EXECUTE_ORDER = 'E',
    EXECUTE_ORDER_WITH_PRICE = 'C',
    REDUCE_ORDER = 'X',
    DELETE_ORDER = 'D',
    REPLACE_ORDER = 'U',
    TRADE = 'P',
    CROSS_TRADE = 'Q',
    BROKEN_TRADE = 'B',
    NET_ORDER_IMBALANCE = 'I',
    RETAIL_PRICE_IMPROVEMENT = 'N',
    PROCESS_LULD_AUCTION_COLLAR_MESSAGE = 'J',
};

pub fn netlen(comptime msgType: ItchMsgType) comptime_int {
    comptime {
        return switch (msgType) {
            ItchMsgType.SYSEVENT => 12,
            ItchMsgType.STOCK_DIRECTORY => 39,
            ItchMsgType.TRADING_ACTION => 25,
            ItchMsgType.REG_SHO_RESTRICT => 20,
            ItchMsgType.MPID_POSITION => 26,
            ItchMsgType.MWCB_DECLINE => 35,
            ItchMsgType.MWCB_STATUS => 12,
            ItchMsgType.IPO_QUOTE_UPDATE => 28,
            ItchMsgType.ADD_ORDER => 36,
            ItchMsgType.ADD_ORDER_MPID => 40,
            ItchMsgType.EXECUTE_ORDER => 31,
            ItchMsgType.EXECUTE_ORDER_WITH_PRICE => 36,
            ItchMsgType.REDUCE_ORDER => 23,
            ItchMsgType.DELETE_ORDER => 19,
            ItchMsgType.REPLACE_ORDER => 35,
            ItchMsgType.TRADE => 44,
            ItchMsgType.CROSS_TRADE => 40,
            ItchMsgType.BROKEN_TRADE => 19,
            ItchMsgType.NET_ORDER_IMBALANCE => 50,
            ItchMsgType.RETAIL_PRICE_IMPROVEMENT => 20,
            ItchMsgType.PROCESS_LULD_AUCTION_COLLAR_MESSAGE => 35,
        };
    }
}

pub const Side = enum(u8) {
    BUY = 'B',
    SELL = 'S',
};

// itch protocol sends data in nanoseconds since start of day, ns in a day is 86.4 trillion
// itch protocol sends timestamp using 6 bytes, which can represent up to 281 trillion
pub const Timestamp = u48;
pub const Oid = u64;
pub const Price = u32;
pub const SignedPrice = i32;
pub const Qty = u32;
pub const Locate = u16;

// refresher:
// big endian: MSB in small address, LSB in big address
// e.g. 0x01234567 => small address 01 23 45 67 big address
// little endian: LSB in small address, MSB in big address
// e.g. 0x01234567 => small address 67 45 23 01 small address

pub fn read8(src: [*]const u8) u64 {
    return std.mem.readIntBig(u64, @ptrCast(src));
}

pub fn read6(src: [*]const u8) u48 {
    return std.mem.readIntBig(u48, @ptrCast(src));
}

pub fn read4(src: [*]const u8) u32 {
    return std.mem.readIntBig(u32, @ptrCast(src));
}

pub fn read2(src: [*]const u8) u16 {
    return std.mem.readIntBig(u16, @ptrCast(src));
}

pub fn readOid(src: [*]const u8) Oid {
    return read8(src);
}

pub fn readTimestamp(src: [*]const u8) Timestamp {
    return read6(src);
}

pub fn readPrice(src: [*]const u8) Price {
    return read4(src);
}

pub fn readQty(src: [*]const u8) Qty {
    return read4(src);
}

pub fn readLocate(src: [*]const u8) Locate {
    return read2(src);
}

pub fn readSide(src: u8) Side {
    return @enumFromInt(src);
}

/// This function issues a compile error if there is a problem with the
/// provided itch message type. An itch message must have the following:
/// member functions: pub fn parse(ptr: [*]const u8) Self
pub fn verifyItchMessage(comptime ItchMsg: type) void {
    comptime {
        switch (@typeInfo(ItchMsg)) {
            .Struct => {},
            else => @compileError("ItchMsg has to be a Struct type with parse member function"),
        }

        // comptime field: comptime network_len: comptime_int
        // if (!@hasField(ItchMsg, "network_len")) {
        //     @compileError("ItchMsg needs network_len: comptime_int field");
        // }
        // var item: ItchMsg = undefined;
        // const network_len = @field(item, "network_len");
        // const field_info = @typeInfo(@TypeOf(network_len));
        // if (field_info != .ComptimeInt) {
        //     @compileError("ItchMsg.network_len type has to be: comptime_int");
        // }

        if (@hasDecl(ItchMsg, "parse")) {
            const parse = ItchMsg.parse;
            const info = @typeInfo(@TypeOf(parse));
            if (info == .Fn) {
                const func = info.Fn;
                if (func.params.len != 1) {
                    @compileError("ItchMsg.parse(...) takes 1 parameter: [*]const u8");
                } else {
                    if (func.params[0].type != null and func.params[0].type.? != [*]const u8) {
                        @compileError("Argument has to be [*]const u8");
                    }
                    if (func.return_type != null and func.return_type.? != ItchMsg) {
                        @compileError("Return type has to be Self");
                    }
                }
            } else {
                @compileError("ItchMsg.parse has to be a member function");
            }
        } else {
            @compileError("ItchMsg missing parse member function");
        }
    }
}

pub const DefaultItchMsg = struct {
    comptime {
        verifyItchMessage(@This());
    }

    pub fn parse(ptr: [*]const u8) @This() {
        _ = ptr;
        return .{};
    }
};

// pub fn DefaultItchMsg() type {
//     return struct {
//         comptime {
//             verifyItchMessage(@This());
//         }
//
//         pub fn parse(ptr: [*]const u8) @This() {
//             _ = ptr;
//             return .{};
//         }
//     };
// }

pub const ItchMsgAddOrder = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,
    price: Price,
    qty: Qty,
    locate: Locate,
    isBuy: Side,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
            .price = readPrice(ptr + 32),
            .qty = readQty(ptr + 20),
            .locate = readLocate(ptr + 1),
            .isBuy = readSide(ptr[19]),
        };
    }
};

pub const ItchMsgAddOrderMpid = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,
    price: Price,
    qty: Qty,
    locate: Locate,
    isBuy: Side,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
            .price = readPrice(ptr + 32),
            .qty = readQty(ptr + 20),
            .locate = readLocate(ptr + 1),
            .isBuy = readSide(ptr[19]),
        };
    }
};

pub const ItchMsgExecuteOrder = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,
    qty: Qty,
    locate: Locate,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
            .qty = readQty(ptr + 19),
            .locate = readLocate(ptr + 1),
        };
    }
};

pub const ItchMsgExecuteOrderWithPrice = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,
    qty: Qty,
    locate: Locate,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
            .qty = readQty(ptr + 19),
            .locate = readLocate(ptr + 1),
        };
    }
};

pub const ItchMsgReduceOrder = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,
    qty: Qty,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
            .qty = readQty(ptr + 19),
        };
    }
};

pub const ItchMsgDeleteOrder = struct {
    comptime {
        verifyItchMessage(@This());
    }
    timestamp: Timestamp,
    oid: Oid,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .timestamp = readTimestamp(ptr + 5),
            .oid = readOid(ptr + 11),
        };
    }
};

pub const ItchMsgReplaceOrder = struct {
    comptime {
        verifyItchMessage(@This());
    }
    oid: Oid,
    new_oid: Oid,
    new_qty: Qty,
    new_price: Price,

    pub fn parse(ptr: [*]const u8) @This() {
        return .{
            .oid = readOid(ptr + 11),
            .new_oid = readOid(ptr + 19),
            .new_qty = readQty(ptr + 27),
            .new_price = readPrice(ptr + 31),
        };
    }
};

test "sizes" {
    try expectEqual(0, @sizeOf(DefaultItchMsg));
    try expectEqual(32, @sizeOf(ItchMsgAddOrder));
    try expectEqual(32, @sizeOf(ItchMsgAddOrderMpid));
    try expectEqual(24, @sizeOf(ItchMsgExecuteOrder));
    try expectEqual(24, @sizeOf(ItchMsgExecuteOrderWithPrice));
    try expectEqual(24, @sizeOf(ItchMsgReduceOrder));
    try expectEqual(16, @sizeOf(ItchMsgDeleteOrder));
    try expectEqual(24, @sizeOf(ItchMsgReplaceOrder));
}

test "basic itch parse test" {
    // add order
    var addOrderMsg: [36]u8 = undefined;
    addOrderMsg[0] = 0x41;
    addOrderMsg[1] = 0x00;
    addOrderMsg[2] = 0x01;
    addOrderMsg[3] = 0x00;
    addOrderMsg[4] = 0x00;
    addOrderMsg[5] = 0x00;
    addOrderMsg[6] = 0x00;
    addOrderMsg[7] = 0x00;
    addOrderMsg[8] = 0x00;
    addOrderMsg[9] = 0x00;
    addOrderMsg[10] = 0x03;
    addOrderMsg[11] = 0x00;
    addOrderMsg[12] = 0x00;
    addOrderMsg[13] = 0x00;
    addOrderMsg[14] = 0x00;
    addOrderMsg[15] = 0x00;
    addOrderMsg[16] = 0x00;
    addOrderMsg[17] = 0x00;
    addOrderMsg[18] = 0x04;
    addOrderMsg[19] = 0x42;
    addOrderMsg[20] = 0x00;
    addOrderMsg[21] = 0x00;
    addOrderMsg[22] = 0x00;
    addOrderMsg[23] = 0x05;
    addOrderMsg[24] = 0x00;
    addOrderMsg[25] = 0x00;
    addOrderMsg[26] = 0x00;
    addOrderMsg[27] = 0x00;
    addOrderMsg[28] = 0x00;
    addOrderMsg[29] = 0x00;
    addOrderMsg[30] = 0x00;
    addOrderMsg[31] = 0x00;
    addOrderMsg[32] = 0x00;
    addOrderMsg[33] = 0x00;
    addOrderMsg[34] = 0x00;
    addOrderMsg[35] = 0x06;

    const msg = ItchMsgAddOrder.parse(&addOrderMsg);
    try expect(1 == msg.locate);
    try expect(Side.BUY == msg.isBuy);
    try expect(3 == msg.timestamp);
    try expect(4 == msg.oid);
    try expect(5 == msg.qty);
    try expect(6 == msg.price);
}
