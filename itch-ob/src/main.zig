const std = @import("std");
const itch = @import("itch.zig");
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
            _ = buf.ensure(msglen);
            const ret = Msg.parse(buf.get(0));
            buf.advance(msglen);
            return ret;
        }
    };
}

pub fn main() !void {
    const buflen = 4096;
    var buf = bufferedreader.StackBufferedReader(buflen).init();
    var num_packets: u64 = 0;
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
                _ = processor(itch.ItchMsgAddOrder, buflen, itch.netlen(.ADD_ORDER)).read_from(&buf);
            },
            .ADD_ORDER_MPID => {},
            .EXECUTE_ORDER => {},
            .EXECUTE_ORDER_WITH_PRICE => {},
            .REDUCE_ORDER => {},
            .DELETE_ORDER => {},
            .REPLACE_ORDER => {},
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}

test "simple test" {
    try std.testing.expect(true);
}
