const std = @import("std");
const itch = @import("itch.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const BookId = u16;
pub const LevelId = u32;
// const Oid = itch.Oid;
pub const Oid = u32;
const Qty = itch.Qty;
const SignedPrice = i32;

pub inline fn priceIsBid(price: SignedPrice) bool {
    return price >= 0;
}

/// Level represents the quantity of orders for a given price level
pub const Level = struct {
    price: SignedPrice,
    qty: Qty,
};

/// Order represents the quantity of an order, price (via level_id) and symbol (via book_id)
pub const Order = struct {
    qty: Qty,
    level_id: LevelId,
    book_id: BookId,
};

/// PriceLevel represents a price-level pair
pub const PriceLevel = struct {
    price: SignedPrice,
    ptr: LevelId,
};

/// OidMap maps order ids to Orders
pub const OidMap = struct {
    data: ArrayList(Order),

    pub fn init(allocator: Allocator, capacity: usize) !OidMap {
        return .{ .data = try ArrayList(Order).initCapacity(allocator, capacity) };
    }

    pub fn deinit(self: *OidMap) void {
        self.data.deinit();
    }

    pub fn reserve(self: *OidMap, idx: Oid) void {
        if (idx >= self.data.items.len) {
            self.data.resize(idx + 1) catch unreachable;
        }
    }

    pub fn get(self: *OidMap, idx: Oid) *Order {
        return &self.data.items[idx];
    }
};

/// This pool represents a pool of Levels.
/// alloc to get a new place (LevelId) to store a new Level.
/// dealloc to return a Level back into the pool.
pub const Pool = struct {
    allocated: ArrayList(Level),
    free: ArrayList(LevelId),

    pub fn initCapacity(allocator: Allocator, size: usize) !Pool {
        return .{
            .allocated = try ArrayList(Level).initCapacity(allocator, size),
            .free = ArrayList(LevelId).init(allocator),
        };
    }

    pub fn deinit(self: *Pool) void {
        self.allocated.deinit();
        self.free.deinit();
    }

    pub fn get(self: *Pool, idx: LevelId) *Level {
        return &self.allocated.items[idx];
    }

    pub fn alloc(self: *Pool) LevelId {
        if (self.free.items.len == 0) {
            const size = self.allocated.items.len;
            const new_item = Level{ .price = 0, .qty = 0 };
            self.allocated.append(new_item) catch unreachable;
            return @intCast(size);
        } else {
            return self.free.pop();
        }
    }

    pub fn dealloc(self: *Pool, idx: LevelId) void {
        self.free.append(idx);
    }
};

/// An OrderBook represents a single symbol's order book.
/// The bids and asks of an order book is represented using a preallocated array of PriceLevel objects
/// The bids and asks are ordered by the price. Indexing the price gives you information about the
pub const OrderBook = struct {
    // const maxbooks: comptime_int = 1 << 14;
    // const numlevels: comptime_int = 1 << 20;
    // const LevelVector =
    const SortedLevels = ArrayList(PriceLevel);
    const Self = OrderBook;
    // var levels:
    bids: SortedLevels,
    asks: SortedLevels,
    global_levels: *Pool,

    pub fn init(allocator: Allocator, global_levels: *Pool) Self {
        return .{
            .bids = SortedLevels.init(allocator),
            .asks = SortedLevels.init(allocator),
            .global_levels = global_levels,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bids.deinit();
        self.asks.deinit();
    }

    pub fn addOrder(self: *Self, order: *Order, price: SignedPrice, qty: Qty) void {
        const sorted_levels = if (priceIsBid(price)) &self.bids else &self.asks;
        var insertion_point: i64 = @intCast(sorted_levels.items.len);
        insertion_point -= 1;
        var found = false;
        while (insertion_point > 0) : (insertion_point -= 1) {
            const cur_price = &sorted_levels.items[@intCast(insertion_point)];
            if (cur_price.price == price) {
                order.level_id = cur_price.ptr;
                found = true;
                break;
            } else if (price > cur_price.price) {
                break;
            }
        }
        if (!found) {
            order.level_id = self.global_levels.alloc();
            self.global_levels.get(order.level_id).qty = 0;
            self.global_levels.get(order.level_id).price = price;
            insertion_point += 1;
            sorted_levels.insert(@intCast(insertion_point), PriceLevel{ .price = price, .ptr = order.level_id }) catch unreachable;
        }
        self.global_levels.get(order.level_id).qty = self.global_levels.get(order.level_id).qty + qty;
    }

    pub fn deleteOrder(self: *Self, order: *Order) void {
        const level = self.global_levels.get(order.level_id);
        level.qty -= order.qty;
        if (level.qty == 0) {
            const price = level.price;
            const sorted_levels = if (priceIsBid(price)) &self.bids else &self.asks;
            var it = sorted_levels.items.len;
            while (it != 0) {
                it -= 1;
                if (sorted_levels.items[it].price == price) {
                    _ = sorted_levels.orderedRemove(it);
                    break;
                }
            }
            self.global_levels.dealoc(order.level_id);
        }
    }

    pub fn reduceOrder(self: *Self, order: *Order, qty: Qty) void {
        // const new_level_qty = self.global_levels.get(order.level_id).qty - qty;
        // self.global_levels.get(order.level_id).qty = new_level_qty;
        // const new_order_qty = order.qty - qty;
        // order.qty = new_order_qty;
        self.global_levels.get(order.level_id).qty -= qty;
        order.qty -= qty;
    }
};

pub const FullOrderBook = struct {
    const Self = FullOrderBook;
    const MAXOID = 1 << 28;
    const MAXBOOKS = 1 << 14;
    const NUMLEVELS = 1 << 20;

    books: ArrayList(OrderBook), // one order book per symbol
    oid_map: OidMap,
    levels: Pool,

    pub fn init(allocator: Allocator) !Self {
        var obj = Self{
            .books = try ArrayList(OrderBook).initCapacity(allocator, MAXBOOKS),
            .oid_map = try OidMap.init(allocator, MAXOID),
            .levels = try Pool.initCapacity(allocator, NUMLEVELS),
        };
        return obj;
    }

    pub fn deinit(self: *Self) void {
        for (self.books.items) |*book| {
            book.deinit();
        }
        self.books.deinit();
        self.oid_map.deinit();
        self.levels.deinit();
    }

    pub fn addOrder(self: *Self, oid: Oid, book_id: BookId, price: SignedPrice, qty: Qty) void {
        self.oid_map.reserve(oid);
        const order: *Order = self.oid_map.get(oid);
        order.qty = qty;
        order.book_id = book_id;
        self.books.items[book_id].addOrder(order, price, qty);
    }

    pub fn deleteOrder(self: *Self, oid: Oid) void {
        const order = self.oid_map.get(oid);
        self.books.items[order.book_id].deleteOrder(order);
    }

    pub fn reduceOrder(self: *Self, oid: Oid, qty: Qty) void {
        const order = self.oid_map.get(oid);
        self.books.items[order.book_id].reduceOrder(order, qty);
    }

    pub fn executeOrder(self: *Self, oid: Oid, qty: Qty) void {
        const order = self.oid_map.get(oid);
        if (qty == order.qty) {
            self.books.items[order.book_id].deleteOrder(order);
        } else {
            self.books.items[order.book_id].reduceOrder(qty);
        }
    }

    pub fn replaceOrder(self: *Self, old_oid: Oid, new_oid: Oid, new_qty: Qty, new_price: SignedPrice) void {
        const order = self.oid_map.get(old_oid);
        const book = &self.books.items[order.book_id];
        const levels = self.levels.get(order.level_id);
        const bid = priceIsBid(levels.price);
        book.deleteOrder(order);
        if (bid) {
            book.addOrder(new_oid, order.book_id, new_price, new_qty);
        } else {
            book.addOrder(new_oid, order.book_id, -1 * new_price, new_qty);
        }
    }
};

test "OrderBook initialization" {
    const allocator = std.testing.allocator;
    var fob = try FullOrderBook.init(allocator);

    const hihi = 1 << 14;
    const loc = &fob.levels;
    for (0..hihi) |_| {
        try fob.books.append(OrderBook.init(allocator, loc));
    }

    fob.addOrder(0, 0, 100, 1);
    fob.addOrder(1, 0, 101, 2);

    defer fob.deinit();
}
