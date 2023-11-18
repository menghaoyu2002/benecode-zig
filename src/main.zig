const std = @import("std");
const benecode = @import("benecode.zig");

pub fn main() !void {
    const f = try std.fs.cwd().openFile("torrents/torrent.torrent", .{ .mode = std.fs.File.OpenMode.read_only });
    defer f.close();

    // const stdout = std.io.getStdOut().writer();

    const file_size = (try f.stat()).size;
    var buf = try std.heap.page_allocator.alloc(u8, file_size);
    defer std.heap.page_allocator.free(buf);

    _ = try f.readAll(buf);
    _ = try benecode.parse_benecode(buf, std.heap.page_allocator);
}
