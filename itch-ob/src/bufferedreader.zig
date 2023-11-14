const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const os = std.os;
const File = std.fs.File;
const assert = std.debug.assert;
const ReadError = os.ReadError;

pub const ReadStatus = enum { OK, ERR };

/// Buffered reader with the buffer stored in stack memory
/// Layout:
/// [..........................................]
/// buffer      pos         limit              buffer + buflen
/// <-------available--------><---freeSpace---->
///
/// For nonblocking versions, checkout std.fs.File.read(...),
/// which internally calls functions in std.os
/// Also checkout the nb_read() implementation of itch-order-book/bufferedreader.h
pub fn StackBufferedReader(comptime buflen: comptime_int) type {
    return struct {
        const Self = @This();
        const Handle = os.fd_t;

        buffer: [buflen]u8 = undefined,
        pos: u32 = 0, // pos of last byte read into buffer
        limit: u32 = 0,
        bytesread: usize = 0,
        // file: File,
        fd: Handle,

        pub fn init() Self {
            return .{
                // .file = io.getStdIn(),
                .fd = io.getStdIn().handle,
            };
        }

        pub inline fn get(self: Self, idx: u32) [*]const u8 {
            return @ptrCast(&self.buffer[self.pos + idx]);
        }

        pub inline fn available(self: Self) u32 {
            return self.limit - self.pos;
        }

        pub inline fn isAvailable(self: Self, n: u32) bool {
            return self.pos + n <= self.limit; // may be faster than available() >= n
        }

        pub inline fn freeSpace(self: Self) u32 {
            return buflen - self.limit;
        }

        pub inline fn advance(self: *Self, bytes: u32) void {
            self.pos += bytes;
            assert(self.pos <= self.limit);
        }

        pub fn discardToPos(self: *Self) void {
            if (self.pos > 0 and self.pos < self.limit) {
                // alternatively, can use std.mem.copyForwards, or memmove
                const items = self.limit - self.pos;
                const offset = self.pos;
                for (0..items) |index| {
                    self.buffer[index] = self.buffer[index + offset];
                }
            }
            self.limit -= self.pos;
            self.pos = 0;
        }

        /// Blocking. Ensures that n bytes are availble to consume.
        /// If available, return, if not, attempt to read.
        /// Return error on failure
        pub fn ensure(self: *Self, n: u32) ReadStatus {
            if (self.isAvailable(n)) {
                return ReadStatus.OK;
            }
            const bytes: isize = self.readN(n);
            if (bytes > 0) {
                return ReadStatus.OK;
            } else if (bytes < 0) {
                // Read error
                return ReadStatus.ERR;
            } else {
                // end of file
                return ReadStatus.ERR;
            }
        }

        pub fn readN(self: *Self, n: u32) isize {
            assert(n <= buflen);
            assert(self.pos <= self.limit);
            assert(self.limit <= buflen);
            if (self.pos + n > buflen) {
                self.discardToPos();
            }
            var bytes_read: isize = 0;
            while (self.available() < n) {
                const bytes = self.read();
                if (bytes <= 0) {
                    return bytes;
                }
                bytes_read += bytes;
            }
            return bytes_read;
        }

        pub fn read(self: *Self) isize {
            const start: [*]u8 = @ptrCast(&self.buffer[self.limit]);
            const slice = start[0 .. buflen - self.limit];
            const result = os.read(self.fd, slice);
            if (result) |bytes| {
                assert(0 <= bytes);
                assert(bytes <= buflen);
                self.limit += @intCast(bytes);
                self.bytesread += @intCast(bytes);
                assert(self.pos <= self.limit);
                assert(self.limit <= buflen);
                return @intCast(bytes);
            } else |err| {
                err catch {};
                return -1;
            }
        }
    };
}
