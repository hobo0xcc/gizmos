An WebAssembly-based operating system written in zig

This project is work in progress.

# Prerequisites

- Zig master (at least 0.11.0-dev.1602+d976b4e4a)
- QEMU

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

You can make some breakpoints here and to start debugging the OS you need to enter `c` on gdb terminal. For example:

```
(gdb) break _entry
Breakpoint 1 at 0x80000000: file main.zig, line 6.
(gdb) c
Continuing.

Breakpoint 1, _entry () at main.zig:6
6           asm volatile (
```