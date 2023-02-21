// refer: https://www.lammertbies.nl/comm/info/serial-uart
const RBR_ro: usize = 0; // base + 0, read only (ro)
const THR_wo: usize = 0; // base + 0, write only (wo)
const DLL_rw: usize = 0; // base + 0, read write (rw)
const IER_rw: usize = 1;
const DLM_rw: usize = 1;
const IIR_ro: usize = 2;
const FCR_wo: usize = 2;
const LCR_rw: usize = 3;
const MCR_rw: usize = 4;
const LSR_ro: usize = 5;
const MSR_ro: usize = 6;
const SCR_rw: usize = 7;

const IER_receiver_ready: u8 = 0b0000_0001; // Enable bit for the receiver ready interrupt
const IER_transmitter_empty: u8 = 0b0000_0010;
const FCR_enable_fifo: u8 = 0b0000_0001;
const FCR_clear_fifo: u8 = 0b0000_0010;
const LCR_baud_latch: u8 = 0b1000_0000;
const LCR_eight_bits: u8 = 0b0000_0011;
const LSR_data_available: u8 = 0b0000_0001;

const uart_base_addr: [*]volatile u8 = @intToPtr([*]volatile u8, 0x10000000);

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
    MachineExternalInterrupt = 11,
};

const Mstatus = enum(usize) {
    SIE = 0b1  << 1,
    MIE = 0b1  << 3,
    SPIE = 0b1 << 5,
};

const Mie = enum(usize) {
    MEIE = 0b1 << 11,
};

extern fn _stack_end() noreturn;

comptime {
    asm (
        // _entry here
        @embedFile("boot.S")
    );
}

pub export fn main() callconv(.Naked) noreturn {
    initCpu();

    uartInit();

    uartWrite('A');
    uartWrite('B');

    while (true) {}
}

fn initCpu() void {
    // Enable interrupt
    writeCsr("mstatus", readCsr("mstatus") | @enumToInt(Mstatus.MIE));
    writeCsr("mie",     readCsr("mie") | @enumToInt(Mie.MEIE));
    // Set interrupt handler
    const handler_addr = @ptrToInt(@as(*const fn() align(4) callconv(.Naked) noreturn, _interrupt));
    writeCsr("mtvec", handler_addr);

    // Set mhartid to tp register for use in cpuid
    // mhartid is a CPU id that this program is currently running on.
    const id = readCsr("mhartid");
    asm volatile ("mv tp, %[id]" :: [id] "r" (id));

    initPlic();
    // NOTE(hobo0xcc): Currently there's no SMP
    // but in the future SMP might be added so this could be changed then.
    initPlicForHart();
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7c958af7828973787f3c327854ba71dd3077ad2d/kernel/plic.c#L14-L16
fn initPlic() void {
    // Set IRQ priorities to non-zero (to enable interrupt)
    const uart_irq = @intCast(usize, @enumToInt(Irq.Uart0));
    plicBase()[uart_irq] = 1;
}

fn initPlicForHart() void {
    const hart = cpuId();

    // Enable bits for this hart
    const m_enable = plicMenableAddr(hart);
    m_enable.* = 1 << @enumToInt(Irq.Uart0);

    const m_priority = plicMpriorityAddr(hart);
    m_priority.* = 0;
}

fn plicBase() [*]volatile u32 {
    return @intToPtr([*]volatile u32, plic_base_addr);
}

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

fn plicClaim() Irq {
    const hart = cpuId();
    const irq = plicMclaimAddr(hart).*;
    switch (irq) {
        10 => {},
        else => {
            // TODO(hobo0xcc): Panic
        }
    }
    return @intToEnum(Irq, irq & 0xff);
}

fn plicComplete(irq: Irq) void {
    const hart = cpuId();
    plicMclaimAddr(hart).* = @enumToInt(irq);
}

fn cpuId() usize {
    var tp: usize = 0x123_4567_89ab_cdef;
    asm volatile ("mv %[tp], tp" : [tp] "=r" (tp));
    return tp;
}

fn readCsr(comptime csr: []const u8) usize {
    var ret: usize = 0;
    asm volatile (
        "csrr %[ret], " ++ csr
        : [ret] "=r" (ret) ::
    );
    
    return ret;
}

fn writeCsr(comptime csr: []const u8, value: usize) void {
    asm volatile (
        "csrw " ++ csr ++ ", %[value]"
        :: [value] "r" (value) :
    );
}

fn isInterrupt(cause: usize) bool {
    return (cause & (1 << 63)) != 0;
}

fn isMachineExternalInterrupt(cause: usize) bool {
    return isInterrupt(cause) and (cause & 0xff) == @enumToInt(ExceptionCode.MachineExternalInterrupt);
}

fn uartHandleInterrupt() void {
    // refer: https://www.lammertbies.nl/comm/info/serial-uart
    // IIR : Interrupt identification register
    const IIR = uartReadReg(IIR_ro);
    _ = IIR;
    while (uartGet()) |ch| {
        uartWrite(ch);
    }
}

export fn handleInterrupt() void {
    const cause = readCsr("mcause");

    if (isMachineExternalInterrupt(cause)) {
        const irq = plicClaim();

        // Handle plic external interrupt
        switch (irq) {
            .Uart0 => {
                uartHandleInterrupt();
            }
        }

        plicComplete(irq);
    } else {
        // TODO(hobo0xcc): Handle normal interrupts and exceptions
    }
}

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

fn uartReadReg(reg_offset: usize) u8 {
    return uart_base_addr[reg_offset];
}

fn uartWriteReg(reg_offset: usize, bits: u8) void {
    uart_base_addr[reg_offset] = bits;
}

fn uartGet() ?u8 {
    if (uartReadReg(LSR_ro) & LSR_data_available != 0) {
        return uartReadReg(RBR_ro);
    } else {
        return null;
    }
}

fn uartWrite(ch: u8) void {
    uartWriteReg(THR_wo, ch);
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7086197c27f7c00544ca006561336d8d5791a482/kernel/uart.c#L55-L77
fn uartInit() void {
    // Disable interrupt
    uartWriteReg(IER_rw, 0x00);   

    // Set baud rate
    // Make DLL and DLM accessible
    uartWriteReg(LCR_rw, LCR_baud_latch);
    // 38,400 bps
    uartWriteReg(DLL_rw, 0x03);
    uartWriteReg(DLM_rw, 0x00);

    // Set word length to 8-bits
    uartWriteReg(LCR_rw, LCR_eight_bits);

    // Reset and enable FIFOs
    // NOTE(hobo0xcc): I don't understand how FIFO works in UART.
    uartWriteReg(FCR_wo, FCR_enable_fifo | FCR_clear_fifo);

    // Enable transmit and receive interrupts
    uartWriteReg(IER_rw, IER_receiver_ready | IER_transmitter_empty);
}
