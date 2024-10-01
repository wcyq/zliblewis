const std = @import("std");
const hash_map = std.hash_map;
const testing = std.testing;
const math = std.math;

/// A comptime hashmap constructed with automatically selected hash and eql functions.
pub fn AutoStaticHashMap(comptime K: type, comptime V: type) type {
    return StaticHashMap(K, V, hash_map.AutoContext(K));
}

/// Builtin hashmap for strings as keys.
pub fn StringStaticHashMap(comptime V: type) type {
    return StaticHashMap([]const u8, V, hash_map.StringContext);
}

/// A hashmap which is constructed at compile time from constant values.
/// Intended to be used as a faster lookup table.
pub fn StaticHashMap(comptime K: type, comptime V: type, comptime ctx: type) type {
    comptime {
        hash_map.verifyContext(ctx, K, K, u64, false);
    }

    return struct {
        pub const Self = @This();

        const KV = struct {
            key: K,
            val: V,
        };

        const Entry = struct {
            distance_from_start_index: usize = 0,
            pair: KV = undefined,
            used: bool = false,
        };

        pub const context = ctx;

        _entries: []Entry,
        _map_size: usize,
        _max_distance_from_start_index: usize,

        pub fn init(comptime values: anytype) Self {
            std.debug.assert(values.len != 0);
            @setEvalBranchQuota(1000 * values.len);

            // ensure that the hash map will be at most 60% full
            const size = math.ceilPowerOfTwo(usize, values.len * 5 / 3) catch unreachable;
            comptime var slots = [1]Entry{.{}} ** size;

            comptime var max_distance_from_start_index = 0;

            slot_loop: for (values) |kv| {
                var key: K = kv.@"0";
                var value: V = kv.@"1";

                const start_index = @as(usize, ctx.hash(undefined, key)) & (size - 1);

                var roll_over = 0;
                var distance_from_start_index = 0;
                while (roll_over < size) : ({
                    roll_over += 1;
                    distance_from_start_index += 1;
                }) {
                    const index = (start_index + roll_over) & (size - 1);
                    const entry = &slots[index];

                    if (entry.used and !ctx.eql(undefined, entry.key, key)) {
                        if (entry.distance_from_start_index < distance_from_start_index) {
                            // robin hood to the rescue
                            const tmp = slots[index];
                            max_distance_from_start_index = @max(max_distance_from_start_index, distance_from_start_index);
                            entry.* = .{
                                .used = true,
                                .distance_from_start_index = distance_from_start_index,
                                .pair = .{
                                    .key = key,
                                    .val = value,
                                },
                            };
                            key = tmp.key;
                            value = tmp.val;
                            distance_from_start_index = tmp.distance_from_start_index;
                        }
                        continue;
                    }

                    max_distance_from_start_index = @max(distance_from_start_index, max_distance_from_start_index);
                    entry.* = .{
                        .used = true,
                        .distance_from_start_index = distance_from_start_index,
                        .pair = .{
                            .key = key,
                            .val = value,
                        },
                    };
                    continue :slot_loop;
                }
                unreachable; // put into a full map
            }

            return Self{
                ._entries = slots,
                ._map_size = size,
                ._max_distance_from_start_index = max_distance_from_start_index,
            };
        }

        pub fn has(self: Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn get(self: Self, key: K) ?*const V {
            const start_index = @as(usize, ctx.hash(undefined, key)) & (self._entries.len - 1);
            {
                var roll_over: usize = 0;
                while (roll_over <= self._max_distance_from_start_index) : (roll_over += 1) {
                    const index = (start_index + roll_over) & (self._map_size - 1);
                    const entry = &self._entries[index];

                    if (!entry.*.used) {
                        return null;
                    }
                    if (ctx.eql(undefined, entry.*.key, key)) {
                        return &entry.*.val;
                    }
                }
            }
            return null;
        }
    };
}

test "basic usage" {
    const map = StringStaticHashMap(usize).initComptime(.{
        .{ "foo", 1 },
        .{ "bar", 2 },
        .{ "baz", 3 },
        .{ "quux", 4 },
    });

    try testing.expect(map.has("foo"));
    try testing.expect(map.has("bar"));
    try testing.expect(!map.has("zig"));
    try testing.expect(!map.has("ziguana"));

    try testing.expect(map.get("baz").?.* == 3);
    try testing.expect(map.get("quux").?.* == 4);
    try testing.expect(map.get("nah") == null);
    try testing.expect(map.get("...") == null);
}

test "auto comptime hash map" {
    const map = AutoStaticHashMap(usize, []const u8).initComptime(.{
        .{ 1, "foo" },
        .{ 2, "bar" },
        .{ 3, "baz" },
        .{ 45, "quux" },
    });

    try testing.expect(map.has(1));
    try testing.expect(map.has(2));
    try testing.expect(!map.has(4));
    try testing.expect(!map.has(1_000_000));

    try testing.expectEqualStrings("foo", map.get(1).?.*);
    try testing.expectEqualStrings("bar", map.get(2).?.*);
    try testing.expect(map.get(4) == null);
    try testing.expect(map.get(4_000_000) == null);
}
