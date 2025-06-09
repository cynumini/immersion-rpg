const std = @import("std");
const skn = @import("sakana");
const BaseDirectory = skn.BaseDirectory;

const Type = enum(usize) {
    anki,
    visual_novel,
    reading,
    manga,
    listening,
    anime,
    total,

    pub fn fromInt(value: anytype) Type {
        return @enumFromInt(value);
    }

    pub fn len() usize {
        return @typeInfo(Type).@"enum".fields.len;
    }

    pub fn getGoal(self: Type) f32 {
        return switch (self) {
            .anki => 25_000,
            .visual_novel => 10_000_000,
            .reading => 10_000_000,
            .manga => 100_000,
            .listening => 50_000,
            .anime => 1_500,
            .total => 100,
        };
    }
};

const levels = blk: {
    @setEvalBranchQuota(9000);
    var result: [99]f32 = undefined;
    var xp: comptime_float = 0;
    for (0..result.len) |level| {
        // (level + 300 * 2 ^ (level / 7)) / 4
        const level_f32: comptime_float = @floatFromInt(level);
        const difference: comptime_float = if (level == 0) 0 else (level_f32 + 300 * std.math.pow(f32, 2, level_f32 / 7.0)) / 4;
        xp += difference;
        result[level] = xp;
    }
    break :blk result;
};

pub fn intToFloat(T: type, value: anytype) T {
    return @floatFromInt(value);
}

pub fn floatToInt(T: type, value: anytype) T {
    return @intFromFloat(value);
}

pub fn calcLevel(current_xp: f32, goal: f32) struct { usize, f32 } {
    const coefficient: f32 = goal / levels[levels.len - 1];
    for (0.., levels) |level, xp| {
        const need_xp_to_next = coefficient * xp;
        if (current_xp < need_xp_to_next) return .{ level, need_xp_to_next };
    } else {
        return .{ 99, goal };
    }
}

pub fn printPercent(writer: anytype, width: usize, value: f32, max: f32) !void {
    const colors: [8][]const u8 = .{
        "\x1b[31m", // Red
        "\x1b[91m", // Bright Red
        "\x1b[33m", // Yellow
        "\x1b[93m", // Bright Yellow
        "\x1b[32m", // Green
        "\x1b[92m", // Bright Green
        "\x1b[34m", // Blue
        "\x1b[94m", // Bright Blue
    };
    const percent = value / max;
    // std.debug.print("here {d:.2} / {d:.2} = {d:.2}\n", .{value, max, percent});
    const index = @min(7, floatToInt(usize, percent * 8));

    var bar: usize = (width - 2);
    bar = floatToInt(usize, intToFloat(f32, bar) * percent);

    try writer.print("{s}[", .{colors[index]});

    for (0..bar) |_| {
        try writer.print("=", .{});
    }

    for (0..(width - bar - 2)) |_| {
        try writer.print(" ", .{});
    }

    try writer.print("]\x1b[0m", .{});
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const data_home_app_path = try BaseDirectory.getDataHomeApp(allocator, "immersion-rpg");
    defer allocator.free(data_home_app_path);

    const data_path = try std.fs.path.join(allocator, &.{ data_home_app_path, "data.csv" });
    defer allocator.free(data_path);

    const file: std.fs.File = std.fs.openFileAbsolute(data_path, .{}) catch |open_error| switch (open_error) {
        error.FileNotFound => blk: {
            std.fs.makeDirAbsolute(data_home_app_path) catch |err| if (err != error.PathAlreadyExists) return err;
            const new_file = try std.fs.createFileAbsolute(data_path, .{ .read = true });
            try new_file.writeAll("type,amount");
            try new_file.seekTo(0);
            break :blk new_file;
        },
        else => return open_error,
    };
    defer file.close();

    const reader = file.reader();

    const Line = struct {
        type: Type,
        amount: f32,
    };
    var lines = std.ArrayList(Line).init(allocator);
    defer lines.deinit();

    var raw_line = std.ArrayList(u8).init(allocator);
    defer raw_line.deinit();

    var index: usize = 0;
    while (reader.readUntilDelimiterArrayList(&raw_line, '\n', std.math.maxInt(usize))) : (index += 1) {
        if (index == 0) continue;
        var it = std.mem.splitAny(u8, raw_line.items, ",");
        var j: usize = 0;
        var line: Line = undefined;
        while (it.next()) |cell| : (j += 1) {
            switch (j) {
                0 => {
                    if (std.mem.eql(u8, "anki", cell)) {
                        line.type = .anki;
                    } else if (std.mem.eql(u8, "vn", cell)) {
                        line.type = .visual_novel;
                    } else if (std.mem.eql(u8, "reading", cell)) {
                        line.type = .reading;
                    } else if (std.mem.eql(u8, "manga", cell)) {
                        line.type = .manga;
                    } else if (std.mem.eql(u8, "listening", cell)) {
                        line.type = .listening;
                    } else if (std.mem.eql(u8, "anime", cell)) {
                        line.type = .anime;
                    } else unreachable;
                },
                1 => line.amount = try std.fmt.parseFloat(f32, cell),
                else => unreachable,
            }
        }
        try lines.append(line);
    } else |err| if (err != error.EndOfStream) return err;

    var total: [Type.len()]f32 = std.mem.zeroes([Type.len()]f32);

    for (lines.items) |line| {
        total[@intFromEnum(line.type)] = if (line.type == .anki)
            @max(total[@intFromEnum(line.type)], line.amount)
        else
            total[@intFromEnum(line.type)] + line.amount;
    }

    for (0..total.len - 1) |i| {
        total[total.len - 1] += total[i] / Type.fromInt(i).getGoal() * 100;
    }
    total[total.len - 1] /= 6;

    var buf: std.posix.winsize = undefined;
    if (std.posix.errno(std.posix.system.ioctl(
        std.io.getStdOut().handle,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&buf),
    )) != .SUCCESS) return error.IoctlError;

    const skills = &.{
        .{ "Anki", Type.anki },
        .{ "Visual Novel", Type.visual_novel },
        .{ "Reading", Type.reading },
        .{ "Manga", Type.manga },
        .{ "Listening", Type.listening },
        .{ "Anime", Type.anime },
        .{ "Total", Type.total },
    };

    const max_string: usize = comptime blk: {
        var max: usize = 0;
        for (skills) |skill| {
            max = @max(skill[0].len, max);
        }
        break :blk max;
    };

    const stdout = std.io.getStdOut().writer();
    const fmt = std.fmt.comptimePrint("{{s: <{}}} ({{:2}}/99)", .{max_string});

    inline for (skills) |skill| {
        const name, const skill_type = skill;
        const goal = skill_type.getGoal();
        const value = total[@intFromEnum(skill_type)];
        const level, const need = calcLevel(value, goal);
        std.debug.print(fmt, .{ name, level });
        if (level != 99) {
            const string = try std.fmt.allocPrint(allocator, "{}/{d:.2} ({d:.2}%)\n", .{
                skn.fmt.Float{ .value = value },
                skn.fmt.Float{ .value = need },
                value / need * 100,
            });
            defer allocator.free(string);
            for (0..buf.col - max_string - 7 - string.len) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("{s}", .{string});
        } else {
            const string = try std.fmt.allocPrint(allocator, "{}\n", .{
                skn.fmt.Float{ .value = -value },
            });
            defer allocator.free(string);
            for (0..buf.col - max_string - 7 - string.len) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("{s}", .{string});
        }
        try printPercent(stdout, buf.col, value, need);
        std.debug.print("\n", .{});
    }
}
