const std = @import("std");

const SupportedArch = enum {
    riscv64,
};
const default_arch: SupportedArch = .riscv64;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // var target_arch = default_arch;
    // //  If arch is specified, use it.
    // if (b.option(SupportedArch, "arch", "Target architecture: riscv64")) |arch| {
    //     target_arch = arch;
    // }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    var target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const board: ?[]const u8 = b.option([]const u8, "board", "Supported board: virt");
    if (board == null) {
        @panic("Target board must be specified; -Dboard=[board name]");
    }

    var linker_path = std.ArrayList(u8).init(b.allocator);
    try linker_path.appendSlice("linker/");
    try linker_path.appendSlice(board.?);
    try linker_path.appendSlice(".ld");

    const exe = b.addExecutable(.{
        .name = "gizmos",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize
    });
    exe.code_model = .medium;

    exe.setLinkerScriptPath(.{.path = linker_path.items});
    exe.setOutputDir("zig-out/bin");

    exe.install();

    var run_emulator_command = std.ArrayList([]const u8).init(b.allocator);
    switch (target.cpu_arch.?) {
        .riscv64 =>
            try run_emulator_command.appendSlice(&[_][]const u8 {
            "qemu-system-riscv64",
            "-machine", "virt",
            "-bios", "none",
            "-m", "256M",
            "-smp", "1",
            "-serial", "stdio",
            "-kernel", "zig-out/bin/gizmos",
        }),
        else => std.debug.print("Unknown arch: {}\n", .{target.cpu_arch.?}),
    }

    if (run_emulator_command.items.len == 0) {
        @panic("Error");
    }

    // Run QEMU
    const run_cmd = b.addSystemCommand(run_emulator_command.items);
    run_cmd.step.dependOn(b.getInstallStep());

    // zig build run
    const run_step = b.step("run", "Run the OS");
    run_step.dependOn(&run_cmd.step);

    // Run QEMU in debug mode.
    var debug_run_cmd = b.addSystemCommand(run_emulator_command.items);
    debug_run_cmd.addArgs(&[_][]const u8 {
        "-s", // shorthand for -gdb tcp::1234
        "-S", // freeze CPU at startup
    });
    debug_run_cmd.step.dependOn(b.getInstallStep());

    // zig build debug
    const debug_run_step = b.step("debug", "Run the OS in debug mode");
    debug_run_step.dependOn(&debug_run_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        debug_run_cmd.addArgs(args);
    }

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
