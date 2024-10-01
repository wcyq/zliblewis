pub const char = u8; // Standard character type
pub const wchar = u16; // Large character type for unicode (UTF-16)

pub const zstring = []char;
pub const zstringlit = []const char;

pub const string = [:0]char;
pub const stringlit = [:0]const char;

pub const cstring = [*:0]char;
pub const cstringlit = [*:0]const char;
