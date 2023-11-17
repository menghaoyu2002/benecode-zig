const std = @import("std");

const BenecodeErrors = error{ InvalidInt, InvalidStr, InvalidList, InvalidDict, OutOfMemory };

const BenecodeTypes = enum {
    Int,
    Str,
    List,
    Dict,
};

const BenecodeValue = union(BenecodeTypes) {
    Int: i32,
    Str: []const u8,
    List: []BenecodeValue,
    Dict: std.StringHashMap(BenecodeValue),
};

const ParsedBenecode = struct {
    value: BenecodeValue,
    chars_parsed: usize,
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

fn parse_benecode(bytes: []const u8) BenecodeErrors!BenecodeValue {
    return switch (bytes[0]) {
        'i' => parse_int(bytes),
        'l' => parse_list(bytes),
        'd' => parse_dict(bytes),
        '0'...'9' => parse_str(bytes),
        else => unreachable,
    };
}

fn parse_int(bytes: []const u8) BenecodeErrors!ParsedBenecode {
    var curr: usize = 0;
    if (bytes[curr] != 'i') {
        return BenecodeErrors.InvalidInt;
    }
    curr += 1;

    const is_negative = bytes[curr] == '-';
    if (is_negative) {
        curr += 1;
    }

    var int: i32 = 0;

    while (curr < bytes.len and bytes[curr] != 'e') {
        if (bytes[curr] > '9' or bytes[curr] < '0') {
            return BenecodeErrors.InvalidInt;
        }

        int = int * 10 + bytes[curr] - '0';
        curr += 1;
    }

    if (bytes[curr] != 'e') {
        return BenecodeErrors.InvalidInt;
    }
    curr += 1;

    if (is_negative) {
        if (int == 0) {
            return BenecodeErrors.InvalidInt;
        }

        int = -int;
    }

    const value = BenecodeValue{ .Int = int };
    return ParsedBenecode{ .value = value, .chars_parsed = curr };
}

fn parse_str(bytes: []const u8) BenecodeErrors!ParsedBenecode {
    var size: usize = 0;
    var colon_pos: usize = 0;
    while (colon_pos < bytes.len and bytes[colon_pos] != ':') {
        if (bytes[colon_pos] > '9' or bytes[colon_pos] < '0') {
            return BenecodeErrors.InvalidStr;
        }

        size = size * 10 + bytes[colon_pos] - '0';
        colon_pos += 1;
    }

    if (bytes[colon_pos] != ':') {
        return BenecodeErrors.InvalidStr;
    }
    colon_pos += 1;

    const value = BenecodeValue{ .Str = bytes[colon_pos .. colon_pos + size] };
    return ParsedBenecode{ .value = value, .chars_parsed = colon_pos + size };
}

fn parse_list(bytes: []const u8) BenecodeErrors!BenecodeValue {
    _ = bytes;
    return BenecodeErrors.InvalidList;
}

fn parse_dict(bytes: []const u8) BenecodeErrors!BenecodeValue {
    _ = bytes;
    return BenecodeErrors.InvalidDict;
}

test "parse benecode string" {
    const str = "4:spam";
    const result = try parse_str(str);
    try std.testing.expectEqualStrings("spam", result.value.Str);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse invalid benecode string \"4spa:m\"" {
    const value = parse_str("4spa:m");
    try std.testing.expectError(BenecodeErrors.InvalidStr, value);
}

test "parse invalid benecode string \"4spam\"" {
    const value = parse_str("4spam");
    try std.testing.expectError(BenecodeErrors.InvalidStr, value);
}

test "parse positive benecode int" {
    const str = "i3e";
    const result = try parse_int(str);
    try std.testing.expectEqual(@as(i32, 3), result.value.Int);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse negative benecode int" {
    const str = "i-3e";
    const result = try parse_int(str);
    try std.testing.expectEqual(@as(i32, -3), result.value.Int);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse invalid benecode int" {
    const str = "ihelloe";
    const value = parse_int(str);
    try std.testing.expectError(BenecodeErrors.InvalidInt, value);
}

test "parse invalid benecode int negative zero" {
    const negative_zero = "i-0e";
    const value = parse_int(negative_zero);
    try std.testing.expectError(BenecodeErrors.InvalidInt, value);
}

test "parse benecode list" {
    const str = "l4:spami3ee";
    const value = try parse_list(str);
    try std.testing.expectEqual(value.List.len, 2);
    try std.testing.expectEqualStrings(value.List[0].Str, "spam");
    try std.testing.expectEqual(value.List[1].Int, 3);
}

test "parse benecode dict" {
    const str = "d3:cow3:moo4:spam4:eggse";
    const value = try parse_dict(str);
    try std.testing.expectEqualStrings(value.Dict.get("cow").?.Str, "moo");
    try std.testing.expectEqualStrings(value.Dict.get("spam").?.Str, "eggs");
}

test "parse benecode nested lists" {}
test "parse benecode nested dicts" {}
test "parse benecode dicts in lists" {}
test "parse benecode lists in dicts" {}
