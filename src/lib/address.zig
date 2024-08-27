const std = @import("std");
const base32 = @import("base32");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const nimiq_base32_alphabet = "0123456789ABCDEFGHJKLMNPQRSTUVXY";
const nimiq_base32_encoder = base32.Encoding.initWithPadding(nimiq_base32_alphabet, null);

pub const InvalidAddressError = error{
    InvalidLength,
    InvalidCountryCode,
};

const address_length = 20;
const address_length_hex = address_length * 2;
const address_length_friendly = 44;

/// Address holds the raw bytes of a Nimiq address
/// the address can either be parsed from hex or the friendly address format
pub const Address = struct {
    bytes: [address_length]u8,

    /// Parse address from hex string
    pub fn parseAddressFromHex(self: *Address, hex: []const u8) !void {
        if (hex.len != address_length_hex) return InvalidAddressError.InvalidLength;

        const decoded = try fmt.hexToBytes(&self.bytes, hex);
        if (decoded.len != address_length) return InvalidAddressError.InvalidLength;

        self.bytes = decoded[0..address_length].*;
    }

    /// Parse address from friendly address format
    pub fn parseAddressFromFriendly(self: *Address, friendly: []const u8) !void {
        if (friendly.len != address_length_friendly) return InvalidAddressError.InvalidLength;
        if (friendly[0] != 'N' or friendly[1] != 'Q') return InvalidAddressError.InvalidCountryCode;

        var trimmed = [_]u8{0} ** 32;
        var index: usize = 0;
        for (friendly[5..]) |
            char,
        | {
            if (char == ' ') continue;
            trimmed[index] = char;
            index += 1;
        }

        var out = try nimiq_base32_encoder.decode(&self.bytes, &trimmed);
        self.bytes = out[0..address_length].*;
    }

    pub fn toFriendlyAddress(self: *Address, allocator: Allocator) !u32 {
        const base32_encoded = try allocator.alloc(u8, nimiq_base32_encoder.encodeLen(self.bytes.len));
        defer allocator.free(base32_encoded);

        const encoded = nimiq_base32_encoder.encode(base32_encoded, &self.bytes);
        var payload = ArrayList(u8).init(allocator);
        defer payload.deinit();

        try payload.appendSlice(encoded);
        try payload.appendSlice("NQ00");

        const iban_number = 98 - try ibanCheck(payload.items, allocator);

        return iban_number;
    }

    fn ibanCheck(data: []u8, allocator: Allocator) !u32 {
        var number_list = ArrayList(u8).init(allocator);
        defer number_list.deinit();

        for (data) |char| {
            if (char >= 48 and char <= 57) {
                try number_list.append(char);
            } else {
                try fmt.format(number_list.writer(), "{d}", .{char - 55});
            }
        }

        const number_string = number_list.items;

        var iban_number: u32 = 0;
        var i: usize = 0;
        const div = try math.divCeil(usize, number_string.len, 6);
        while (i < div) : (i += 1) {
            const start_index: usize = i * 6;
            const end_index: usize = @min(@as(usize, number_string.len), start_index + 6);

            const iban_number_string = try fmt.allocPrint(allocator, "{any}{s}", .{ iban_number, number_string[start_index..end_index] });
            defer allocator.free(iban_number_string);

            const parsed_uint = try fmt.parseInt(u32, iban_number_string, 10);
            iban_number = @rem(parsed_uint, 97);
        }

        return iban_number;
    }
};

var test_address = Address{ .bytes = [20]u8{ 0x93, 0xef, 0x3e, 0x94, 0x5f, 0x99, 0xcf, 0x64, 0x3f, 0x26, 0xa2, 0x58, 0xa2, 0x88, 0x32, 0xf8, 0x98, 0xed, 0xa4, 0x96 } };

test "Parse address from hex: invalid length" {
    const allocator = testing.allocator;

    var address = try allocator.create(Address);
    defer allocator.destroy(address);

    const result = address.parseAddressFromHex("0016");
    try testing.expectError(InvalidAddressError.InvalidLength, result);
}

test "Parse address from hex: ok" {
    const allocator = testing.allocator;

    var address = try allocator.create(Address);
    defer allocator.destroy(address);

    try address.parseAddressFromHex("93ef3e945f99cf643f26a258a28832f898eda496");
    try testing.expectEqualSlices(u8, &address.bytes, &test_address.bytes);
}

test "Parse address from friendly: invalid length" {
    const allocator = testing.allocator;

    var address = try allocator.create(Address);
    defer allocator.destroy(address);

    const result = address.parseAddressFromFriendly("0016");
    try testing.expectError(InvalidAddressError.InvalidLength, result);
}

test "Parse address from friendly: invalid country code" {
    const allocator = testing.allocator;

    var address = try allocator.create(Address);
    defer allocator.destroy(address);

    const result = address.parseAddressFromFriendly("NT61 JFPK V52Y K77N 8FR6 L9CA 521J Y2CE T94N");
    try testing.expectError(InvalidAddressError.InvalidCountryCode, result);
}

test "Parse address from friendly: ok" {
    const allocator = testing.allocator;

    var address = try allocator.create(Address);
    defer allocator.destroy(address);

    try address.parseAddressFromFriendly("NQ61 JFPK V52Y K77N 8FR6 L9CA 521J Y2CE T94N");
    try testing.expectEqualSlices(u8, &address.bytes, &test_address.bytes);
}

test "to friendly address" {
    const allocator = testing.allocator;
    var address = &test_address;
    const iban_number = try address.toFriendlyAddress(allocator);
    std.debug.print("\n\ngot iban {d}\n\n", .{iban_number});
    try testing.expect(iban_number == 61);
}
