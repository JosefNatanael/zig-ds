const std = @import("std");
const itch = @import("itch.zig");
const time = @import("time.zig");
const bufferedreader = @import("bufferedreader.zig");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;

fn processor(comptime Msg: type, comptime BufSize: comptime_int, comptime MsgLength: comptime_int) type {
    comptime {
        itch.verifyItchMessage(Msg);
    }
    return struct {
        fn read_from(buf: *bufferedreader.StackBufferedReader(BufSize)) Msg {
            const msglen = itch.read2(buf.get(0));
            assert(msglen == MsgLength);
            buf.advance(2); // first 2 bytes is the length of the payload
            _ = buf.ensure(MsgLength);
            const ret = Msg.parse(buf.get(0));
            buf.advance(MsgLength);
            return ret;
        }
    };
}

pub fn main() !void {
    const buflen = 1024 * 16;
    var buf = bufferedreader.StackBufferedReader(buflen).init();
    var num_packets: u64 = 0;
    var start_time: i128 = undefined;
    while (buf.ensure(3) == bufferedreader.ReadStatus.OK) {
        if (num_packets > 0) {
            num_packets += 1;
        }
        const msgType: itch.ItchMsgType = @enumFromInt(buf.get(2)[0]);
        switch (msgType) {
            .SYSEVENT => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.SYSEVENT)).read_from(&buf);
            },
            .STOCK_DIRECTORY => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.STOCK_DIRECTORY)).read_from(&buf);
            },
            .TRADING_ACTION => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.TRADING_ACTION)).read_from(&buf);
            },
            .REG_SHO_RESTRICT => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.REG_SHO_RESTRICT)).read_from(&buf);
            },
            .MPID_POSITION => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.MPID_POSITION)).read_from(&buf);
            },
            .MWCB_DECLINE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.MWCB_DECLINE)).read_from(&buf);
            },
            .MWCB_STATUS => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.MWCB_STATUS)).read_from(&buf);
            },
            .IPO_QUOTE_UPDATE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.IPO_QUOTE_UPDATE)).read_from(&buf);
            },
            .TRADE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.TRADE)).read_from(&buf);
            },
            .CROSS_TRADE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.CROSS_TRADE)).read_from(&buf);
            },
            .BROKEN_TRADE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.BROKEN_TRADE)).read_from(&buf);
            },
            .NET_ORDER_IMBALANCE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.NET_ORDER_IMBALANCE)).read_from(&buf);
            },
            .RETAIL_PRICE_IMPROVEMENT => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.RETAIL_PRICE_IMPROVEMENT)).read_from(&buf);
            },
            .PROCESS_LULD_AUCTION_COLLAR_MESSAGE => {
                _ = processor(itch.DefaultItchMsg, buflen, itch.netlen(.PROCESS_LULD_AUCTION_COLLAR_MESSAGE)).read_from(&buf);
            },

            .ADD_ORDER => {
                if (num_packets == 0) {
                    num_packets += 1;
                    start_time = time.nanoTimestamp();
                }
                const packet = processor(itch.ItchMsgAddOrder, buflen, itch.netlen(.ADD_ORDER)).read_from(&buf);
                assert(packet.oid < std.math.maxInt(i32));
            },
            .ADD_ORDER_MPID => {
                _ = processor(itch.ItchMsgAddOrderMpid, buflen, itch.netlen(.ADD_ORDER_MPID)).read_from(&buf);
            },
            .EXECUTE_ORDER => {
                _ = processor(itch.ItchMsgExecuteOrder, buflen, itch.netlen(.EXECUTE_ORDER)).read_from(&buf);
            },
            .EXECUTE_ORDER_WITH_PRICE => {
                _ = processor(itch.ItchMsgExecuteOrderWithPrice, buflen, itch.netlen(.EXECUTE_ORDER_WITH_PRICE)).read_from(&buf);
            },
            .REDUCE_ORDER => {
                _ = processor(itch.ItchMsgReduceOrder, buflen, itch.netlen(.REDUCE_ORDER)).read_from(&buf);
            },
            .DELETE_ORDER => {
                _ = processor(itch.ItchMsgDeleteOrder, buflen, itch.netlen(.DELETE_ORDER)).read_from(&buf);
            },
            .REPLACE_ORDER => {
                _ = processor(itch.ItchMsgReplaceOrder, buflen, itch.netlen(.REPLACE_ORDER)).read_from(&buf);
            },
        }
    }
    const end_time = time.nanoTimestamp();
    const nanos = end_time - start_time;
    const mean_time = @as(f64, @floatFromInt(nanos)) / @as(f64, @floatFromInt(num_packets));
    print("{} packets in {} nanos, {} nanos per packet\n", .{ num_packets, nanos, mean_time });
}

test {
    std.testing.refAllDecls(@This());
}

test "simple test" {
    try std.testing.expect(true);
}
