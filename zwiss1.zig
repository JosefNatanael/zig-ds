//! initial implementation of a basic swiss table, not a lot of bit hacks
const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;
const Wyhash = std.hash.Wyhash;
const meta = std.meta;
const Allocator = std.mem.Allocator;

// hash: hash1 ++ hash2
// hash1: 57 bits, position in array
// hash2: 7 bits, metadata

// Backing Array:
// Capacity should be a number 2^n - 1, e.g. 15, 31, ...
// struct {
//   Ctrl[capacity],
//   Ctrl sentinel,
//   padding, (to align with the values in slots)
//   Slots[capacity]
// };

const group_width = 16;
const log_group_width = 4;
const hash1 = u64;
const hash2 = u8;

const IndexFoundPair = struct { index: u64, found: bool };

// ** helpers
pub inline fn toi8(a: anytype) i8 {
    return @bitCast(@as(u8, a));
}

/// sets ctrl to {empty, ..., empty, sentinel}, marking the array as deleted
pub inline fn resetCtrl(capacity: u64, ctrl: []i8) void {
    const slice = ctrl[0..capacity];
    @memset(slice, Ctrl.empty);
    ctrl[capacity] = Ctrl.sentinel;
}

const BitMask = struct {
    mask: u16,

    const Self = @This();

    pub fn init(mask: u16) BitMask {
        return .{ .mask = mask };
    }

    /// true if mask still non zero, false if mask is zero
    /// bit: the position of the lowest set bit
    pub fn next(self: *Self, bit: *u32) bool {
        if (self.mask == 0) return false;
        bit.* = @ctz(self.mask);
        self.mask = self.mask & (self.mask - 1);
        return true;
    }
};

const Ctrl = struct {
    const empty: i8 = -128;
    const deleted: i8 = -2;
    const sentinel: i8 = -1;

    value: i8,

    pub fn init(value: anytype) Ctrl {
        return .{ .value = toi8(value) };
    }

    pub inline fn initSentinel() Ctrl {
        return .{ .value = Ctrl.sentinel };
    }

    pub inline fn initEmpty() Ctrl {
        return .{ .value = Ctrl.empty };
    }
};

const Group = struct {
    const GroupT = @Vector(group_width, i8);
    ctrl: GroupT = undefined,

    pub fn init(pos: *[group_width]Ctrl) Group {
        // tries to _mm_loadu_si128((Group*)pos), which is an unaligned load of an i128
        var g: Group = .{};
        var i: u32 = 0;
        while (i < group_width) : (i += 1) {
            g.ctrl[i] = pos[i].value;
        }
        return g;
    }

    /// bitmask representing the positions of slots that match hash
    pub fn match(self: *Group, hash: hash2) BitMask {
        const a: GroupT = @splat(@bitCast(hash));
        const b: @Vector(group_width, bool) = a == self.ctrl;
        const c: u16 = @bitCast(b);
        return BitMask.init(c);
    }

    /// bitmask representing the positions of slots that is empty
    pub fn matchEmpty(self: *Group) BitMask {
        return self.match(@bitCast(Ctrl.empty));
    }
};

/// used to initialize an empty map
fn emptyGroup() *[group_width]Ctrl {
    const static = struct {
        var g: [group_width]Ctrl = [_]Ctrl{Ctrl.initSentinel()} ++ [_]Ctrl{Ctrl.initEmpty()} ** (group_width - 1);
    };
    return &static.g;
}

pub fn HashMap(
    comptime Key: type,
    comptime Value: type,
    comptime HashFn: fn (Key) u64,
    comptime EqlFn: fn (Key, Key) bool,
) type {
    return struct {
        const Self = @This();

        ctrl: [*]Ctrl, // there should be capacity + 1 bytes here
        slots: ?[*]Value, // there should be capacity slots here
        size: u64,
        capacity: u64,
        allocator: Allocator,

        pub fn init(capacity: u64, allocator: Allocator) !Self {
            const normalized_cap = normalizeCapacity(capacity);
            const slot_size = @sizeOf(Value);
            const slot_align = @alignOf(Value);
            const to_allocate = allocSize(normalized_cap, slot_size, slot_align);
            const offset = slotOffset(normalized_cap, slot_align);
            var allocated = try allocator.alloc(i8, to_allocate);
            resetCtrl(normalized_cap, allocated);
            return .{
                .ctrl = @ptrCast(allocated.ptr),
                .slots = @ptrCast(@alignCast(allocated.ptr + offset)),
                .size = 0,
                .capacity = normalized_cap,
                .allocator = allocator,
            };
        }

        pub fn initZero(allocator: Allocator) !Self {
            return .{
                .ctrl = emptyGroup(),
                .slots = null,
                .size = 0,
                .capacity = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.capacity == 0) {
                return;
            }
            const slot_size = @sizeOf(Value);
            const slot_align = @alignOf(Value);
            const allocated = allocSize(self.capacity, slot_size, slot_align);
            // https://ziggit.dev/t/how-to-go-from-extern-pointer-to-slice/178/1
            const start: [*]u8 = @ptrCast(self.ctrl);
            const slice = start[0..allocated];
            self.allocator.free(slice);
        }

        /// capacity is valid if it is 2^m -1 and non zero
        inline fn isValidCapacity(n: u64) bool {
            return ((n + 1) & n) == 0 and n > 0;
        }

        /// converts n into the next valid capacity
        inline fn normalizeCapacity(n: u64) u64 {
            if (n > 0) {
                const maxU64: u64 = std.math.maxInt(u64);
                const leadingZeroes: u64 = @clz(n);
                // https://github.com/ziglang/zig/issues/7605
                return maxU64 >> @intCast(leadingZeroes);
            }
            return 1;
        }

        /// returns the offset of the slots into the allocated block
        inline fn slotOffset(capacity: u64, slot_align: u64) u64 {
            assert(isValidCapacity(capacity));
            const num_ctrl_bytes = capacity + 1;
            return (num_ctrl_bytes + slot_align - 1) & (~slot_align + 1);
        }

        /// computes the total size of the backing array
        inline fn allocSize(capacity: u64, slot_size: u64, slot_align: u64) u64 {
            return slotOffset(capacity, slot_align) + capacity * slot_size;
        }

        /// performs an insert
        fn insert(self: *Self, key: Key) void {
            const hash = HashFn(key);
            const h1: hash1 = getHash1(hash);
            const h2: hash2 = getHash2(hash);
            const num_groups = (self.capacity + 1) >> log_group_width; // (cap + 1) / 16, always a power of 2
            // todo: check if table is full or not
            var group_idx = h1 & (num_groups - 1); // h1 mod num_groups
            while (true) {
                const group_pos: [*]Ctrl = self.ctrl + group_idx * group_width;
                var group = Group.init(@ptrCast(group_pos));
                var empty_matches: BitMask = group.matchEmpty();
                var i: u32 = undefined;
                while (empty_matches.next(&i)) {
                    const slot_idx = i + group_idx * group_width;
                    self.ctrl[i] = Ctrl.init(h2);
                    self.slots.?[slot_idx] = key;
                    self.size += 1;
                    return;
                }
                group_idx = (group_idx + 1) & (num_groups - 1);
            }
        }

        /// performs a table find
        fn find(self: *Self, key: Key) IndexFoundPair {
            const hash = HashFn(key);
            const h1: hash1 = getHash1(hash);
            const h2: hash2 = getHash2(hash);
            const num_groups = (self.capacity + 1) >> log_group_width; // (cap + 1) / 16, always a power of 2
            var group_idx = h1 & (num_groups - 1); // h1 mod num_groups
            while (true) {
                const group_pos: [*]Ctrl = self.ctrl + group_idx * group_width;
                var group = Group.init(@ptrCast(group_pos));
                var matches: BitMask = group.match(h2);
                var i: u32 = undefined;
                while (matches.next(&i)) {
                    const idx = i + group_idx * group_width;
                    if (EqlFn(key, self.slots.?[idx])) {
                        // todo: mark this branch likely
                        return IndexFoundPair{ .index = idx, .found = true };
                    }
                }
                if (group.matchEmpty().mask > 0) {
                    // key insight: the table must always have at least one empty element,
                    // otherwise it will loop forever
                    // todo: mark this branch likely
                    return IndexFoundPair{ .index = 0, .found = false };
                }
                // linearly probe to the next group
                group_idx = (group_idx + 1) & (num_groups - 1);
            }
        }

        inline fn getHash1(hash: u64) hash1 {
            return hash >> 7;
        }

        inline fn getHash2(hash: u64) hash2 {
            return @truncate(hash & 0x7f);
        }

        test "correct allocation" {
            try expect(!isValidCapacity(0));
            try expect(isValidCapacity(1));
            try expect(!isValidCapacity(2));
            try expect(isValidCapacity(3));
            try expect(isValidCapacity(15));
            try expect(!isValidCapacity(16));
            try expect(!isValidCapacity(17));

            try expect(normalizeCapacity(1) == 1);
            try expect(normalizeCapacity(2) == 3);
            try expect(normalizeCapacity(4) == 7);
            try expect(normalizeCapacity(10) == 15);
            try expect(normalizeCapacity(11) == 15);
            try expect(normalizeCapacity(12) == 15);
            try expect(normalizeCapacity(13) == 15);
            try expect(normalizeCapacity(14) == 15);
            try expect(normalizeCapacity(15) == 15);
            try expect(normalizeCapacity(16) == 31);
        }
    };
}

fn someHashFunction(key: u32) u64 {
    return key;
}

fn someEqlFunction(a: u32, b: u32) bool {
    return a == b;
}

test "empty hashset initialization" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).initZero(allocator);
    defer set.deinit();
    const size1 = @sizeOf(@TypeOf(set.ctrl));
    const size2 = @sizeOf(@TypeOf(set.slots));
    try expect(size1 == 8);
    try expect(size2 == 8);
    try expect(set.capacity == 0);
    // for (0..15) |i| {
    //     try expect(set.ctrl[i].value == Ctrl.empty);
    // }
    // try expect(set.ctrl[15].value == Ctrl.sentinel);
}

test "small size hashset" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(10, allocator);
    defer set.deinit();
    try expect(set.capacity == 15);
    for (0..15) |i| {
        try expect(set.ctrl[i].value == Ctrl.empty);
    }
    try expect(set.ctrl[15].value == Ctrl.sentinel);
}

test "smaller size hashset" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(2, allocator);
    defer set.deinit();
    try expect(set.capacity == 3);
    for (0..3) |i| {
        try expect(set.ctrl[i].value == Ctrl.empty);
    }
    try expect(set.ctrl[3].value == Ctrl.sentinel);
}

test "nonempty hashset initialization" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(32, allocator);
    defer set.deinit();
    const setSize = @sizeOf(@TypeOf(set));
    try expect(@sizeOf(Allocator) == 16);
    try expect(setSize == 48);
    try expect(set.capacity == 63);
    for (0..63) |i| {
        try expect(set.ctrl[i].value == Ctrl.empty);
    }
    try expect(set.ctrl[63].value == Ctrl.sentinel);
}

test "basic find not found" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(32, allocator);
    defer set.deinit();
    var result = set.find(69);
    try expect(!result.found);
}

test "test small set finds" {
    const allocator = std.testing.allocator;
    var empty_set = try HashMap(u32, u32, someHashFunction, someEqlFunction).initZero(allocator);
    defer empty_set.deinit();
    var result = empty_set.find(69);
    try expect(!result.found);

    var small_set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(7, allocator);
    defer small_set.deinit();
    result = small_set.find(69);
    try expect(!result.found);
}

test "basic insertion test" {
    const allocator = std.testing.allocator;
    var set = try HashMap(u32, u32, someHashFunction, someEqlFunction).init(32, allocator);
    defer set.deinit();
    var result = set.find(69);
    try expect(!result.found);
    set.insert(69);
    result = set.find(69);
    try expect(result.found);
    set.insert(70);
    result = set.find(70);
    try expect(result.found);
}

test "alignment check" {
    const ItemA = struct {
        val1: u64,
        val2: u32,
    };

    const ItemB = struct {
        val1: u64,
        val2: u64,
    };

    const ItemC = struct {
        val1: u64,
        val2: bool,
    };

    const ItemD = struct {
        val1: u64,
        val2: bool,
        val3: bool,
    };

    const ItemE = struct {
        val1: bool,
        val2: u64,
        val3: bool,
    };

    const ItemF = packed struct {
        val1: bool,
        val2: u64,
        val3: bool,
    };

    const ItemG = extern struct {
        val1: bool,
        val2: u64,
        val3: bool,
    };

    try expect(@sizeOf(ItemA) == 16);
    try expect(@sizeOf(ItemB) == 16);
    try expect(@sizeOf(ItemC) == 16);
    try expect(@sizeOf(ItemD) == 16);
    try expect(@sizeOf(ItemE) == 16);
    try expect(@sizeOf(ItemF) == 16); // this is misleading
    try expect(@sizeOf(ItemG) == 24);

    try expect(@alignOf(ItemA) == 8);
    try expect(@alignOf(ItemB) == 8);
    try expect(@alignOf(ItemC) == 8);
    try expect(@alignOf(ItemD) == 8);
    try expect(@alignOf(ItemE) == 8);
    try expect(@alignOf(ItemF) == 8);
    try expect(@alignOf(ItemG) == 8);
}
