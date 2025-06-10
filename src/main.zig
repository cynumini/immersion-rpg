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

    pub fn toUsize(self: Type) usize {
        return @intFromEnum(self);
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

pub fn calcLevel(current_xp: f32, goal: f32) struct { usize, f32, f32 } {
    const coefficient: f32 = goal / levels[levels.len - 1];
    for (0.., levels) |level, xp| {
        const need_xp = coefficient * xp;
        const level_f32: f32 = @floatFromInt(level);
        const difference: f32 = if (level == 0) 0 else (level_f32 + 300 * std.math.pow(f32, 2, level_f32 / 7.0)) / 4;
        if (current_xp < need_xp) return .{ level, need_xp, difference * coefficient };
    } else {
        return .{ 99, goal, 0 };
    }
}

pub fn printProgressBar(writer: anytype, column_count: usize, value: f32, max: f32) !void {
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
    const index = @min(7, floatToInt(usize, percent * 8));
    const progress: usize = floatToInt(usize, intToFloat(f32, column_count - 2) * percent);

    try writer.print("{s}[", .{colors[index]}); // Set color
    for (0..progress) |_| try writer.print("=", .{});
    for (0..(column_count - (progress + 2))) |_| try writer.print(" ", .{});
    try writer.print("]\x1b[0m", .{}); // Clear color
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const file = blk: {
        const app_data_dir = try BaseDirectory.getDataHomeApp(allocator, "immersion-rpg");
        defer allocator.free(app_data_dir);

        const app_data_file = try std.fs.path.join(allocator, &.{ app_data_dir, "data.csv" });
        defer allocator.free(app_data_file);

        break :blk std.fs.openFileAbsolute(app_data_file, .{}) catch |open_error|
            switch (open_error) {
                error.FileNotFound => {
                    std.fs.makeDirAbsolute(app_data_dir) catch |err|
                        if (err != error.PathAlreadyExists) return err;
                    const new_file = try std.fs.createFileAbsolute(app_data_file, .{ .read = true });
                    try new_file.writeAll("type,amount");
                    try new_file.seekTo(0);
                    break :blk new_file;
                },
                else => return open_error,
            };
    };
    defer file.close();

    const Skill = struct {
        name: []const u8,
        type: Type,
        amount: f32,
    };
    var skills = [_]Skill{
        .{ .name = "Anki", .type = Type.anki, .amount = 0 },
        .{ .name = "Visual Novel", .type = Type.visual_novel, .amount = 0 },
        .{ .name = "Reading", .type = Type.reading, .amount = 0 },
        .{ .name = "Manga", .type = Type.manga, .amount = 0 },
        .{ .name = "Listening", .type = Type.listening, .amount = 0 },
        .{ .name = "Anime", .type = Type.anime, .amount = 0 },
        .{ .name = "Total", .type = Type.total, .amount = 0 },
    };

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    const reader = file.reader();

    var index: usize = 0;
    while (reader.readUntilDelimiterArrayList(&line, '\n', std.math.maxInt(usize))) : (index += 1) {
        if (index == 0) continue;
        var it = std.mem.splitAny(u8, line.items, ",");
        var j: usize = 0;
        var row_type: Type = undefined;
        var row_amount: f32 = undefined;
        while (it.next()) |cell| : (j += 1) {
            switch (j) {
                0 => {
                    if (std.mem.eql(u8, "anki", cell)) {
                        row_type = .anki;
                    } else if (std.mem.eql(u8, "vn", cell)) {
                        row_type = .visual_novel;
                    } else if (std.mem.eql(u8, "reading", cell)) {
                        row_type = .reading;
                    } else if (std.mem.eql(u8, "manga", cell)) {
                        row_type = .manga;
                    } else if (std.mem.eql(u8, "listening", cell)) {
                        row_type = .listening;
                    } else if (std.mem.eql(u8, "anime", cell)) {
                        row_type = .anime;
                    } else unreachable;
                },
                1 => row_amount = try std.fmt.parseFloat(f32, cell),
                else => unreachable,
            }
        }
        skills[row_type.toUsize()].amount = if (row_type == .anki)
            @max(skills[row_type.toUsize()].amount, row_amount)
        else
            skills[row_type.toUsize()].amount + row_amount;
    } else |err| if (err != error.EndOfStream) return err;

    for (0..skills.len - 1) |i| {
        skills[skills.len - 1].amount += skills[i].amount / Type.fromInt(i).getGoal() * 1000;
    }
    skills[skills.len - 1].amount /= 6;

    const column_count = blk: {
        var window_size: std.posix.winsize = undefined;
        if (std.posix.errno(std.posix.system.ioctl(
            std.io.getStdOut().handle,
            std.posix.T.IOCGWINSZ,
            @intFromPtr(&window_size),
        )) != .SUCCESS) return error.IoctlError;
        break :blk window_size.col;
    };

    const max_string_len: usize = blk: {
        var max: usize = 0;
        for (skills) |skill| {
            max = @max(skill.name.len, max);
        }
        break :blk max;
    };

    const stdout = std.io.getStdOut().writer();

    for (skills) |skill| {
        const goal = skill.type.getGoal();
        const level, const need_xp, const difference = calcLevel(skill.amount, goal);

        try stdout.print("{s} ", .{skill.name});
        for (0..(max_string_len - skill.name.len)) |_| try stdout.writeAll(" ");
        try stdout.print("({:2})/99", .{level});
        const current_level_string_len = 7;

        const string = blk: {
            if (level != 99) {
                break :blk try std.fmt.allocPrint(allocator, "{}/{d:.2} (left: {d:.2}) ({d:.2}%)\n", .{
                    skn.fmt.Float{ .value = skill.amount },
                    skn.fmt.Float{ .value = need_xp },
                    skn.fmt.Float{ .value = need_xp - skill.amount },
                    skill.amount / need_xp * 100,
                });
            } else break :blk try std.fmt.allocPrint(allocator, "{}\n", .{
                skn.fmt.Float{ .value = skill.amount },
            });
        };
        defer allocator.free(string);

        for (0..column_count - (max_string_len + current_level_string_len + string.len)) |_| {
            try stdout.print(" ", .{});
        }
        try stdout.print("{s}", .{string});

        const current = skill.amount - (need_xp - difference);
        try printProgressBar(stdout, column_count, current, difference);
        try stdout.print("\n", .{});
    }
}
