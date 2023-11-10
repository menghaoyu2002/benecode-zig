const std = @import("std");

pub fn main() !void {
    const f = try std.fs.cwd().openFile("torrent.torrent", .{ .mode = std.fs.File.OpenMode.read_only });
    defer f.close();

    const stdout = std.io.getStdOut().writer();

    var buf: []u8 = try std.heap.page_allocator.alloc(u8, 1);
    while (try f.read(buf) > 0) {
        try stdout.print("{c}", .{buf[0]});
    }
}
