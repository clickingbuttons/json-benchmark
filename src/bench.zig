//! https://github.com/Hejsil/zig-bench/tree/60c49fc

const std = @import("std");

const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const time = std.time;

const Decl = std.builtin.Type.Declaration;

pub fn benchmark(comptime B: type) !void {
    const ally = if (@hasDecl(B, "allocator")) B.allocator else testing.allocator;
    const types = if (@hasDecl(B, "types")) B.types else [_]type{{}};
    const args = if (@hasDecl(B, "args")) B.args else [_]void{{}};
    const arg_names = if (@hasDecl(B, "names")) B.names else [_]u8{};
    const min_iterations = if (@hasDecl(B, "min_iterations")) B.min_iterations else 10000;
    const max_iterations = if (@hasDecl(B, "max_iterations")) B.max_iterations else 100000;
    const max_time = 500 * time.ns_per_ms;

    const functions = comptime blk: {
        var res: []const Decl = &[_]Decl{};
        for (meta.declarations(B)) |decl| {
            if (@typeInfo(@TypeOf(@field(B, decl.name))) != .Fn)
                continue;
            res = res ++ [_]Decl{decl};
        }

        break :blk res;
    };
    if (functions.len == 0)
        @compileError("No benchmarks to run.");

    const min_width = blk: {
        const writer = io.null_writer;
        var res = [_]u64{ 0, 0, 0, 0, 0, 0 };
        res = try printBenchmark(
            writer,
            res,
            "Benchmark",
            formatter("{s}", ""),
            formatter("{s}", "Iterations"),
            formatter("{s}", "Min(ms)"),
            formatter("{s}", "Max(ms)"),
            formatter("{s}", "Variance"),
            formatter("{s}", "Mean(ms)"),
        );
        inline for (functions) |f| {
            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                const max = math.maxInt(u32);
                res = if (i < arg_names.len) blk2: {
                    const arg_name = formatter("{s}", arg_names[i]);
                    break :blk2 try printBenchmark(writer, res, f.name, arg_name, max, max, max, max, max);
                } else blk2: {
                    break :blk2 try printBenchmark(writer, res, f.name, i, max, max, max, max, max);
                };
            }
        }
        break :blk res;
    };

    var _stderr = std.io.bufferedWriter(std.io.getStdErr().writer());
    const stderr = _stderr.writer();
    try stderr.writeAll(" \n");
    _ = try printBenchmark(
        stderr,
        min_width,
        "Benchmark",
        formatter("{s}", ""),
        formatter("{s}", "Iterations"),
        formatter("{s}", "Min(ms)"),
        formatter("{s}", "Max(ms)"),
        formatter("{s}", "Variance"),
        formatter("{s}", "Mean(ms)"),
    );
    try stderr.writeAll("\n");
    for (min_width) |w|
        try stderr.writeByteNTimes('-', w);
    try stderr.writeByteNTimes('-', min_width.len - 1);
    try stderr.writeAll("\n");
    try stderr.context.flush();

    var timer = try time.Timer.start();
    inline for (functions) |def| {
        inline for (args, 0..) |arg, index| {
            var runtimes: [max_iterations]u64 = undefined;
            var min: u64 = math.maxInt(u64);
            var max: u64 = 0;
            var runtime_sum: u128 = 0;

            var i: usize = 0;
            while (i < min_iterations or (i < max_iterations and runtime_sum < max_time)) : (i += 1) {
                timer.reset();
                const res = @field(B, def.name)(ally, types[index], arg);
                runtimes[i] = timer.read() / std.time.ns_per_ms;

                runtime_sum += runtimes[i];
                if (runtimes[i] < min) min = runtimes[i];
                if (runtimes[i] > max) max = runtimes[i];
                switch (@TypeOf(res)) {
                    void => {},
                    else => std.mem.doNotOptimizeAway(&res),
                }
            }

            const runtime_mean: u64 = @intCast(runtime_sum / i);

            var d_sq_sum: u128 = 0;
            for (runtimes[0..i]) |runtime| {
                const d = @as(i64, @intCast(@as(i128, @intCast(runtime)) - runtime_mean));
                d_sq_sum += @as(u64, @intCast(d * d));
            }
            const variance = d_sq_sum / i;

            if (index < arg_names.len) {
                const arg_name = formatter("{s}", arg_names[index]);
                _ = try printBenchmark(stderr, min_width, def.name, arg_name, i, min, max, variance, runtime_mean);
            } else {
                _ = try printBenchmark(stderr, min_width, def.name, index, i, min, max, variance, runtime_mean);
            }
            try stderr.writeAll("\n");
            try stderr.context.flush();
        }
    }
}

fn printBenchmark(
    writer: anytype,
    min_widths: [6]u64,
    func_name: []const u8,
    arg_name: anytype,
    iterations: anytype,
    min_runtime: anytype,
    max_runtime: anytype,
    variance: anytype,
    mean_runtime: anytype,
) ![6]u64 {
    const arg_len = std.fmt.count("{}", .{arg_name});
    const name_len = try alignedPrint(writer, .left, min_widths[0], "{s}{s}{}{s}", .{
        func_name,
        "("[0..@intFromBool(arg_len != 0)],
        arg_name,
        ")"[0..@intFromBool(arg_len != 0)],
    });
    try writer.writeAll(" ");
    const it_len = try alignedPrint(writer, .right, min_widths[1], "{}", .{iterations});
    try writer.writeAll(" ");
    const min_runtime_len = try alignedPrint(writer, .right, min_widths[2], "{}", .{min_runtime});
    try writer.writeAll(" ");
    const max_runtime_len = try alignedPrint(writer, .right, min_widths[3], "{}", .{max_runtime});
    try writer.writeAll(" ");
    const variance_len = try alignedPrint(writer, .right, min_widths[4], "{}", .{variance});
    try writer.writeAll(" ");
    const mean_runtime_len = try alignedPrint(writer, .right, min_widths[5], "{}", .{mean_runtime});

    return [_]u64{ name_len, it_len, min_runtime_len, max_runtime_len, variance_len, mean_runtime_len };
}

fn formatter(comptime fmt_str: []const u8, value: anytype) Formatter(fmt_str, @TypeOf(value)) {
    return .{ .value = value };
}

fn Formatter(comptime fmt_str: []const u8, comptime T: type) type {
    return struct {
        value: T,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try std.fmt.format(writer, fmt_str, .{self.value});
        }
    };
}

fn alignedPrint(writer: anytype, dir: enum { left, right }, width: u64, comptime fmt: []const u8, args: anytype) !u64 {
    const value_len = std.fmt.count(fmt, args);

    var cow = io.countingWriter(writer);
    if (dir == .right)
        try cow.writer().writeByteNTimes(' ', math.sub(u64, width, value_len) catch 0);
    try cow.writer().print(fmt, args);
    if (dir == .left)
        try cow.writer().writeByteNTimes(' ', math.sub(u64, width, value_len) catch 0);
    return cow.bytes_written;
}
