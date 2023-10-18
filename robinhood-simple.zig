// https://programming.guide/robin-hood-hashing.html
//
// stupid naive implementation of robin hood hashing
// only too try the robin hood algorithm
// tombstones: fast for removal, slower for lookup/insertion
// backshift: slower for removal, faster for lookup/insertion

const std = @import("std");
const expect = std.testing.expect;
const print = std.debug.print;
const Wyhash = std.hash.Wyhash;
const capacity: comptime_int = 8;

const Entry = struct {
    key: []const u8,
    value: i32,
};

const Metadata = struct {
    state: i8,
};

const DumbRobinHoodMap = struct {
    // -1 is empty, 0.. is the probe sequence length
    metadata: [capacity]i8 = [_]i8{-1} ** capacity,
    data: [capacity]Entry = undefined,

    const Self = @This();

    fn insert(self: *Self, entry: Entry) void {
        var tmp: Entry = entry;
        const hash_val = hash(entry.key);
        const index = hash_val % capacity;
        var insert_index = index;

        var curr_psl: i8 = 0;
        while (true) {
            const meta = self.metadata[insert_index];
            // found an empty spot
            if (meta == -1) {
                self.metadata[insert_index] = curr_psl;
                self.data[insert_index] = tmp;
                return;
            }
            // check if it is the same key
            if (eql(self.data[insert_index].key, tmp.key)) {
                self.data[insert_index] = tmp;
                return;
            }
            // steals the spot from the rich for the poor
            if (meta > curr_psl) {
                self.metadata[insert_index] = curr_psl;
                curr_psl = meta;
                tmp = self.data[insert_index];
                self.data[insert_index] = entry;
            }

            curr_psl += 1;
            insert_index = (insert_index + 1) % capacity;
            if (insert_index == index) {
                return;
            }
        }
    }

    fn lookup(self: *Self, key: []const u8) ?i32 {
        const hash_val = hash(key);
        const index = hash_val % capacity;
        var curr_idx = index;
        var curr_psl: i8 = 0;
        while (true) {
            const meta = self.metadata[curr_idx];
            if (meta == -1 or meta > curr_psl) {
                return null;
            }
            const data = self.data[curr_idx];
            if (eql(data.key, key)) {
                return data.value;
            }
            curr_psl += 1;
            curr_idx = (curr_idx + 1) % capacity;
            if (curr_idx == index) {
                return null;
            }
        }

        return null;
    }

    fn remove(self: *Self, key: []const u8) ?void {
        const hash_val = hash(key);
        const index = hash_val % capacity;
        var curr_idx = index;
        var curr_psl: i8 = 0;
        while (true) {
            const meta = self.metadata[curr_idx];
            if (meta == -1 or meta > curr_psl) {
                return null;
            }
            const data = self.data[curr_idx];
            if (eql(data.key, key)) {
                break;
            }
            curr_psl += 1;
            curr_idx = (curr_idx + 1) % capacity;
            if (curr_idx == index) {
                return null;
            }
        }
        // remove and backshift
        self.metadata[curr_idx] = -1;
        curr_idx = (curr_idx + 1) % capacity;
        while (true) {
            const meta = self.metadata[curr_idx];
            if (meta == 0) {
                return;
            }
            const prev_idx = (curr_idx - 1) % capacity;
            _ = prev_idx;
        }

        return;
    }

    fn hash(key: []const u8) u64 {
        return Wyhash.hash(0, key);
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

test "basic insertion" {
    var map = DumbRobinHoodMap{};

    map.insert(.{ .key = &[_]u8{ 'j', 'o' }, .value = 20 });
    map.insert(.{ .key = &[_]u8{ 'j', 'o' }, .value = 21 });
    map.insert(.{ .key = "jo", .value = 22 });

    print("metadata: {any}\n", .{map.metadata});
    print("data: {any}\n", .{map.data});

    map.insert(.{ .key = "jo", .value = 22 });
    map.insert(.{ .key = "sef", .value = 23 });
    map.insert(.{ .key = "nata", .value = 24 });
    map.insert(.{ .key = "nael", .value = 25 });

    map.insert(.{ .key = "hi", .value = 26 });
    map.insert(.{ .key = "hello", .value = 27 });
    map.insert(.{ .key = "hihi", .value = 28 });
    map.insert(.{ .key = "hehe", .value = 29 });

    print("metadata: {any}\n", .{map.metadata});
    print("data: {any}\n", .{map.data});
}

test "basic lookup" {
    var map = DumbRobinHoodMap{};
    map.insert(.{ .key = "josef", .value = 69 });
    const res = map.lookup("josef") orelse 70;
    try expect(res == 69);
}
