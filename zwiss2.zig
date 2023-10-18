const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;
const Wyhash = std.hash.Wyhash;
const meta = std.meta;

// ** helpers
pub inline fn toi8(a: anytype) i8 {
    return @bitCast(@as(u8, a));
}

// ** table configs
const num_groups = 8;
const mask_num_groups = num_groups - 1;
const group_width = 16;
const num_cloned_bytes = group_width - 1;

// ** capacity checks
pub inline fn isValidCapacity(n: u64) bool {
    // 2^m - 1 and non zero
    return ((n + 1) & n) == 0 and n > 0;
}

pub inline fn randomSeed() u64 {
    // XOR'ing the address of a thread local value with a perpetually incrementing value
    const static = struct {
        threadlocal var counter: u64 = 0;
    };
    static.counter += 1;
    return static.counter ^ @intFromPtr(&static.counter);
}

pub noinline fn shouldInsertBackwards(hash: u64, ctrl: *Ctrl) bool {
    // mixes a randomly generated per-process seed with 'hash' and 'ctrl' to
    // randomize insertion order within groups
    return (H1(hash, ctrl) ^ randomSeed()) % 13 > 6;
}

pub noinline fn convertDeletedToEmptyAndFullToDeleted(ctrl: [*]Ctrl, capacity: u64) void {
    // deleted -> empty
    // empty -> empty
    // _ -> deleted
    //
    // ctrl[capacity] == sentinel
    // ctrl[i] != sentinel for i < capacity
    assert(ctrl[capacity] == Ctrl.sentinel);
    assert(isValidCapacity(capacity));
    var pos = ctrl;
    while (pos < ctrl + capacity) {
        Group.init(pos).convertSpecialToEmptyAndFullToDeleted(pos);
        pos += group_width;
    }

    // we want to copy num_cloned_bytes from ctrl to ctrl + capacity + 1
    // check: will tmp ever overlap with ctrl + capacity + 1, i.e., capacity < 15?
    var tmp: *[num_cloned_bytes]Ctrl = @ptrCast(ctrl);
    @memcpy(ctrl + capacity + 1, tmp);

    ctrl[capacity] = Ctrl.sentinel;
}

pub inline fn resetCtrl(capacity: u64, ctrl: [*]Ctrl) void {
    // sets ctrl to {empty, ..., empty, sentinel}, marking the array as deleted
    var tmp: *[capacity + 1 + num_cloned_bytes]Ctrl = @ptrCast(ctrl);
    @memset(tmp, Ctrl.empty);
}

pub inline fn setCtrl(i: u64, h: Ctrl, capacity: u64, ctrl: [*]Ctrl) void {
    // sets ctrl[i] = h
    // will mirror the value to the cloned tail if necessary
    // if i < width, it will write to the cloned bytes as well as the real byte
    // else, it will store h twice
    var mirrored_i: u64 = ((i - num_cloned_bytes) & capacity) + (num_cloned_bytes & capacity);
    ctrl[i] = h;
    ctrl[mirrored_i] = h;
}

pub inline fn normalizeCapacity(n: u64) u64 {
    // converts n into the next valid capacity
    if (n > 0) {
        return std.math.maxInt(u64) >> @clz(n);
    }
    return 1;
}

pub inline fn capacityToGrowth(capacity: u64) u64 {
    // we use 7/8 as max load factor
    // for capacity + 1 >= width, grow is 7/8 x capacity
    // for capacity + 1 < width, growth == capacity (no need to probe, whole table fits in 1 group)
    assert(isValidCapacity(capacity));
    if (group_width == 8 and capacity == 7) {
        return 6;
    }
    return capacity - capacity / 8;
}

pub inline fn growToLowerboundCapacity(growth: u64) u64 {
    // unapplies the load factor to find how large the capacity should be to stay within
    // the load factor
    // result may not be a valid capacity, therefore normalizeCapacity() may be needed

    if (group_width == 8 and growth == 7) {
        return 8;
    }
    // x+(x-1)/7
    return growth + @as(u64, (@as(i64, growth) - 1) / 7);
}

pub inline fn slotOffset(capacity: u64, slot_align: u64) u64 {
    // returns the offset of the slots into the allocated block
    // allocated block: capacity + 1 + num_cloned_bytes + padding + slots...
    assert(isValidCapacity(capacity));
    const num_control_bytes = capacity + 1 + num_cloned_bytes;
    return (num_control_bytes + slot_align - 1) & (~slot_align + 1);
}

pub inline fn allocSize(capacity: u64, slot_size: u64, slot_align: u64) u64 {
    // computes the total size of the backing array
    return slotOffset(capacity, slot_align) + capacity * slot_size;
}

pub inline fn isSmall(capacity: u64) bool {
    // small if table entirely fits into a probing group, i.e. has a capacity
    // equal ot the size of a Group
    return capacity < group_width - 1;
}

// ** aliases
const hash1 = u64;
const hash2 = u8;

/// Conceptual structure of the SwissTable's backing array
/// struct BackingArray {
///     Ctrl ctrl[capacity];                            // control bytes
///     Ctrl sentinel;                                  // used by iterators when to stop
///     Ctrl clones[16 - 1]                             // copy of the first 16 - 1 elements of ctrl
///     char padding;                                   // padding equal to alignof(slot_type)
///     char slots[capacity * sizeof(slot_type)];       // actual slot data
/// };
const RawTable = struct {
    // points to these number of Ctrl bytes: capacity + 1 + num_clone_bytes
    ctrl: [*]Ctrl,
    // located at slotOffset(...) bytes after ctrl, may be null for empty tables
    slots: [*]u8,
    // number of filled slots
    size: u64,
    // total number of available slots
    capacity: u64,
    // number of slots we can still fill before a rehash, check capacityToGrowth(...)
    growth_left: u64,
};

///    empty: 1 0 0 0 0 0 0 0 (i8 = -128, u8 = 128)
///  deleted: 1 1 1 1 1 1 1 0 (i8 = -2, u8 = 254)
///     full: 0 h h h h h h h
/// sentinel: 1 1 1 1 1 1 1 1 (i8 = -1, u8 = 255)
const Ctrl = struct {
    const empty: i8 = -128;
    const deleted: i8 = -2;
    const sentinel: i8 = -1;

    value: i8,

    pub inline fn from(val: i8) Ctrl {
        return .{ .value = val };
    }

    pub inline fn initEmpty() Ctrl {
        return .{ .value = Ctrl.empty };
    }

    pub inline fn initDeleted() Ctrl {
        return .{ .value = Ctrl.deleted };
    }

    pub inline fn initSentinel() Ctrl {
        return .{ .value = Ctrl.sentinel };
    }

    pub inline fn isEmpty(c: Ctrl) bool {
        return c.value == Ctrl.empty;
    }

    pub inline fn isFull(c: Ctrl) bool {
        return c.value >= 0;
    }

    pub inline fn isDeleted(c: Ctrl) bool {
        return c.value == Ctrl.deleted;
    }

    pub inline fn isEmptyOrDeleted(c: Ctrl) bool {
        return c.value < Ctrl.sentinel;
    }

    comptime {
        assert(Ctrl.empty & Ctrl.deleted & Ctrl.sentinel & toi8(0x80) != 0);
        assert(Ctrl.empty < Ctrl.sentinel and Ctrl.deleted < Ctrl.sentinel);
        assert(~Ctrl.empty & ~Ctrl.deleted & Ctrl.sentinel & toi8(0x7f) != 0);
        assert(@sizeOf(Ctrl) == 1);
        assert(@alignOf(Ctrl) == 1);
    }
};

const BitMask = struct {
    mask: u64 = undefined,
    width: u32 = undefined, // num of bits in the mask
    shift: u32 = undefined, // log_2 width of an abstract bit
};

const Group = struct {
    ctrl: @Vector(16, i8) = undefined,

    pub fn init(pos: [*]Ctrl) Group {
        // tries to do _mm_loadu_si128, which is an unaligned load of an i128
        // _mm_loadu_si128((Group*)pos);
        var g: Group = .{};
        var i: usize = 0;
        while (i < group_width) {
            g.ctrl[i] = pos[i].value;
            i += 1;
        }
        return g;
    }

    // bitmask representing the positions of slots that match hash
    pub fn match(self: *Group, hash: hash2) BitMask {
        const a: @Vector(16, i8) = @splat(@bitCast(hash));
        const b: @Vector(16, bool) = a == self.ctrl;
        const c: u16 = @bitCast(b);
        return .{ .mask = c, .width = 16, .shift = 0 };
    }

    // bitmask representing the positions of empty slots
    pub fn matchEmpty(self: *Group) BitMask {
        return self.match(@bitCast(Ctrl.empty));
    }

    // bitmask representing the positions of empty or deleted slots
    pub fn matchEmptyOrDeleted(self: *Group) BitMask {
        const special: @Vector(16, i8) = @splat(Ctrl.sentinel);
        const compared: @Vector(16, bool) = special > self.ctrl;
        const tmp: u16 = @bitCast(compared);
        return .{ .mask = tmp, .width = 16, .shift = 0 };
    }

    // returns the number of trailing empty or deleted elements in the group
    pub fn countLeadingEmptyOrDeleted(self: *Group) u32 {
        const special: @Vector(16, i8) = @splat(Ctrl.sentinel);
        const compared: @Vector(16, bool) = special > self.ctrl;
        const tmp: u16 = @bitCast(compared);
        const tmp2: u32 = tmp + 1;
        return @ctz(tmp2);
    }

    pub fn convertSpecialToEmptyAndFullToDeleted(self: *Group, dest: *[16]Ctrl) void {
        const msbs: @Vector(16, i8) = @splat(-128); // 1000_0000
        const x126: @Vector(16, i8) = @splat(126); // 0111_1110
        const zero: @Vector(16, i8) = @splat(0);
        const special_mask: @Vector(16, i8) = zero > self.ctrl;
        const res: @Vector(16, i8) = msbs | (!special_mask & x126);
        // tries to do a _mm_storeu_si128, which is an unaligned store of an i128
        // _mm_storeu_si128((Group*)dst, res);
        var i: usize = 0;
        while (i < 16) {
            dest[i] = res[i];
            i += 1;
        }
    }
};

pub inline fn hashSeed(ctrl: *Ctrl) u64 {
    return @intFromPtr(ctrl) >> 12;
}

pub inline fn H1(hash: u64, ctrl: *Ctrl) hash1 {
    return (hash >> 7) ^ hashSeed(ctrl);
}

pub inline fn H2(hash: u64) hash2 {
    return hash & 0x7f;
}

pub fn emptyGroup() *[16]Ctrl {
    const static = struct {
        var g: [16]Ctrl = [_]Ctrl{Ctrl.initSentinel()} ++ [_]Ctrl{Ctrl.initDeleted()} ** 15;
    };
    return &static.g;
}

test "Ctrl test" {
    const c1: Ctrl = Ctrl.from(-128);
    const c2: Ctrl = Ctrl.from(-2);
    const c3: Ctrl = Ctrl.from(-1);
    const c4: Ctrl = Ctrl.from(69);

    try expect(Ctrl.isEmpty(c1));
    try expect(!Ctrl.isEmpty(c2));
    try expect(!Ctrl.isEmpty(c3));
    try expect(!Ctrl.isEmpty(c4));

    try expect(!Ctrl.isFull(c1));
    try expect(!Ctrl.isFull(c2));
    try expect(!Ctrl.isFull(c3));
    try expect(Ctrl.isFull(c4));

    try expect(!Ctrl.isDeleted(c1));
    try expect(Ctrl.isDeleted(c2));
    try expect(!Ctrl.isDeleted(c3));
    try expect(!Ctrl.isDeleted(c4));

    try expect(Ctrl.isEmptyOrDeleted(c1));
    try expect(Ctrl.isEmptyOrDeleted(c2));
    try expect(!Ctrl.isEmptyOrDeleted(c3));
    try expect(!Ctrl.isEmptyOrDeleted(c4));
}

test "bitmask test" {
    try expect(@sizeOf(BitMask) == 16);
}

test "empty group" {
    var e = emptyGroup();
    var f = emptyGroup();
    try expect(e == f);
    try expect(e.*[0].value == Ctrl.sentinel);
    try expect(e.*[1].value == Ctrl.deleted);
    try expect(e.*[15].value == Ctrl.deleted);
    try expect(e.len == 16);
}

test "group match" {
    var arr: [16]Ctrl = [_]Ctrl{.{ .value = 1 }} ** 16;
    var g1 = Group.init(&arr);
    var bm1 = g1.match(1);
    print("bm1: {any}\n", .{bm1});

    var g2 = Group.init(emptyGroup());
    var bm2 = g2.matchEmpty();
    print("bm2: {any}\n", .{bm2});
}

test "Group load vector" {
    var arr = [_]Ctrl{.{ .value = 1 }} ** 16;
    const g = Group.init(&arr);
    print("g: {}\n", .{g.ctrl});
}
