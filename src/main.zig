//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const Aiger = @import("aiger.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len <= 2) {
        try printUsage(stdout);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "read")) {
        var aiger = try Aiger.parseAiger(allocator, args[2]);
        defer aiger.deinit();

        // TODO
        // var aig = try Aig.fromAiger(allocator, &aiger);
        // defer aig.deinit();

        try stdout.print("\nSuccess!\n", .{});
    } else if (std.mem.eql(u8, command, "bfs")) {
        var aiger = try Aiger.parseAiger(allocator, args[2]);
        defer aiger.deinit();

        // TODO
        // var aig = try Aig.fromAiger(allocator, &aiger);
        // defer aig.deinit();
        //
        // const Visitor = struct {
        //     count: u32 = 0,
        //     pub fn visit(self: *@This(), node: *Aig.Node) !void {
        //         self.count += 1;
        //         std.debug.print("Visiting node {d} (level: {d})\n", .{ node.id, node.level });
        //     }
        // };
        // var visitor = Visitor{};
        // try aig.bfs(&visitor);
    } else if (std.mem.eql(u8, command, "help")) {
        try printUsage(stdout);
    } else {
        try stdout.print("Unknown command: {s}\n", .{command});
        try printUsage(stdout);
        std.process.exit(1);
    }
}

fn printUsage(writer: std.fs.File.Writer) !void {
    try writer.writeAll(
        \\Usage: abzig <command> [arguments]
        \\
        \\Commands:
        \\  read <file_path>    Read AIGER file (ASCII only)
        \\  help                Print this help message
        \\
    );
}
