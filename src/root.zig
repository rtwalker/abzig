const std = @import("std");
const Aiger = @import("aiger.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const NodeKind = enum(u2) { andgate, input, constant };

const Edge = struct {
    inverted: bool,
};

pub const NodeData = union(NodeKind) {
    andgate: struct {
        fanins: [2]Edge,
    },
    input: struct {
        name: ?[]const u8,
    },
    constant: struct {
        value: bool,
    },
};

const Node = struct {
    const Self = @This();

    id: u32,
    data: NodeData,
    fanouts: ArrayList(*Self),
    level: u16,

    pub fn init(allocator: *Allocator, id: u32, data: NodeData, level: u16) !*Self {
        const node = try allocator.create(Self);
        node.* = Self{
            .id = id,
            .data = data,
            .fanouts = ArrayList(*Self).init(allocator),
            .level = level,
        };
        return node;
    }

    pub fn deinit(self: *Self) void {
        self.fanouts.deinit();

        if (self.data == .input and self.data.input.name != null) {
            self.fanouts.allocator.free(self.data.input.name.?);
        }
    }
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

    pub fn deinit(self: *Self) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            const node = entry.value_ptr.*;
            node.deinit();
            self.allocator.destroy(node);
        }

        self.nodes.deinit();
        self.inputs.deinit();
        self.outputs.deinit();
        self.latches.deinit();
    }

    pub fn findNode(self: *Self, id: u32) ?*Node {
        return self.nodes.get(id);
    }

    pub fn bfs(self: Self, visitor: anytype) !void {
        var visited = std.AutoHashMap(u32, void).init(self.allocator);
        defer visited.deinit();

        var queue = std.fifo.LinearFifo(u32, .Dynamic).init(self.allocator);
        defer queue.deinit();

        for (self.outputs.items) |output_lit| {
            const output_id = output_lit >> 1;
            if (output_id > 0) {
                try queue.writeItem(output_id);
                try visited.put(output_id, {});
            }
        }

        while (queue.readItem()) |node_id| {
            const node = self.nodes.get(node_id).?;

            try visitor.visit(node);

            if (node.data == .andgate) {
                for (node.data.andgate.fanins) |edge| {
                    if (!visited.contains(edge.node_id)) {
                        try queue.writeItem(edge.node_id);
                        try visited.put(edge.node_id, {});
                    }
                }
            }
        }
    }
};
