(To be) A WebAssembly-based operating system

This project is work in progress.

# Prerequisites

- Zig master (at least 0.11.0-dev.2725+4374ce51b)
    - https://ziglang.org/download/
- QEMU
    - https://www.qemu.org/download/

# Specifying default settings

You can specify default settings in `build.json`. Default settings will then be used by `zig build` to configure build process.

```
{
    "target": "riscv64-freestanding",
    "board": "virt"
}
```

```
# you can omit otherwise required command-line options by using default settings.
$ zig build run
```

You can omit these default settings and instead use command-line options to indicate these settings.

Note: If command-line options are used, they will overwrite the default settings in `build.json`.

```
zig build -Dtarget=riscv64-freestanding -Dboard=virt
```

# Build

```
$ zig build -Dtarget=riscv64-freestanding -Dboard=virt
```

# Run

```
$ zig build run -Dtarget=riscv64-freestanding -Dboard=virt
```

# Debug (with gdb)

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

# Test

```
$ zig build test -Dtarget=riscv64-freestanding -Dboard=virt
```