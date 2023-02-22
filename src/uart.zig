const std = @import("std");
const io = std.io;

const Self = @This();

const WriteError: type = std.os.WriteError;
const Writer = io.Writer(Self, WriteError, write);

const uart_base_addr: [*]volatile u8 = @intToPtr([*]volatile u8, 0x10000000);

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

pub fn readReg(reg_offset: usize) u8 {
    return uart_base_addr[reg_offset];
}

pub fn writeReg(reg_offset: usize, bits: u8) void {
    uart_base_addr[reg_offset] = bits;
}

pub fn readChar() ?u8 {
    if (readReg(LSR_ro) & LSR_data_available != 0) {
        return readReg(RBR_ro);
    } else {
        return null;
    }
}

pub fn writeChar(ch: u8) void {
    writeReg(THR_wo, ch);
}

pub fn write(_: Self, bytes: []const u8) WriteError!usize {
    for (bytes) |byte| {
        writeChar(byte);
    }

    return bytes.len;
}

pub fn writer(self: Self) Writer {
    return .{ .context = self };
}

pub fn handleInterrupt() void {
    // refer: https://www.lammertbies.nl/comm/info/serial-uart
    // IIR : Interrupt identification register
    const IIR = readReg(IIR_ro);
    _ = IIR;
    while (readChar()) |ch| {
        writeChar(ch);
    }
}

// refer: https://github.com/mit-pdos/xv6-riscv/blob/7086197c27f7c00544ca006561336d8d5791a482/kernel/uart.c#L55-L77
pub fn init() Self {
    // Disable interrupt
    writeReg(IER_rw, 0x00);   

    // Set baud rate
    // Make DLL and DLM accessible
    writeReg(LCR_rw, LCR_baud_latch);
    // 38,400 bps
    writeReg(DLL_rw, 0x03);
    writeReg(DLM_rw, 0x00);

    // Set word length to 8-bits
    writeReg(LCR_rw, LCR_eight_bits);

    // Reset and enable FIFOs
    // NOTE(hobo0xcc): I don't understand how FIFO works in UART.
    writeReg(FCR_wo, FCR_enable_fifo | FCR_clear_fifo);

    // Enable transmit and receive interrupts
    writeReg(IER_rw, IER_receiver_ready | IER_transmitter_empty);

    return .{};
}