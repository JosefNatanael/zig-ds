const std = @import("std");
const os = std.os;
const print = std.debug.print;
const ns_per_s: comptime_int = 1000 * 1000 * 1000;

pub fn nanoTimestamp() u128 {
    var ts: os.timespec = undefined;
    os.clock_gettime(os.CLOCK.REALTIME, &ts) catch |err| switch (err) {
        error.UnsupportedClock, error.Unexpected => return 0, // "Precision of timing depends on hardware and OS".
    };
    return (@as(i128, ts.tv_sec) * ns_per_s) + ts.tv_nsec;
}

fn rdtsc() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    // output in eax and edx, could probably movl edx, fingers x'ed...
    low = asm volatile ("rdtsc"
        : [low] "={eax}" (-> u32),
    );
    high = asm volatile ("movl %%edx,%[high]"
        : [high] "=r" (-> u32),
    );
    const hhigh: u64 = @intCast(high);
    const llow: u64 = @intCast(low);
    return (hhigh << 32) | llow;
    // return ((u64(high) << 32) | (u64(low)));
}

fn tuning() void {
    var samples: [1024]u64 = undefined;
    for (0..1024) |idx| {
        samples[idx] = rdtsc();
    }
    var tot: u128 = 0;
    for (0..1023) |idx| {
        tot += samples[idx + 1] - samples[idx];
    }
    const mean = tot / 1023;
    print("mean: {}\n", .{mean});
}
