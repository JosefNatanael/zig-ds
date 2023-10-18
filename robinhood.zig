const std = @import("std");
const mem = std.mem;
const trait = std.meta.trait;
const autoHash = std.hash.autoHash;
const Allocator = std.mem.Allocator;

const ahm = std.AutoHashMap;

pub const default_max_load_percentage = 80;

pub fn DefaultContext(comptime K: type) type {
    comptime {
        if (K == []const u8) {
            return struct {
                pub fn hash(self: @This(), s: []const u8) u64 {
                    _ = self;
                    return std.hash.Wyhash.hash(0, s);
                }
                pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
                    _ = self;
                    return mem.eql(u8, a, b);
                }
            };
        }
    }

    return struct {
        fn hash(self: @This(), key: K) u64 {
            _ = self;
            if (comptime trait.hasUniqueRepresentation(K)) {
                return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
            } else {
                var hasher = std.hash.Wyhash.init(0);
                autoHash(&hasher, key);
                return hasher.final();
            }
        }
        pub fn eql(self: @This(), a: K, b: K) bool {
            _ = self;
            return std.meta.eql(a, b);
        }
    };
}

pub fn HashMap(comptime K: type, comptime V: type, comptime Context: type, comptime max_load_percentage: type) type {
    return struct {
        unmanaged: Unmanaged,
        allocator: Allocator,
        ctx: Context,

        comptime {
            std.hash_map.verifyContext(Context, K, K, u64, false);
        }

        pub const Unmanaged = HashMapUnmanaged(K, V, Context, max_load_percentage);
        pub const Entry = Unmanaged.Entry;
        pub const KV = Unmanaged.KV;
        pub const Hash = Unmanaged.Hash;
        pub const Iterator = Unmanaged.Iterator;
        pub const KeyIterator = Unmanaged.KeyIterator;
        pub const ValueIterator = Unmanaged.ValueIterator;
        pub const Size = Unmanaged.Size;
        pub const GetOrPutResult = Unmanaged.GetOrPutResult;

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            if (@sizeOf(Context) != 0) {
                @compileError("Context must be specified! Call initConext(allocator, ctx) instead.");
            }
            return .{
                .unmanaged = .{},
                .allocator = allocator,
                .ctx = undefined,
            };
        }

        pub fn initContext(allocator: Allocator, ctx: Context) Self {
            return .{
                .unmanaged = .{},
                .allocator = allocator,
                .ctx = ctx,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            return self.unmanaged.clearRetainingCapacity();
        }

        pub fn clearAndFree(self: *Self) void {
            return self.unmanaged.clearAndFree(self.allocator);
        }

        pub fn count(self: Self) Size {
            return self.unmanaged.count();
        }

        pub fn iterator(self: *const Self) Iterator {
            return self.unmanaged.iterator();
        }

        pub fn keyIterator(self: *const Self) KeyIterator {
            return self.unmanaged.keyIterator();
        }

        pub fn valueIterator(self: *const Self) ValueIterator {
            return self.unmanaged.valueIterator();
        }

        pub fn getOrPut(self: *Self, key: K) Allocator.Error!GetOrPutResult {
            return self.unmanaged.getOrPutContext(self.allocator, key, self.ctx);
        }

        pub fn getOrPutAdapted(self: *Self, key: anytype, ctx: anytype) Allocator.Error!GetOrPutResult {
            return self.unmanaged.getOrPutContextAdapted(self.allocator, key, ctx, self.ctx);
        }

        pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            return self.unmanaged.getOrPutAssumeCapacityContext(key, self.ctx);
        }

        pub fn getOrPutAssumeCapacityAdapted(self: *Self, key: anytype, ctx: anytype) GetOrPutResult {
            return self.unmanaged.getOrPutAssumeCapacityAdapted(key, ctx);
        }

        pub fn getOrPutValue(self: *Self, key: K, value: V) Allocator.Error!Entry {
            return self.unmanaged.getOrPutValueContext(self.allocator, key, value, self.ctx);
        }

        pub fn ensureTotalCapacity(self: *Self, expected_count: Size) Allocator.Error!void {
            return self.unmanaged.ensureTotalCapacityContext(self.allocator, expected_count, self.ctx);
        }

        pub fn ensureUnusedCapacity(self: *Self, additional_count: Size) Allocator.Error!void {
            return self.unmanaged.ensureUnusedCapacityContext(self.allocator, additional_count, self.ctx);
        }

        pub fn capacity(self: *Self) Size {
            return self.unmanaged.capacity();
        }

        pub fn put(self: *Self, key: K, value: V) Allocator.Error!void {
            return self.unmanaged.putContext(self.allocator, key, value, self.ctx);
        }

        pub fn putNoClobber(self: *Self, key: K, value: V) Allocator.Error!void {
            return self.unmanaged.putNoClobberContext(self.allocator, key, value, self.ctx);
        }

        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            return self.unmanaged.putAssumeCapacityContext(key, value, self.ctx);
        }

        pub fn putAssumeCapacityNoClobber(self: *Self, key: K, value: V) void {
            return self.unmanaged.putAssumeCapacityNoClobberContext(key, value, self.ctx);
        }

        pub fn fetchPut(self: *Self, key: K, value: V) Allocator.Error!?KV {
            return self.unmanaged.fetchPutContext(self.allocator, key, value, self.ctx);
        }

        pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?KV {
            return self.unmanaged.fetchPutAssumeCapacityContext(key, value, self.ctx);
        }

        pub fn fetchRemove(self: *Self, key: K) ?KV {
            return self.unmanaged.fetchRemoveContext(key, self.ctx);
        }

        pub fn fetchRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV {
            return self.unmanaged.fetchRemoveAdapted(key, ctx);
        }

        pub fn get(self: Self, key: K) ?V {
            return self.unmanaged.getContext(key, self.ctx);
        }
        pub fn getAdapted(self: Self, key: anytype, ctx: anytype) ?V {
            return self.unmanaged.getAdapted(key, ctx);
        }

        pub fn getPtr(self: Self, key: K) ?*V {
            return self.unmanaged.getPtrContext(key, self.ctx);
        }
        pub fn getPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*V {
            return self.unmanaged.getPtrAdapted(key, ctx);
        }

        pub fn getKey(self: Self, key: K) ?K {
            return self.unmanaged.getKeyContext(key, self.ctx);
        }
        pub fn getKeyAdapted(self: Self, key: anytype, ctx: anytype) ?K {
            return self.unmanaged.getKeyAdapted(key, ctx);
        }

        pub fn getKeyPtr(self: Self, key: K) ?*K {
            return self.unmanaged.getKeyPtrContext(key, self.ctx);
        }
        pub fn getKeyPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*K {
            return self.unmanaged.getKeyPtrAdapted(key, ctx);
        }

        pub fn getEntry(self: Self, key: K) ?Entry {
            return self.unmanaged.getEntryContext(key, self.ctx);
        }

        pub fn getEntryAdapted(self: Self, key: anytype, ctx: anytype) ?Entry {
            return self.unmanaged.getEntryAdapted(key, ctx);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.unmanaged.containsContext(key, self.ctx);
        }

        pub fn containsAdapted(self: Self, key: anytype, ctx: anytype) bool {
            return self.unmanaged.containsAdapted(key, ctx);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.unmanaged.removeContext(key, self.ctx);
        }

        pub fn removeAdapted(self: *Self, key: anytype, ctx: anytype) bool {
            return self.unmanaged.removeAdapted(key, ctx);
        }

        pub fn removeByPtr(self: *Self, key_ptr: *K) void {
            self.unmanaged.removeByPtr(key_ptr);
        }

        pub fn clone(self: Self) Allocator.Error!Self {
            var other = try self.unmanaged.cloneContext(self.allocator, self.ctx);
            return other.promoteContext(self.allocator, self.ctx);
        }

        pub fn cloneWithAllocator(self: Self, new_allocator: Allocator) Allocator.Error!Self {
            var other = try self.unmanaged.cloneContext(new_allocator, self.ctx);
            return other.promoteContext(new_allocator, self.ctx);
        }

        pub fn cloneWithContext(self: Self, new_ctx: anytype) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage) {
            var other = try self.unmanaged.cloneContext(self.allocator, new_ctx);
            return other.promoteContext(self.allocator, new_ctx);
        }

        pub fn cloneWithAllocatorAndContext(
            self: Self,
            new_allocator: Allocator,
            new_ctx: anytype,
        ) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage) {
            var other = try self.unmanaged.cloneContext(new_allocator, new_ctx);
            return other.promoteContext(new_allocator, new_ctx);
        }

        pub fn move(self: *Self) Self {
            const result = self.*;
            self.unmanaged = .{};
            return result;
        }
    };
}

pub fn HashMapUnmanaged(
    comptime K: type,
    comptime V: type,
    comptime Context: type,
    comptime max_load_percentage: u64,
) type {
    _ = Context;
    _ = V;
    _ = K;
    if (max_load_percentage <= 0 or max_load_percentage >= 100)
        @compileError("max_load_percentage must be between 0 and 100.");
    return struct {};
}

pub fn RobinHoodMap(comptime K: type, comptime V: type) type {
    return HashMap(K, V, DefaultContext(K), default_max_load_percentage);
}

// Basics of a hashmap:
// 1. make a big array
// 2. get a magic hashing function that converts elements into integers
// 3. store elements in the array at index from the magic function
// 4. do something interesting when there is a hash conflict
//
// Collision resolution strategies:
// 1. chaining
// 2. open addressing
//
// Hashing function:
// Can use SipHash 2-4 or SipHash 1-3
// This is a pseudorandom hash function so that it is impossible
//      for an attacker to determine a set of keys that all hash to the same value
//
// Open addressing strategies:
// 1. Linear probing (fcfs):
//      - insertion: walk to the right until we find an empty space
//      - searching: jump to index, linear search the array until we find a match/empty space
//      - removal: "set as tombstone", searching will skip tombstones, insertion will overwrite tombstones
// 2. Linear probing (lcfs):
//      - insertion: when collide, tell the old element to find a new place, the new element will takeover
//      - searching and removal is the same as fcfs
// 3. Robinhood hashing:
// Similar to fcfs, linear probe for an empty space. However, if we ever find an element that isn't as far from its ideal
// as we currenty are, we take its place and have it continue the search, similar to lcfs
