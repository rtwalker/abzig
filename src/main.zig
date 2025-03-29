//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const ArrayList = std.ArrayList;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try parseAiger(allocator, "buffer.aag");

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nSuccess!\n", .{});
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
            .max_var = try parseNextU32(&tokens),
            .inputs = try parseNextU32(&tokens),
            .latches = try parseNextU32(&tokens),
            .outputs = try parseNextU32(&tokens),
            .andgates = try parseNextU32(&tokens),
        };
    };

    var lines = std.mem.tokenizeScalar(u8, body, '\n');

    var inputs = try ArrayList(u32).initCapacity(allocator, header.inputs);
    errdefer inputs.deinit();
    for (0..header.inputs) |_| {
        const input_line = lines.next() orelse return error.UnexpectedEndOfFile;
        var input_tokens = std.mem.tokenizeScalar(u8, input_line, ' ');
        const token = input_tokens.next() orelse return error.InvalidFormat;
        const input = try std.fmt.parseInt(u32, token, 10);

        // Validate - input should be an even, positive integer
        if (input == 0 or input % 2 != 0) return error.InvalidInputLiteral;

        try inputs.append(input);

        // Check for extra unexpected tokens
        if (input_tokens.next() != null) return error.ExtraTokensInLine;
    }

    var latches = try ArrayList(LatchInfo).initCapacity(allocator, header.latches);
    errdefer latches.deinit();
    for (0..header.latches) |_| {
        const latch_line = lines.next() orelse return error.UnexpectedEndOfFile;
        var latch_tokens = std.mem.tokenizeScalar(u8, latch_line, ' ');

        const curr_state_token = latch_tokens.next() orelse return error.InvalidFormat;
        const curr_state = try std.fmt.parseInt(u32, curr_state_token, 10);
        // Validate - current state should be an even, positive integer
        if (curr_state == 0 or curr_state % 2 != 0) return error.InvalidLatchCurrentState;

        const next_state_token = latch_tokens.next() orelse return error.InvalidFormat;
        const next_state = try std.fmt.parseInt(u32, next_state_token, 10);
        // Validate - current state should be an even, positive integer
        if (next_state == 0) return error.InvalidLatchNextState;

        try latches.append(LatchInfo.init(curr_state, next_state));

        // Check for extra unexpected tokens
        if (latch_tokens.next() != null) return error.ExtraTokensInLine;
    }

    var outputs = try ArrayList(u32).initCapacity(allocator, header.outputs);
    errdefer outputs.deinit();
    for (0..header.outputs) |_| {
        const outputs_line = lines.next() orelse return error.UnexpectedEndOfFile;
        var output_tokens = std.mem.tokenizeScalar(u8, outputs_line, ' ');
        const token = output_tokens.next() orelse return error.InvalidFormat;
        const output = try std.fmt.parseInt(u32, token, 10);

        try outputs.append(output);

        // Check for extra unexpected tokens
        if (output_tokens.next() != null) return error.ExtraTokensInLine;
    }

    var andgates = try ArrayList(AndGate).initCapacity(allocator, header.andgates);
    errdefer andgates.deinit();
    for (0..header.andgates) |_| {
        const andgate_line = lines.next() orelse return error.UnexpectedEndOfFile;
        var andgate_tokens = std.mem.tokenizeScalar(u8, andgate_line, ' ');

        const lhs_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const lhs = try std.fmt.parseInt(u32, lhs_token, 10);
        // Validate - lhs should be an even, positive integer
        if (lhs == 0 or lhs % 2 != 0) return error.InvalidAndGateLhs;

        const rhs0_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const rhs0 = try std.fmt.parseInt(u32, rhs0_token, 10);

        const rhs1_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const rhs1 = try std.fmt.parseInt(u32, rhs1_token, 10);

        try andgates.append(AndGate.init(lhs, rhs0, rhs1));

        // Check for extra unexpected tokens
        if (andgate_tokens.next() != null) return error.ExtraTokensInLine;
    }

    const aiger = Aiger.init(header.max_var, inputs, latches, outputs, andgates, lines.rest());

    try stdout.writer().print("Aiger:\n{}", .{aiger});

    return aiger;
}

const Aiger = struct {
    max_var: u32,
    inputs: ArrayList(u32),
    latches: ArrayList(LatchInfo),
    outputs: ArrayList(u32),
    andgates: ArrayList(AndGate),
    body: []const u8,

    pub fn init(max_var: u32, inputs: ArrayList(u32), latches: ArrayList(LatchInfo), outputs: ArrayList(u32), andgates: ArrayList(AndGate), body: []const u8) Aiger {
        return Aiger{
            .max_var = max_var,
            .inputs = inputs,
            .latches = latches,
            .outputs = outputs,
            .andgates = andgates,
            .body = body,
        };
    }

    pub fn deinit(self: *Aiger) void {
        self.inputs.deinit();
        self.latches.deinit();
        self.outputs.deinit();
        self.andgates.deinit();
    }
};

const LatchInfo = struct {
    curr_state: u32,
    next_state: u32,

    pub fn init(curr_state: u32, next_state: u32) LatchInfo {
        return LatchInfo{
            .curr_state = curr_state,
            .next_state = next_state,
        };
    }
};

const AndGate = struct {
    lhs: u32,
    rhs: [2]u32,

    pub fn init(lhs: u32, rhs0: u32, rhs1: u32) AndGate {
        return AndGate{
            .lhs = lhs,
            .rhs = [2]u32{ rhs0, rhs1 },
        };
    }
};
