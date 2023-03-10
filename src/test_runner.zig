const std = @import("std");
const Riscv = @import("riscv.zig");
const builtin = @import("builtin");

pub fn main() !void {
    Riscv.Uart.init();
    const writer = Riscv.Uart.writer();

    std.debug.assert(builtin.is_test);

    try writer.print("Running tests...\n", .{});
    try testRunner();
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;
    _ = ret_addr;
    const writer = Riscv.Uart.writer();
    writer.print("[Test] Panic occurred: {s}\n", .{msg}) catch |e| {
        Riscv.exitQemu(Riscv.ExitStatus.Failure, @errorToInt(e));
    };

    Riscv.exitQemu(Riscv.ExitStatus.Failure, @errorToInt(Riscv.RiscvError.Panic));
}

pub fn testRunner() !void {
    const writer = Riscv.Uart.writer();

    var skipped: usize = 0;
    var failed: usize = 0;
    var counter: usize = 1;

    for (builtin.test_functions) |test_fn| {
        try writer.print("Test [{}/{}] {s}...\n", .{ counter, builtin.test_functions.len, test_fn.name });

        test_fn.func() catch |err| {
            if (err != error.SkipZigTest) {
                failed += 1;
            } else {
                skipped += 1;
            }
        };

        counter += 1;
    }

    if (failed == 0) {
        try writer.print("All {d} tests passed.\n", .{builtin.test_functions.len - skipped});
    } else {
        try writer.print("{d} passed; {d} skipped; {d} failed.\n", .{ builtin.test_functions.len - skipped - failed, skipped, failed });
        return Riscv.RiscvError.TestFailed;
    }
}
