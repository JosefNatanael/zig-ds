const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const Wyhash = std.hash.Wyhash;

// power of 2 for classic modulo tricks
const num_groups = 8;
const mask_num_groups = num_groups - 1;

// SSE2 => 8 x 16 bytes => 128 bytes SIMD
const group_width = 16;

const DumbZwissTable = struct {
    const Self = @This();

    // First bit: state (0 is full, 1 is empty/tombstone)
    // 2nd-8th bit: hash h2
    const Control = packed struct {
        state: u1 = 0,
        h2: u7 = undefined,
    };

    pub fn insert(self: *Self, key: []const u8) void {
        _ = self;
        _ = key;
    }

    pub fn fetch(self: *Self, key: []const u8) bool {
        _ = self;
        _ = key;
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        _ = self;
        _ = key;
    }

    fn groupIndex(key: []const u8) u8 {
        return hash(key) & mask_num_groups;
    }

    fn hash(key: []const u8) u64 {
        return Wyhash.hash(0, key);
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    // top 57 bits
    fn getH1(hashVal: u64) u57 {
        return @truncate(hashVal >> 7);
    }

    // bottom 7 bits
    fn getH2(hashVal: u64) u7 {
        return @truncate(hashVal & 0b111_1111);
    }
};

// A swiss table is made up of groups (number of groups is a power of 2)
// A group represents the metadata table (control) with its corresponding elements table (slot)
// A group only contains 16 items.
//
// Metadata table: 16 items, 16 bytes
// Each metadata is 1 byte = 8 bits = 1 + 7 bits (control byte)
// The first bit is the control bit (0 means full, 1 means empty/deleted/sentinel)
// The next 7 bits is "h2"
//
// Hashing:
// The result of the hash function produces a 64-bit hash value = 57 + 7 bits
// Hash h = h1 (57 bits) ++ h2 (7 bits)
// h1: used to index the group number of the element
// h2: bit mask
//
// Control byte (metadata):
// - Empty:     0b1000_0000 => -128
// - Deleted:   0b1111_1110 => -2
// - Sentinel:  0b1111_1111 => -1 (to stop scanning the metadata for a table scan)
// - Full:      0b0xxx_xxxx => h2
//
// Basic idea (assuming group = 1):
// Search (key, hash):
// pos = h1(hash) % size
// while true:
//      if h2(hash) == ctrl[pos] && key == slots[pos]:
//          return iter(pos)
//      if ctrl[pos] == empty:
//          return end()
//      pos = (pos + 1) % size
//
// SIMD:
// match (h2, ctrl):
// create a vector of 16 h2s
// m    = [h2, h2, h2, ..., h2] (16 items)
// now compare m with ctrl, if same 1, else 0
// return [0, 0, 1, 0, 1, ...] (16 items)
//
// Basic idea (with SIMD):
// Search (key, hash)
// pos = h1(hash) % size
// return match(h2(hash), ctrl[pos])
//
// Actual search (with more than 1 group)
// Search (key, hash):
// group = h1(hash) % num_groups
// while true:
//      g = ctrl + 16 * group
//      for i in g.match(h2(hash))
//          if key == slots[group * 16 + i]
//              return iter(group * 16 + i)
//      if g.matchempty()   // probe to next group when the entire group is full
//          return end()
//      group = (group + 1) % num_groups
//
// Search:
// 1. Use h1 to get the group number (mod num of groups)
// 2. Load the group metadata table (16 slots)
// 3. (SIMD) Search the group for your key's h2, there may be multiple matches.
//      For each match, check if the keys are equal, return if found
// 4. (SIMD) Search the group for an empty slot
//      If there are any matches, return false
//      Else, every entry is either full or deleted, probe and go to step 2.
//
// Insertion:
// Pass 1: Perform search, if found overwrite there
// Pass 2: Search failed, we perform insertion on an empty/deleted slot
// 1. Use h1 to get the group number
// 2. Load the group metadata table
// 3. (SIMD) Search the group for EMPTY or DELETED
//      If there are no matches, probe and go to step 2.
//      Else, get the first match

test "basic insertion" {}

test "basic fetch" {}

test "basic removal" {}
