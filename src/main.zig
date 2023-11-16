const std = @import("std");

const BenecodeErrors = error{
    InvalidInt,
    InvalidStr,
    InvalidList,
    InvalidDict,
};

const BenecodeTypes = enum {
    Int,
    Str,
    List,
    Dict,
};

const BenecodeValue = union(BenecodeTypes) {
    Int: i32,
    Str: []u8,
    List: []BenecodeValue,
    Dict: std.StringHashMap(BenecodeValue),
};

pub fn main() !void {
    const f = try std.fs.cwd().openFile("torrents/torrent.torrent", .{ .mode = std.fs.File.OpenMode.read_only });
    defer f.close();

    // const stdout = std.io.getStdOut().writer();

    const file_size = (try f.stat()).size;
    var buf = try std.heap.page_allocator.alloc(u8, file_size);
    defer std.heap.page_allocator.free(buf);

    _ = try f.readAll(buf);
    _ = try parse_benecode(buf);
}

fn parse_benecode(bytes: []u8) !BenecodeValue {
    var pos: usize = 0;
    return try _parse_benecode(bytes, &pos);
}

fn _parse_benecode(bytes: []u8, pos: *usize) BenecodeErrors!BenecodeValue {
    while (pos.* < bytes.len) {
        const parsed_value = try switch (bytes[pos.*]) {
            'i' => parse_int(bytes, pos),
            'l' => parse_list(bytes, pos),
            'd' => parse_dict(bytes, pos),
            0...9 => parse_str(bytes, pos),
            else => unreachable,
        };
        _ = parsed_value;

        pos.* += 1;
    }

    return BenecodeErrors.InvalidDict;
}

fn parse_int(bytes: []const u8, ppos: *usize) BenecodeErrors!BenecodeValue {
    var pos = ppos.*;
    if (bytes[pos] != 'i') {
        return BenecodeErrors.InvalidInt;
    }
    pos += 1;

    const is_negative = bytes[pos] == '-';
    if (is_negative) {
        pos += 1;
    }

    var int: i32 = 0;

    while (pos < bytes.len and bytes[pos] != 'e') {
        if (bytes[pos] > '9') {
            return BenecodeErrors.InvalidInt;
        }

        int = int * 10 + bytes[pos] - '0';
        pos += 1;
    }

    if (bytes[pos] != 'e') {
        return BenecodeErrors.InvalidInt;
    }
    pos += 1;

    if (is_negative) {
        if (int == 0) {
            return BenecodeErrors.InvalidInt;
        }

        int = -int;
    }

    ppos.* = pos;
    return BenecodeValue{ .Int = int };
}

fn parse_str(bytes: []const u8, pos: *usize) BenecodeErrors!BenecodeValue {
    _ = bytes;
    _ = pos;
    return BenecodeErrors.InvalidDict;
}

fn parse_list(bytes: []const u8, pos: *usize) BenecodeErrors!BenecodeValue {
    _ = pos;
    _ = bytes;
    return BenecodeErrors.InvalidDict;
}

fn parse_dict(bytes: []const u8, pos: *usize) BenecodeErrors!BenecodeValue {
    _ = pos;
    _ = bytes;
    return BenecodeErrors.InvalidDict;
}

fn free_benecode(value: BenecodeValue) void {
    switch (value.tag) {
        BenecodeTypes.Int => {},
        BenecodeTypes.Str => {},
        BenecodeTypes.List => {},
        BenecodeTypes.Dict => {},
    }
}

test "parse benecode string" {
    const str = "4:spam";
    var pos: usize = 0;
    const value = try parse_str(str, &pos);
    try std.testing.expectEqualStrings(value.Str, "spam");
    try std.testing.expectEqual(pos, str.len);
}

test "parse positive benecode int" {
    const str = "i3e";
    var pos: usize = 0;
    const value = try parse_int(str, &pos);
    try std.testing.expectEqual(@as(i32, 3), value.Int);
    try std.testing.expectEqual(str.len, pos);
}

test "parse negative benecode int" {
    const str = "i-3e";
    var pos: usize = 0;
    const value = try parse_int(str, &pos);
    try std.testing.expectEqual(@as(i32, -3), value.Int);
    try std.testing.expectEqual(str.len, pos);
}

test "parse invalid benecode int" {
    const str = "ihelloe";
    var pos: usize = 0;
    var value = parse_int(str, &pos);
    try std.testing.expectError(BenecodeErrors.InvalidInt, value);

    // pointer should not move if we could not parse the int
    try std.testing.expectEqual(@as(usize, 0), pos);

    const negative_zero = "i-0e";
    pos = 0;
    value = parse_int(negative_zero, &pos);
    try std.testing.expectError(BenecodeErrors.InvalidInt, value);
    try std.testing.expectEqual(@as(usize, 0), pos);
}

test "parse benecode list" {
    const str = "l4:spami3ee";
    var pos: usize = 0;
    const value = try parse_list(str, &pos);
    try std.testing.expectEqual(value.List.len, 2);
    try std.testing.expectEqualStrings(value.List[0].Str, "spam");
    try std.testing.expectEqual(value.List[1].Int, 3);
    try std.testing.expectEqual(pos, str.len);
}

test "parse benecode dict" {
    const str = "d3:cow3:moo4:spam4:eggse";
    var pos: usize = 0;
    const value = try parse_dict(str, &pos);
    try std.testing.expectEqualStrings(value.Dict.get("cow").?.Str, "moo");
    try std.testing.expectEqualStrings(value.Dict.get("spam").?.Str, "eggs");
    try std.testing.expectEqual(pos, str.len);
}

test "parse benecode nested lists" {}
test "parse benecode nested dicts" {}
test "parse benecode dicts in lists" {}
test "parse benecode lists in dicts" {}
