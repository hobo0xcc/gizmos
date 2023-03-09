const Riscv = @import("riscv.zig");
const Uart = @import("uart.zig");

const plic_base_addr: usize = 0x0c000000;
const plic_priority: usize = plic_base_addr + 0x0;
const plic_pending: usize = plic_base_addr + 0x1000;
const plic_menable_base: usize = plic_base_addr + 0x2000;
const plic_mpriority_base: usize = plic_base_addr + 0x200000;
const plic_mclaim_base: usize = plic_base_addr + 0x200004;

const Irq = enum(u32) {
    Uart0 = 10,
};

const ExceptionCode = enum(usize) {
    // Interrupts
    const InterruptFlag: usize = 0b1 << 63;
    SupervisorSoftwareInterrupt = InterruptFlag | 1,
    MachineSoftwareInterrupt = InterruptFlag | 3,
    SupervisorTimerInterrupt = InterruptFlag | 5,
    MachineTimerInterrupt = InterruptFlag | 7,
    SupervisorExternalInterrupt = InterruptFlag | 9,
    MachineExternalInterrupt = InterruptFlag | 11,

    InstructionAddressMisaligned = 0,
    InstructionAccessFault = 1,
    IllegalInstruction = 2,
    Breakpoint = 3,
    LoadAddressMisaligned = 4,
    LoadAccessFault = 5,
    StoreAMOAddressMisaligned = 6,
    StoreAMOAccessFault = 7,
    EnvironmentCallFromUMode = 8,
    EnvironmentCallFromSMode = 9,
    EnvironmentCallFromMMode = 11,
    InstructionPageFault = 12,
    LoadPageFault = 13,
    StoreAMOPageFault = 15,

    Reserved,
    Undefined,

    const Self = @This();

    pub fn val(self: Self) usize {
        return @enumToInt(self);
    }

    pub fn isInterrupt(self: Self) bool {
        return (self.val() & InterruptFlag) != 0;
    }

    pub fn isException(self: Self) bool {
        return !self.isInterrupt();
    }

    pub fn from(cause: usize) Self {
        // See RISC-V Previleged Spec Table 3.6: Machine cause register (mcause) values after trap.
        return @intToEnum(Self, cause);
    }
};

// Save registers and jump to handleInterrupt
pub export fn _interrupt() align(4) callconv(.Naked) noreturn {
    // Save registers
    // refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/kernelvec.S#L13-L47
    asm volatile (
        \\ addi sp, sp, -256
        \\ sd ra, 0(sp)
        \\ sd sp, 8(sp)
        \\ sd gp, 16(sp)
        \\ sd tp, 24(sp)
        \\ sd t0, 32(sp)
        \\ sd t1, 40(sp)
        \\ sd t2, 48(sp)
        \\ sd s0, 56(sp)
        \\ sd s1, 64(sp)
        \\ sd a0, 72(sp)
        \\ sd a1, 80(sp)
        \\ sd a2, 88(sp)
        \\ sd a3, 96(sp)
        \\ sd a4, 104(sp)
        \\ sd a5, 112(sp)
        \\ sd a6, 120(sp)
        \\ sd a7, 128(sp)
        \\ sd s2, 136(sp)
        \\ sd s3, 144(sp)
        \\ sd s4, 152(sp)
        \\ sd s5, 160(sp)
        \\ sd s6, 168(sp)
        \\ sd s7, 176(sp)
        \\ sd s8, 184(sp)
        \\ sd s9, 192(sp)
        \\ sd s10, 200(sp)
        \\ sd s11, 208(sp)
        \\ sd t3, 216(sp)
        \\ sd t4, 224(sp)
        \\ sd t5, 232(sp)
        \\ sd t6, 240(sp)
        \\ call handleInterrupt
        \\ ld ra, 0(sp)
        \\ ld sp, 8(sp)
        \\ ld gp, 16(sp)
        // not tp (contains hartid), in case we moved CPUs
        \\ ld t0, 32(sp)
        \\ ld t1, 40(sp)
        \\ ld t2, 48(sp)
        \\ ld s0, 56(sp)
        \\ ld s1, 64(sp)
        \\ ld a0, 72(sp)
        \\ ld a1, 80(sp)
        \\ ld a2, 88(sp)
        \\ ld a3, 96(sp)
        \\ ld a4, 104(sp)
        \\ ld a5, 112(sp)
        \\ ld a6, 120(sp)
        \\ ld a7, 128(sp)
        \\ ld s2, 136(sp)
        \\ ld s3, 144(sp)
        \\ ld s4, 152(sp)
        \\ ld s5, 160(sp)
        \\ ld s6, 168(sp)
        \\ ld s7, 176(sp)
        \\ ld s8, 184(sp)
        \\ ld s9, 192(sp)
        \\ ld s10, 200(sp)
        \\ ld s11, 208(sp)
        \\ ld t3, 216(sp)
        \\ ld t4, 224(sp)
        \\ ld t5, 232(sp)
        \\ ld t6, 240(sp)
        \\ addi sp, sp, 256
        \\ mret
    );

    while (true) {}
}

pub export fn handleInterrupt() void {
    const cause = Riscv.readCsr("mcause");
    const exception_code = ExceptionCode.from(cause);

    switch (exception_code) {
        ExceptionCode.MachineExternalInterrupt => {
            const irq = plicClaim();

            // Handle plic external interrupt
            switch (irq) {
                .Uart0 => {
                    Uart.handleInterrupt();
                },
            }

            plicComplete(irq);
        },
        else => |code| {
            if (code.isException()) {
                handleUnrecoverableException(exception_code) catch {};
            }
        },
    }
}

pub fn handleUnrecoverableException(code: ExceptionCode) !void {
    const writer = Riscv.Uart.writer();
    try writer.print("Unrecoverable Exception occurred !!", .{});

    const mcause = Riscv.readCsr("mcause");
    const mtvec = Riscv.readCsr("mtvec");
    const mtval = Riscv.readCsr("mtval");
    const mepc = Riscv.readCsr("mepc");

    try writer.print("\n{s}\n", .{"-" ** 20});

    try writer.print("ExceptionCode: {}\n", .{code});
    try writer.print("mcause: 0x{x}\n", .{mcause});
    try writer.print("mtvec: 0x{x}\n", .{mtvec});
    try writer.print("mtval: 0x{x}\n", .{mtval});
    try writer.print("mepc: 0x{x}\n", .{mepc});

    try writer.print("{s}\n", .{"-" ** 20});

    @panic("Unrecoverable Exception");
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/plic.c#L14-L16
pub fn initPlic() void {
    // Set IRQ priorities to non-zero (to enable interrupt)
    const uart_irq = @intCast(usize, @enumToInt(Irq.Uart0));
    plicBase()[uart_irq] = 1;
}

pub fn initPlicForHart() void {
    const hart = Riscv.cpuId();

    // Enable bits for this hart
    const m_enable = plicMenableAddr(hart);
    m_enable.* = 1 << @enumToInt(Irq.Uart0);

    const m_priority = plicMpriorityAddr(hart);
    m_priority.* = 0;
}

fn plicBase() [*]volatile u32 {
    return @intToPtr([*]volatile u32, plic_base_addr);
}

// TODO(hobo0xcc): Refine
// refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/memlayout.h#L37
fn plicMenableAddr(hart: usize) *volatile u32 {
    const base_addr_value = plic_menable_base;
    return @intToPtr(*volatile u32, base_addr_value + (hart * 0x100));
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/memlayout.h#L39
fn plicMpriorityAddr(hart: usize) *volatile u32 {
    const base_addr_value = plic_mpriority_base;
    return @intToPtr(*volatile u32, base_addr_value + (hart * 0x2000));
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/memlayout.h#L41
fn plicMclaimAddr(hart: usize) *volatile u32 {
    const base_addr_value = plic_mclaim_base;
    return @intToPtr(*volatile u32, base_addr_value + (hart * 0x2000));
}

pub fn plicClaim() Irq {
    const hart = Riscv.cpuId();
    const irq = plicMclaimAddr(hart).*;
    switch (irq) {
        10 => {},
        else => {
            // TODO(hobo0xcc): Panic
        },
    }
    return @intToEnum(Irq, irq & 0xff);
}

pub fn plicComplete(irq: Irq) void {
    const hart = Riscv.cpuId();
    plicMclaimAddr(hart).* = @enumToInt(irq);
}
