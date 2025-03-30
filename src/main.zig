//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try parseAiger(allocator, "halfadder.aag");

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

        const output_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const output = try std.fmt.parseInt(u32, output_token, 10);
        // Validate - output should be an even, positive integer
        if (output == 0 or output % 2 != 0) return error.InvalidAndGateOutput;

        const input0_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const input0 = try std.fmt.parseInt(u32, input0_token, 10);

        const input1_token = andgate_tokens.next() orelse return error.InvalidFormat;
        const input1 = try std.fmt.parseInt(u32, input1_token, 10);

        try andgates.append(AndGate.init(output, input0, input1));

        // Check for extra unexpected tokens
        if (andgate_tokens.next() != null) return error.ExtraTokensInLine;
    }

    var symbols = SymbolTable.init(allocator);
    defer symbols.deinit();
    while (lines.peek()) |next_line| {
        // Check if we've reached the comment section
        if (next_line.len > 0 and next_line[0] == 'c') {
            break;
        }

        // Confirm this is a symbol line
        if (next_line.len < 2) break;
        if (std.mem.indexOfAny(u8, "ilo", next_line[0..1]) == null) break;

        _ = lines.next();

        var symbol_tokens = std.mem.splitScalar(u8, next_line, ' ');
        const type_specifier = symbol_tokens.next() orelse return error.InvalidFormat;

        const symbol_type = type_specifier[0];
        const position_str = type_specifier[1..];
        const index = std.fmt.parseInt(u32, position_str, 10) catch continue;

        const name = symbol_tokens.next() orelse continue;

        switch (symbol_type) {
            'i' => try symbols.input_names.put(index, try allocator.dupe(u8, name)),
            'l' => try symbols.latch_names.put(index, try allocator.dupe(u8, name)),
            'o' => try symbols.output_names.put(index, try allocator.dupe(u8, name)),
            else => return error.InvalidFormat,
        }
    }

    var comments: ?[]const u8 = null;
    errdefer if (comments) |c| allocator.free(c);

    if (lines.peek()) |next_line| {
        if (next_line.len > 0 and next_line[0] == 'c') {
            _ = lines.next();
            var remaining_content: []const u8 = "";
            if (lines.rest().len > 0) {
                remaining_content = try allocator.dupe(u8, lines.rest());
                comments = remaining_content;
            }
        }
    }

    const aiger = Aiger.init(header.max_var, inputs, latches, outputs, andgates, symbols, comments);

    try stdout.writer().print("Aiger:\n{}", .{aiger});

    return aiger;
}

const Aiger = struct {
    max_var: u32,
    inputs: ArrayList(u32),
    latches: ArrayList(LatchInfo),
    outputs: ArrayList(u32),
    andgates: ArrayList(AndGate),
    symbols: SymbolTable,
    comments: ?[]const u8,

    pub fn init(max_var: u32, inputs: ArrayList(u32), latches: ArrayList(LatchInfo), outputs: ArrayList(u32), andgates: ArrayList(AndGate), symbols: SymbolTable, comments: ?[]const u8) Aiger {
        return Aiger{
            .max_var = max_var,
            .inputs = inputs,
            .latches = latches,
            .outputs = outputs,
            .andgates = andgates,
            .symbols = symbols,
            .comments = comments,
        };
    }

    pub fn deinit(self: *Aiger) void {
        self.inputs.deinit();
        self.latches.deinit();
        self.outputs.deinit();
        self.andgates.deinit();
        self.symbols.deinit();
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
    output: u32,
    inputs: [2]u32,

    pub fn init(output: u32, input0: u32, input1: u32) AndGate {
        return AndGate{
            .output = output,
            .inputs = [2]u32{ input0, input1 },
        };
    }
};

const SymbolTable = struct {
    input_names: std.AutoHashMap(u32, []const u8),
    latch_names: std.AutoHashMap(u32, []const u8),
    output_names: std.AutoHashMap(u32, []const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{
            .input_names = std.AutoHashMap(u32, []const u8).init(allocator),
            .latch_names = std.AutoHashMap(u32, []const u8).init(allocator),
            .output_names = std.AutoHashMap(u32, []const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        var input_it = self.input_names.iterator();
        while (input_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.input_names.deinit();

        var latch_it = self.latch_names.iterator();
        while (latch_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.latch_names.deinit();

        var output_it = self.output_names.iterator();
        while (output_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.output_names.deinit();
    }
};
