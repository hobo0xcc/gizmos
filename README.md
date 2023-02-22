A WebAssembly-based "macrokernel" operating system

This project is work in progress.

# Prerequisites

- Zig master (at least 0.11.0-dev.1602+d976b4e4a)
    - https://ziglang.org/download/
- QEMU
    - https://www.qemu.org/download/

# Building

```
$ zig build -Dtarget=riscv64-freestanding -Dboard=virt
```

# Running

```
$ zig build run -Dtarget=riscv64-freestanding -Dboard=virt
```

# Debugging (with gdb)

```
$ zig build debug -Dtarget=riscv64-freestanding -Dboard=virt
```

Open another terminal and enter:

```
$ gdb -x script.gdb
```

You can make some breakpoints here. To start debugging the OS you need to enter `c` on gdb terminal. For example:

```
(gdb) break main
Breakpoint 1 at 0x8000030a: file main.zig, line 38.
(gdb) c
Continuing.

Breakpoint 1, main () at main.zig:38
38          initCpu();
(gdb) 
```

# TODO

- [x] UART IO
- [x] Interrupt handler
- [x] Separate main.zig into some files
- [x] IO write
- [ ] Bring Wasm binary from somewhere
    - VirtIO Block + File System (overkill?)
    - Embed Wasm binary to source files (easy)
- [ ] Wasm runtime
    - I need to read the spec.
    - Tiny Wasm runtime that only executes some basic operation (add, sub, mul, ret, call, etc.)
    - Preemption without timer interrupt
        - Need to get clock counts from somewhere
        - Maybe just do count executed instructions and switch the running process by these information