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
    List: std.ArrayList(BenecodeValue),
    Dict: std.StringHashMap(BenecodeValue),
};

const ParsedBenecodeValue = struct {
    value: BenecodeValue,
    chars_parsed: usize,
};

pub fn parse_benecode(bytes: []const u8, allocator: std.mem.Allocator) BenecodeErrors!ParsedBenecodeValue {
    return switch (bytes[0]) {
        'i' => parse_int(bytes),
        'l' => parse_list(bytes, allocator),
        'd' => parse_dict(bytes, allocator),
        '0'...'9' => parse_str(bytes),
        else => unreachable,
    };
}

pub fn parse_int(bytes: []const u8) BenecodeErrors!ParsedBenecodeValue {
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

    if (curr >= bytes.len or bytes[curr] != 'e') {
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
    return ParsedBenecodeValue{ .value = value, .chars_parsed = curr };
}

pub fn parse_str(bytes: []const u8) BenecodeErrors!ParsedBenecodeValue {
    var size: usize = 0;
    var colon_pos: usize = 0;
    while (colon_pos < bytes.len and bytes[colon_pos] != ':') {
        if (bytes[colon_pos] > '9' or bytes[colon_pos] < '0') {
            return BenecodeErrors.InvalidStr;
        }

        size = size * 10 + bytes[colon_pos] - '0';
        colon_pos += 1;
    }

    if (colon_pos >= bytes.len or bytes[colon_pos] != ':') {
        return BenecodeErrors.InvalidStr;
    }
    colon_pos += 1;

    const value = BenecodeValue{ .Str = bytes[colon_pos .. colon_pos + size] };
    return ParsedBenecodeValue{ .value = value, .chars_parsed = colon_pos + size };
}

pub fn parse_list(bytes: []const u8, allocator: std.mem.Allocator) BenecodeErrors!ParsedBenecodeValue {
    var curr: usize = 0;
    if (bytes[curr] != 'l') {
        return BenecodeErrors.InvalidList;
    }
    curr += 1;

    var array = std.ArrayList(BenecodeValue).init(allocator);
    while (curr < bytes.len and bytes[curr] != 'e') {
        const benecode = try parse_benecode(bytes[curr..], allocator);
        try array.append(benecode.value);
        curr += benecode.chars_parsed;
    }

    if (curr >= bytes.len or bytes[curr] != 'e') {
        array.deinit();
        return BenecodeErrors.InvalidList;
    }
    curr += 1;

    const value = BenecodeValue{ .List = array };

    return ParsedBenecodeValue{ .value = value, .chars_parsed = curr };
}

pub fn parse_dict(bytes: []const u8, allocator: std.mem.Allocator) BenecodeErrors!ParsedBenecodeValue {
    var curr: usize = 0;
    if (bytes[curr] != 'd') {
        return BenecodeErrors.InvalidDict;
    }
    curr += 1;

    var dict = std.StringHashMap(BenecodeValue).init(allocator);
    while (curr < bytes.len and bytes[curr] != 'e') {
        const key = try parse_str(bytes[curr..]);
        curr += key.chars_parsed;
        const val = try parse_benecode(bytes[curr..], allocator);
        curr += val.chars_parsed;
        try dict.put(key.value.Str, val.value);
    }

    const value = BenecodeValue{ .Dict = dict };
    if (curr >= bytes.len or bytes[curr] != 'e') {
        free_benecode(value);
        return BenecodeErrors.InvalidDict;
    }
    curr += 1;

    return ParsedBenecodeValue{ .value = value, .chars_parsed = curr };
}

pub fn free_benecode(benecode: BenecodeValue) void {
    switch (benecode) {
        .Dict => {
            var dict = benecode.Dict;
            var iterator = dict.valueIterator();
            while (iterator.next()) |value| {
                free_benecode(value.*);
            }

            dict.deinit();
        },
        .List => |list| {
            for (list.items) |value| {
                free_benecode(value);
            }
            list.deinit();
        },
        else => {},
    }
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
    const result = try parse_list(str, std.testing.allocator);
    defer free_benecode(result.value);
    try std.testing.expectEqual(result.value.List.items.len, 2);
    try std.testing.expectEqualStrings("spam", result.value.List.items[0].Str);
    try std.testing.expectEqual(result.value.List.items[1].Int, 3);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse empty benecode list" {
    const str = "le";
    const result = try parse_list(str, std.testing.allocator);
    defer free_benecode(result.value);
    try std.testing.expectEqual(result.value.List.items.len, 0);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse invalid benecode list" {
    const str = "l4:test";
    const result = parse_list(str, std.testing.allocator);
    try std.testing.expectError(BenecodeErrors.InvalidList, result);
}

test "parse benecode nested lists" {
    const str = "l4:testl6:nested5:valueee";
    const result = try parse_list(str, std.testing.allocator);
    defer free_benecode(result.value);
    try std.testing.expectEqualStrings("test", result.value.List.items[0].Str);
    try std.testing.expectEqualStrings("nested", result.value.List.items[1].List.items[0].Str);
    try std.testing.expectEqualStrings("value", result.value.List.items[1].List.items[1].Str);
}

test "parse benecode dict" {
    const str = "d3:cow3:moo4:spam4:eggse";
    var result = try parse_dict(str, std.testing.allocator);
    defer free_benecode(result.value);
    try std.testing.expectEqualStrings("moo", result.value.Dict.get("cow").?.Str);
    try std.testing.expectEqualStrings("eggs", result.value.Dict.get("spam").?.Str);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse invalid benecode dict" {
    const str = "d3:cow3:moo4:spam4:eggs";
    var result = parse_dict(str, std.testing.allocator);
    try std.testing.expectError(BenecodeErrors.InvalidDict, result);
}

test "parse benecode nested dicts" {
    const str = "d6:nestedd4:test4:caseee";
    var result = try parse_dict(str, std.testing.allocator);
    var nested = result.value.Dict.get("nested").?.Dict;

    defer free_benecode(result.value);

    try std.testing.expectEqualStrings("case", nested.get("test").?.Str);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse benecode dicts in lists" {
    const str = "ld4:test4:caseee";
    const result = try parse_list(str, std.testing.allocator);
    var dict = result.value.List.items[0].Dict;

    defer free_benecode(result.value);

    try std.testing.expectEqualStrings("case", dict.get("test").?.Str);
    try std.testing.expectEqual(@as(usize, 1), result.value.List.items.len);
    try std.testing.expectEqual(str.len, result.chars_parsed);
}

test "parse benecode lists in dicts" {
    const str = "d4:listli1eee";
    var result = try parse_dict(str, std.testing.allocator);
    const array: std.ArrayList(BenecodeValue) = result.value.Dict.get("list").?.List;

    defer free_benecode(result.value);

    try std.testing.expectEqual(@as(i32, 1), array.items[0].Int);
    try std.testing.expectEqual(@as(usize, 1), array.items.len);
    try std.testing.expectEqual(@as(u32, 1), result.value.Dict.count());
    try std.testing.expectEqual(str.len, result.chars_parsed);
}
