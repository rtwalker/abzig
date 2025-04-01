const std = @import("std");
const Aiger = @import("aiger.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const NodeKind = enum(u2) { andgate, input, constant };

const Edge = struct {
    inverted: bool,
};

const NodeData = union(NodeKind) {
    fanins: [2]Edge, // andgate
    name: ?[]const u8, // input
    value: bool, // constant
};

const Node = struct {
    const Self = @This();

    id: ID,
    data: NodeData,
    parent: ?*Self,
    level: u16,

    pub const ID = enum(u64) { _ };
};

const Aig = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    nodes: AutoHashMap(u32, *Node),

    inputs: ArrayList(u32),
    outputs: ArrayList(u32),
    height: u16,
    max_var: u32,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .nodes = AutoHashMap(u32, *Node).init(allocator),
            .inputs = ArrayList(u32).init(allocator),
            .outputs = ArrayList(u32).init(allocator),
            .height = 0,
            .max_var = 0,
        };
    }

    pub fn findNode(self: *Self, id: u32) ?*Node {
        return self.nodes.get(id);
    }
};
