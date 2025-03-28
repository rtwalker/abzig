//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = try parseAiger(allocator, "buffer.aag");

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nSuccess!", .{});
}

const NodeKind = enum(u2) { andgate, input, constant };

const Edge = struct {
    node: u32,
    inverted: bool,
};

const NodeData = union(NodeKind) {
    fanins: [2]Edge, // andgate
    name: ?[]const u8, // input
    value: bool, // constant
};

const Node = struct { id: u32, data: NodeData, level: u16 };

const Aig = struct {
    nodes: ArrayList(Node),
    height: u16,
};

pub fn readFile(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    return try file.readToEndAlloc(allocator, file_size);
}

/// An AIGER file in ASCII format starts with the format identifier
/// string 'aag' for ASCII AIG and 5 non negative integers 'M', 'I',
/// 'L', 'O', 'A' separated by spaces.
///
///   The interpretation of the integers is as follows
///
///     M = maximum variable index
///     I = number of inputs
///     L = number of latches
///     O = number of outputs
///     A = number of AND gates
pub fn parseAiger(allocator: std.mem.Allocator, filename: []const u8) !Aiger {
    const contents = try readFile(allocator, filename);
    defer allocator.free(contents);

    const stdout = std.io.getStdOut();
    try stdout.writer().print("Contents:\n", .{});
    try stdout.writeAll(contents);
    try stdout.writer().print("\n", .{});

    const eol_index = std.mem.indexOfScalar(u8, contents, '\n') orelse contents.len;
    const first_line = contents[0..eol_index];
    const body = if (eol_index < contents.len) contents[eol_index + 1 ..] else "";

    const header = blk: {
        var tokens = std.mem.tokenizeScalar(u8, first_line, ' ');

        const format = tokens.next() orelse return error.InvalidFormat;
        // only parsing ASCII format for now
        if (!std.mem.eql(u8, format, "aag")) return error.InvalidFormat;

        const parseNextU32 = struct {
            fn parse(iter: *std.mem.TokenIterator(u8, .scalar)) !u32 {
                const token = iter.next() orelse return error.InvalidFormat;
                return std.fmt.parseInt(u32, token, 10);
            }
        }.parse;

        break :blk .{
            .max_index = try parseNextU32(&tokens),
            .inputs = try parseNextU32(&tokens),
            .latches = try parseNextU32(&tokens),
            .outputs = try parseNextU32(&tokens),
            .andgates = try parseNextU32(&tokens),
        };
    };

    const aiger = Aiger.init(header.max_index, header.inputs, header.latches, header.outputs, header.andgates, body);

    try stdout.writer().print("Aiger:\n{}", .{aiger});

    return aiger;
}

const Aiger = struct {
    max_index: u32,
    inputs: u32,
    latches: u32,
    outputs: u32,
    andgates: u32,
    body: []const u8,

    pub fn init(max_index: u32, inputs: u32, latches: u32, outputs: u32, andgates: u32, body: []const u8) Aiger {
        return Aiger{
            .max_index = max_index,
            .inputs = inputs,
            .latches = latches,
            .outputs = outputs,
            .andgates = andgates,
            .body = body,
        };
    }
};
