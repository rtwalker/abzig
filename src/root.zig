const std = @import("std");
const ArrayList = std.ArrayList;

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
