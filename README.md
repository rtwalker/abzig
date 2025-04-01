# abzig

porting [ABC](https://github.com/berkeley-abc/abc) to Zig

## Example

```bash
$ abzig read examples/halfadder.aag
Contents:
aag 7 2 0 2 3
2
4
6
12
6 13 15
12 2 4
14 3 5
i0 x
i1 y
o0 s
o1 c
c
half adder
Aiger:
aiger.Aiger{ .max_var = 7, .inputs = array_list.ArrayListAligned(u32,null){ .items = { 2, 4 }, .capacity = 2, .allocator = mem.Allocator{ .ptr = anyopaque@16f4f7bf0, .vtable = mem.Allocator.VTable{ ... } } }, .latches = array_list.ArrayListAligned(aiger.LatchInfo,null){ .items = {  }, .capacity = 0, .allocator = mem.Allocator{ .ptr = anyopaque@16f4f7bf0, .vtable = mem.Allocator.VTable{ ... } } }, .outputs = array_list.ArrayListAligned(u32,null){ .items = { 6, 12 }, .capacity = 2, .allocator = mem.Allocator{ .ptr = anyopaque@16f4f7bf0, .vtable = mem.Allocator.VTable{ ... } } }, .andgates = array_list.ArrayListAligned(aiger.AndGate,null){ .items = { aiger.AndGate{ ... }, aiger.AndGate{ ... }, aiger.AndGate{ ... } }, .capacity = 3, .allocator = mem.Allocator{ .ptr = anyopaque@16f4f7bf0, .vtable = mem.Allocator.VTable{ ... } } }, .symbols = aiger.SymbolTable{ .input_names = hash_map.HashMap(u32,[]const u8,hash_map.AutoContext(u32),80){ .unmanaged = hash_map.HashMapUnmanaged(u32,[]const u8,hash_map.AutoContext(u32),80){ ... }, .allocator = mem.Allocator{ ... }, .ctx = hash_map.AutoContext(u32){ ... } }, .latch_names = hash_map.HashMap(u32,[]const u8,hash_map.AutoContext(u32),80){ .unmanaged = hash_map.HashMapUnmanaged(u32,[]const u8,hash_map.AutoContext(u32),80){ ... }, .allocator = mem.Allocator{ ... }, .ctx = hash_map.AutoContext(u32){ ... } }, .output_names = hash_map.HashMap(u32,[]const u8,hash_map.AutoContext(u32),80){ .unmanaged = hash_map.HashMapUnmanaged(u32,[]const u8,hash_map.AutoContext(u32),80){ ... }, .allocator = mem.Allocator{ ... }, .ctx = hash_map.AutoContext(u32){ ... } }, .allocator = mem.Allocator{ .ptr = anyopaque@16f4f7bf0, .vtable = mem.Allocator.VTable{ ... } } }, .comments = { 104, 97, 108, 102, 32, 97, 100, 100, 101, 114 } }
Success!
```
