pub const Mstatus = enum(usize) {
    SIE = 0b1  << 1,
    MIE = 0b1  << 3,
    SPIE = 0b1 << 5,
};

pub const Mie = enum(usize) {
    MEIE = 0b1 << 11,
};

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