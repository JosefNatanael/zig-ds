//! A super simple implementation of an early Swiss table version

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const expect = std.testing.expect;
const Wyhash = std.hash.Wyhash;
const meta = std.meta;
const Allocator = std.mem.Allocator;

// modify to change key/value type
// const Key = u32;
// const Value = u32;

// globals
const ctrl_size = 16;
const group_size = 16;
const value_size = ctrl_size * group_size;
const load_factor = 0.75;
const expand_factor = 2;

const swiss_empty = 0b1000_0000;
const swiss_deleted = 0b1111_1111;
const swiss_full_mask = 0b0111_1111;

pub fn HashMap(
    comptime Key: type,
    comptime Value: type,
) type {
    return struct {
        allocator: Allocator,
        num_groups: u64,
        pair_count: u64,
        hashFn: HashFn,
        eqlFn: EqlFn,
        groups: [*]Group,
        slots: [*]Value,

        const Self = @This();
        const swiss_128 = @Vector(ctrl_size, u8);
        const Group = struct {
            ctrl: swiss_128,
            key: Key[ctrl_size],

            pub fn match(self: *Group, h2: u8) u16 {
                const a: @Vector(16, i8) = @splat(@bitCast(h2));
                const b: @Vector(16, bool) = a == self.ctrl;
                const c: u16 = @bitCast(b);
                return c;
            }
        };
        const HashFn = fn (Key) u64;
        const EqlFn = fn (Key, Key) bool;

        pub fn init(hash: HashFn, eql: EqlFn, allocator: Allocator) !Self {
            const new_groups = try allocator.alloc(Group, group_size);
            const new_slots = try allocator.alloc(Value, group_size);
            var i = 0;
            while (i < group_size) {
                new_groups[i].ctrl = @splat(swiss_empty);
                i += 1;
            }
            return .{
                .allocator = allocator,
                .num_groups = group_size,
                .pair_count = 0,
                .hashFn = hash,
                .eqlFn = eql,
                .groups = new_groups,
                .slots = new_slots,
            };
        }

        pub fn hash1(hash: u64) u64 {
            return hash >> 7;
        }

        pub fn hash2(hash: u64) u8 {
            return hash & 0x7f;
        }

        // recycle the map by filling all controls with swiss_empty
        // and set the pair_count = 0
        // returns the available size
        pub fn clear(self: *Self) u64 {
            const tot = self.num_groups;
            var i = 0;
            while (i < tot) {
                self.groups[i].ctrl = @splat(swiss_empty);
            }
            self.pair_count = 0;
            return self.num_groups * ctrl_size;
        }

        pub fn find(self: *Self, key: Key, nomatch: Value) Value {
            const hash = self.hashFn(key);
            var group_idx = hash1(hash) % self.num_groups;
            while (true) {
                const g: Group = self.groups[group_idx];
                const matches: u16 = g.match(hash2(hash));
                var i = 0;
                while (i < ctrl_size) {
                    if (matches & (1 << i) and self.eqlFn(key, g.key[i])) {
                        return self.slots[group_idx * ctrl_size + i];
                    }
                    i += 1;
                }
                if (matches != 0b1111111111111111) {
                    return nomatch;
                }
                group_idx = (group_idx + 1) % self.num_groups;
            }
        }

        pub fn insert(self: *Self, key: Key, value: Value) u64 {
            _ = value;
            if (self.pair_count > load_factor * self.num_groups * ctrl_size) {
                return -1;
            }
            const hash = self.hashFn(key);
            var group_idx = hash1(hash) % self.num_groups;
            _ = group_idx;
        }
    };
}
