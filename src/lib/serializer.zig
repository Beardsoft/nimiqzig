const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;

pub const Serializer = struct {
    buffer: std.ArrayListAligned(u8, null) = undefined,
    state: enum(u2) {
        Init,
        Freed,
        InUse,
    } = .Init,

    pub const SerializerError = error{
        NotInitialized,
        AlreadyInitialized,
        Freed,
        AlreadyFreed,
    };

    pub fn init(self: *Serializer, allocator: Allocator) !void {
        if (self.state == .InUse) return SerializerError.AlreadyInitialized;
        if (self.state == .Freed) return SerializerError.Freed;

        self.buffer = ArrayList(u8).init(allocator);
        self.state = .InUse;
    }

    pub fn deinit(self: *Serializer) !void {
        if (self.state == .Init) return SerializerError.NotInitialized;
        if (self.state == .Freed) return SerializerError.AlreadyFreed;

        self.buffer.deinit();
        self.state = .Freed;
    }
};

test "Serializer: init / deinit" {
    const allocator = testing.allocator;
    var serializer = Serializer{};

    // Deinit on uninitialized => expect error
    var result = serializer.deinit();
    try testing.expectError(Serializer.SerializerError.NotInitialized, result);

    // First init => expect ok
    try serializer.init(allocator);

    // Double init => expect error
    result = serializer.init(allocator);
    try testing.expectError(Serializer.SerializerError.AlreadyInitialized, result);

    // Deinit after init => expect ok
    try serializer.deinit();

    // Double deinit => expect error
    result = serializer.deinit();
    try testing.expectError(Serializer.SerializerError.AlreadyFreed, result);
}
