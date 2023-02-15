const uart_base_addr: *volatile u8 = @intToPtr(*volatile u8, 0x10000000);
extern fn _stack_end() noreturn;

pub export fn _entry() linksection(".entry") callconv(.Naked) noreturn {
    asm volatile (
        @embedFile("boot.S")
    );
    uartWrite('A');
    uartWrite('B');
    while (true) {}
}

pub fn uartWrite(ch: u8) void {
    uart_base_addr.* = ch;
}
