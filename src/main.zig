const std = @import("std");
const skn = @import("sakana");
const BaseDirectory = skn.BaseDirectory;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const path = try BaseDirectory.getDataHomeApp(allocator, "immersion-rpg");
    defer allocator.free(path);

    var accumulated: u32 = 0;
    for (1..100) |level| {
        // round((level - 1 + 300 * pow(2, (level - 1) / 7)) / 4)
        const a: f32 = @floatFromInt(level - 1);
        const b: f32 = 300 * std.math.pow(f32, 2, a / 7);
        const xp: u32 = if (level == 1) 0 else @intFromFloat(@round((a + b) / 4.0));
        accumulated += xp;
        std.debug.print("Level {} - {} - {}\n", .{ level, xp, accumulated });
    }

    std.debug.print("{s}\n", .{path});
}
