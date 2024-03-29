const builtin = @import("builtin");
const std = @import("std");
const root = @import("root");
const Riscv = @import("riscv.zig");

// Function calling order
// _entry -> init() -> main()

comptime {
    asm (
    // _entry here
        @embedFile("boot.S"));
}

// Some initializations and calling main function
pub export fn init() noreturn {
    Riscv.initCpu();
    root.main() catch |e| {
        // Exit qemu with error code when error occurred
        Riscv.exitQemu(Riscv.ExitStatus.Failure, @errorToInt(e));
    };

    if (builtin.is_test) {
        Riscv.exitQemu(Riscv.ExitStatus.Success, null);
    }

    while (true) {}
}

pub fn main() !void {
    Riscv.Uart.init();
    const writer = Riscv.Uart.writer();

    try writer.print("Welcome to gizmos!\n", .{});
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;
    _ = ret_addr;
    const writer = Riscv.Uart.writer();
    writer.print("Panic occurred: {s}\n", .{msg}) catch |e| {
        Riscv.exitQemu(Riscv.ExitStatus.Failure, @errorToInt(e));
    };

    Riscv.exitQemu(Riscv.ExitStatus.Failure, @errorToInt(Riscv.RiscvError.Panic));
}

const testing = std.testing;

test "Hello" {
    const writer = Riscv.Uart.writer();
    try writer.print("Hello\n", .{});
    try testing.expect(1 == 1);
}

test "Goodbye" {
    const writer = Riscv.Uart.writer();
    try writer.print("Goodbye\n", .{});
    try testing.expect(42 == 42);
}
