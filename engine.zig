//! Price-Time Matching Engine
const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

const Price = u64;
const Qty = u64;
const TraderId = [4]u8;
const Symbol = [16]u8;
const OrderId = u64; // monotonically increasing order id

/// Limit Order Book: Flat linear array of price points, indexed by the numeric price value.
/// A slot in the array represents an instance of struct PricePoint.
/// PricePoint maintains a list of open buy/sell orders at the respective price.
/// An open order is represented by an instance of struct OrderBookEntry.
pub fn OrderBook(
    comptime MaxPrice: comptime_int,
    comptime MinPrice: comptime_int,
    comptime MaxNumOrders: comptime_int,
    comptime BuyTradeCallback: fn (Trade) void,
    comptime SellTradeCallback: fn (Trade) void,
) type {
    return struct {
        const Self = @This();

        pricePoints: [*]PricePoint,
        bookEntries: [*]OrderBookEntry,
        allocator: Allocator,
        curOrderId: OrderId = 0,
        askMin: u64 = MaxPrice + 1,
        bidMax: u64 = MinPrice - 1,

        pub fn init(allocator: Allocator) !Self {
            const to_alloc_pp = @sizeOf(PricePoint) * (MaxPrice + 1);
            const to_alloc_be = @sizeOf(OrderBookEntry) * MaxNumOrders;
            const allocate1 = try allocator.alloc(u8, to_alloc_pp);
            const allocate2 = try allocator.alloc(u8, to_alloc_be);
            @memset(allocate1, 0);
            @memset(allocate2, 0);

            return .{
                .pricePoints = @ptrCast(@alignCast(allocate1)),
                .bookEntries = @ptrCast(@alignCast(allocate2)),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            const slice1 = self.pricePoints[0 .. MaxPrice + 1];
            const slice2 = self.bookEntries[0..MaxNumOrders];
            self.allocator.free(slice1);
            self.allocator.free(slice2);
        }

        pub fn limitOrder(self: *Self, order: Order) OrderId {
            return if (order.isBuy) self.processBuyOrder(order) else self.processSellOrder(order);
        }

        fn processBuyOrder(self: *Self, order: Order) OrderId {
            const price = order.price;
            var qty = order.qty;
            // look for open sell orders that cross with the incoming order
            while (price >= self.askMin) {
                var ppEntry: *PricePoint = &self.pricePoints[self.askMin];
                var bookEntry: ?*OrderBookEntry = ppEntry.listHead;
                while (bookEntry != null) {
                    if (bookEntry.?.qty < qty) {
                        reportTrade(order.symbol, order.trader, bookEntry.?.trader, price, bookEntry.?.qty);
                        qty -= bookEntry.?.qty;
                        bookEntry = bookEntry.?.next;
                    } else {
                        reportTrade(order.symbol, order.trader, bookEntry.?.trader, price, qty);
                        if (bookEntry.?.qty > qty) {
                            bookEntry.?.qty -= qty;
                        } else {
                            bookEntry = bookEntry.?.next;
                        }
                        ppEntry.listHead = bookEntry;
                        self.curOrderId += 1;
                        return self.curOrderId;
                    }
                }

                // we have exhausted all orders at the askMin price point, move on to the next price level
                ppEntry.listHead = null;
                // ppEntry += 1;
                self.askMin += 1;
            }
            // if we arrive here, it means that we are inserting an order into the orderbook
            self.curOrderId += 1;
            const entry: *OrderBookEntry = &self.bookEntries[self.curOrderId];
            entry.qty = qty;
            inline for (order.trader, 0..) |value, i| {
                entry.trader[i] = value;
            }
            insertOrder(&self.pricePoints[price], entry);
            if (self.bidMax < price) {
                self.bidMax = price;
            }
            return self.curOrderId;
        }

        fn processSellOrder(self: *Self, order: Order) OrderId {
            const price = order.price;
            var qty = order.qty;
            // look for open buy orders that cross with the incoming order
            while (price <= self.bidMax) {
                var ppEntry: *PricePoint = &self.pricePoints[self.bidMax];
                var bookEntry: ?*OrderBookEntry = ppEntry.listHead;
                while (bookEntry != null) {
                    if (bookEntry.?.qty < qty) {
                        reportTrade(order.symbol, order.trader, bookEntry.?.trader, price, bookEntry.?.qty);
                        qty -= bookEntry.?.qty;
                        bookEntry = bookEntry.?.next;
                    } else {
                        reportTrade(order.symbol, order.trader, bookEntry.?.trader, price, qty);
                        if (bookEntry.?.qty > qty) {
                            bookEntry.?.qty -= qty;
                        } else {
                            bookEntry = bookEntry.?.next;
                        }
                        ppEntry.listHead = bookEntry;
                        self.curOrderId += 1;
                        return self.curOrderId;
                    }
                }

                // we have exhausted all orders at the bidMax price point, move on to the next price level
                ppEntry.listHead = null;
                // ppEntry -= 1;
                self.bidMax -= 1;
            }
            // if we arrive here, it means that we are inserting an order into the orderbook
            self.curOrderId += 1;
            const entry: *OrderBookEntry = &self.bookEntries[self.curOrderId];
            entry.qty = qty;
            inline for (order.trader, 0..) |value, i| {
                entry.trader[i] = value;
            }
            insertOrder(&self.pricePoints[price], entry);
            if (self.askMin > price) {
                self.askMin = price;
            }
            return self.curOrderId;
        }

        pub fn cancelOrder(self: *Self, orderId: OrderId) void {
            self.bookEntries[orderId].qty = 0;
        }

        fn insertOrder(ppEntry: *PricePoint, obEntry: *OrderBookEntry) void {
            if (ppEntry.listHead != null) {
                ppEntry.listTail.?.next = obEntry;
            } else {
                ppEntry.listHead = obEntry;
            }
            ppEntry.listTail = obEntry;
        }

        fn reportTrade(symbol: Symbol, buyer: TraderId, seller: TraderId, price: Price, qty: Qty) void {
            if (qty == 0) {
                return; // skip cancelled orders
            }
            var trade: Trade = undefined;
            inline for (symbol, 0..) |value, i| {
                trade.symbol[i] = value;
            }
            trade.price = price;
            trade.qty = qty;

            // report to buy side
            trade.isBuy = true;
            inline for (buyer, 0..) |value, i| {
                trade.trader[i] = value;
            }
            BuyTradeCallback(trade);

            // report to sell side
            trade.isBuy = false;
            inline for (seller, 0..) |value, i| {
                trade.trader[i] = value;
            }
            SellTradeCallback(trade);
        }
    };
}

const OrderBookEntry = struct {
    qty: Qty,
    next: ?*OrderBookEntry = null,
    trader: TraderId,
};

const PricePoint = struct {
    listHead: ?*OrderBookEntry = null,
    listTail: ?*OrderBookEntry = null,
};

const Trade = struct {
    symbol: Symbol,
    price: Price,
    qty: Qty,
    trader: TraderId,
    isBuy: bool,
};

const Order = struct {
    symbol: Symbol,
    price: Price,
    qty: Qty,
    trader: TraderId,
    isBuy: bool,
};

// TradeCallback: fn (Trade) void,
fn sampleCallback(trade: Trade) void {
    print("{any}\n", .{trade});
}

test "basic tests" {
    const allocator = std.testing.allocator;
    const maxPrice = 1_000_000;
    const minPrice = 1;
    const maxNumOrders = 100_000;
    var orderBook = try OrderBook(maxPrice, minPrice, maxNumOrders, sampleCallback, sampleCallback).init(allocator);
    defer orderBook.deinit();

    // add liquidity
    // buy: (10, 1000), (9, 1001), ... (1, 1009)
    // sell: (1, 1011), (2, 1012), ... (10, 1020)
    const symbol_ = "somesymbol      ";
    const symbol: *[16]u8 = @ptrCast(@constCast(symbol_));
    const trader1_ = "tst1";
    const trader1: *[4]u8 = @ptrCast(@constCast(trader1_));
    const trader2_ = "tst2";
    const trader2: *[4]u8 = @ptrCast(@constCast(trader2_));
    for (1..11) |size| {
        var oid = orderBook.limitOrder(Order{ .qty = size, .price = 1010 - size, .symbol = symbol.*, .isBuy = true, .trader = trader1.* });
        try expect(oid == size * 2 - 1);
        oid = orderBook.limitOrder(Order{ .qty = size, .price = 1010 + size, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
        try expect(oid == size * 2);
    }

    // take some liquidity
    // sell: (4, 1008)
    _ = orderBook.limitOrder(Order{ .qty = 4, .price = 1008, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
    try expect(orderBook.askMin == 1008);
}

test "more tests" {
    const allocator = std.testing.allocator;
    const maxPrice = 1_000_000;
    const minPrice = 1;
    const maxNumOrders = 100_000;
    var orderBook = try OrderBook(maxPrice, minPrice, maxNumOrders, sampleCallback, sampleCallback).init(allocator);
    defer orderBook.deinit();

    // add liquidity
    // buy: (10, 1000), (9, 1001), ... (1, 1009)
    // sell: (1, 1011), (2, 1012), ... (10, 1020)
    const symbol_ = "somesymbol      ";
    const symbol: *[16]u8 = @ptrCast(@constCast(symbol_));
    const trader1_ = "tst1";
    const trader1: *[4]u8 = @ptrCast(@constCast(trader1_));
    const trader2_ = "tst2";
    const trader2: *[4]u8 = @ptrCast(@constCast(trader2_));
    for (1..11) |size| {
        _ = orderBook.limitOrder(Order{ .qty = size, .price = 1010 - size, .symbol = symbol.*, .isBuy = true, .trader = trader1.* });
        _ = orderBook.limitOrder(Order{ .qty = size, .price = 1010 + size, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
    }
    // cancel all orders, order ids are going to be [1..20]
    for (1..21) |id| {
        orderBook.cancelOrder(id);
    }

    // take some liquidity
    // sell: (4, 1008)
    _ = orderBook.limitOrder(Order{ .qty = 4, .price = 1008, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
    try expect(orderBook.askMin == 1008);
}

test "test partial fill top of book" {
    const allocator = std.testing.allocator;
    const maxPrice = 1_000_000;
    const minPrice = 1;
    const maxNumOrders = 100_000;
    var orderBook = try OrderBook(maxPrice, minPrice, maxNumOrders, sampleCallback, sampleCallback).init(allocator);
    defer orderBook.deinit();

    // add liquidity
    // buy: (10, 1000), (9, 1001), ... (1, 1009)
    // sell: (1, 1011), (2, 1012), ... (10, 1020)
    const symbol_ = "somesymbol      ";
    const symbol: *[16]u8 = @ptrCast(@constCast(symbol_));
    const trader1_ = "tst1";
    const trader1: *[4]u8 = @ptrCast(@constCast(trader1_));
    const trader2_ = "tst2";
    const trader2: *[4]u8 = @ptrCast(@constCast(trader2_));
    for (1..11) |size| {
        _ = orderBook.limitOrder(Order{ .qty = size * 10, .price = 1010 - size, .symbol = symbol.*, .isBuy = true, .trader = trader1.* });
        _ = orderBook.limitOrder(Order{ .qty = size * 10, .price = 1010 + size, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
    }

    // take some liquidity
    // sell: (4, 1008)
    _ = orderBook.limitOrder(Order{ .qty = 1, .price = 1008, .symbol = symbol.*, .isBuy = false, .trader = trader2.* });
    try expect(orderBook.askMin == 1011);

    _ = orderBook.limitOrder(Order{ .qty = 1, .price = 1015, .symbol = symbol.*, .isBuy = true, .trader = trader1.* });
    try expect(orderBook.bidMax == 1009);
}
