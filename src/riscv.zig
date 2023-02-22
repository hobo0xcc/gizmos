extern fn _stack_end() noreturn;
extern fn _stack_start() noreturn;

// NOTE(hobo0xcc): refer boot.S
const kernel_stack_size: usize = 0x1000 - 0x50; // 4016

pub const RiscvError = error {
    StackOutOfRange,
};

pub const Mstatus = enum(usize) {
    SIE = 0b1  << 1,
    MIE = 0b1  << 3,
    SPIE = 0b1 << 5,
};

pub const Mie = enum(usize) {
    MEIE = 0b1 << 11,
};

pub fn assertStackValidity() !void {
    const stack_bottom: usize = @ptrToInt(@as(*const fn() callconv(.C) noreturn, _stack_end)) - kernel_stack_size;
    var sp: usize = 0;
    asm volatile (
        "mv %[sp], sp" : [sp] "=r" (sp),
    );

    if (sp < stack_bottom) {
        return RiscvError.StackOutOfRange;
    }
}

pub fn cpuId() usize {
    var tp: usize = 0x123_4567_89ab_cdef;
    asm volatile ("mv %[tp], tp" : [tp] "=r" (tp));
    return tp;
}

pub fn readCsr(comptime csr: []const u8) usize {
    var ret: usize = 0;
    asm volatile (
        "csrr %[ret], " ++ csr
        : [ret] "=r" (ret) ::
    );
    
    return ret;
}

pub fn writeCsr(comptime csr: []const u8, value: usize) void {
    asm volatile (
        "csrw " ++ csr ++ ", %[value]"
        :: [value] "r" (value) :
    );
}