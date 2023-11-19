const std = @import("std");
const benecode = @import("benecode.zig");
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var path: ?[]u8 = null;
    for (args, 1..) |val, len| {
        if (len == 2) {
            path = val;
        }
    }

    if (path == null) {
        try stderr.print("error: missing file path\n", .{});
        std.process.exit(1);
    }

    var f = std.fs.cwd().openFile(path.?, .{ .mode = std.fs.File.OpenMode.read_only }) catch {
        try stderr.print("error: unable to open file at {s}\n", .{path.?});
        std.process.exit(1);
    };
    defer f.close();

    const file_size = (try f.stat()).size;
    var buf = gpa.alloc(u8, file_size) catch |err| {
        try stderr.print("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer gpa.free(buf);

    _ = f.readAll(buf) catch |err| {
        try stderr.print("error: unable to read file due to {}\n", .{err});
        std.process.exit(1);
    };

    const result = benecode.parse_benecode(buf, gpa) catch |err| {
        try stderr.print("error: unable to parse benecode due to {}\n", .{err});
        std.process.exit(1);
    };
    defer benecode.free_benecode(result.value);
    try stdout.print("{s}\n", .{try result.value.to_json_string(gpa)});
}
