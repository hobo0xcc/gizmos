const std = @import("std");
const Riscv = @import("riscv.zig");
// TODO(hobo0xcc): Bring Uart and Interrupt into riscv.zig
const Uart = @import("uart.zig");
const Interrupt = @import("interrupt.zig");

comptime {
    asm (
        // _entry here
        @embedFile("boot.S")
    );
}

// Initialize whole system and then call main
pub export fn start() noreturn {
    initCpu();
    main() catch {
        // Exit qemu with error code when error occurred
        Riscv.exit_qemu(Riscv.ExitStatus.Failure, null);
    };

    while (true) {}
}

pub fn main() !void {
    Uart.init();
    const writer = Uart.writer();

    try writer.print("hello, {} {}\n", .{42, 1729});

    try Riscv.assertStackValidity();
}

fn initCpu() void {
    // Enable interrupt
    Riscv.writeCsr("mstatus", Riscv.readCsr("mstatus") | @enumToInt(Riscv.Mstatus.MIE));
    Riscv.writeCsr("mie",     Riscv.readCsr("mie") | @enumToInt(Riscv.Mie.MEIE));

    // Set interrupt handler
    const handler_addr = @ptrToInt(@as(*const fn() align(4) callconv(.Naked) noreturn, Interrupt._interrupt));
    Riscv.writeCsr("mtvec", handler_addr);

    // Set mhartid to tp register for use in cpuid
    // mhartid is a CPU id that this program is currently running on.
    const id = Riscv.readCsr("mhartid");
    asm volatile ("mv tp, %[id]" :: [id] "r" (id));

    Interrupt.initPlic();
    // NOTE(hobo0xcc): Currently there's no SMP support
    // but in the future SMP might be added so this could be changed then.
    Interrupt.initPlicForHart();
}
