const std = @import("std");
const Riscv = @import("riscv.zig");

comptime {
    asm (
        // _entry here
        @embedFile("boot.S")
    );
}

// Some initializations and calling main function
pub export fn init() noreturn {
    Riscv.initCpu();
    main() catch {
        // Exit qemu with error code when error occurred
        Riscv.exit_qemu(Riscv.ExitStatus.Failure, null);
    };

    while (true) {}
}

pub fn main() !void {
    Riscv.Uart.init();
    const writer = Riscv.Uart.writer();

    try writer.print("hello, {} {}\n", .{42, 1729});

    try Riscv.assertStackValidity();
}