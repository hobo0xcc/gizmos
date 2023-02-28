const std = @import("std");

const SupportedArch = enum {
    riscv64,
};
const default_arch: SupportedArch = .riscv64;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
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

    // TODO(hobo0xcc): Obtain kernel binary image from builder
    const kernel_binary_path = "zig-out/bin/gizmos";
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
            // Specify kernel binary after switch
            "-kernel",
        }),
        else => std.debug.print("Unknown arch: {}\n", .{target.cpu_arch.?}),
    }
    // Append kernel binary
    try run_emulator_command.append(kernel_binary_path);

    if (run_emulator_command.items.len == 0) {
        @panic("Error");
    }

    // Run QEMU
    const run_cmd = b.addSystemCommand(run_emulator_command.items);
    run_cmd.step.dependOn(b.getInstallStep());

    // zig build run
    const run_step = b.step("run", "Run gizmos");
    run_step.dependOn(&run_cmd.step);

    // Run QEMU in debug mode.
    var debug_run_cmd = b.addSystemCommand(run_emulator_command.items);
    debug_run_cmd.addArgs(&[_][]const u8 {
        "-s", // shorthand for -gdb tcp::1234
        "-S", // freeze CPU at startup
    });
    debug_run_cmd.step.dependOn(b.getInstallStep());

    // zig build debug
    const debug_run_step = b.step("debug", "Run gizmos in debug mode");
    debug_run_step.dependOn(&debug_run_cmd.step);

    var test_cmd = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });
    test_cmd.setTestRunner("src/test_runner.zig");
    test_cmd.code_model = .medium;
    test_cmd.setLinkerScriptPath(.{ .path=linker_path.items });

    var exec_cmd = std.ArrayList(?[]const u8).init(b.allocator);
    var do_skip_counter: usize = 0;
    for (run_emulator_command.items) |cmd| {
        if (do_skip_counter > 0) {
            do_skip_counter -= 1;
            continue;
        }

        if (std.mem.eql(u8, cmd, kernel_binary_path)) {
            // See https://github.com/ziglang/zig/blob/f6c934677315665c140151b8dd28a56f948205e2/lib/std/Build/CompileStep.zig#L1591-L1598
            // and https://github.com/ziglang/zig/blob/705d2a3c2cd94faf8e16c660b3b342d6fe900e55/src/main.zig#L3552-L3554
            try exec_cmd.append(null);
        } else if (std.mem.eql(u8, cmd, "-serial")) {
            try exec_cmd.append("-serial");
            try exec_cmd.append("file:/dev/stderr");
            do_skip_counter = 1;
        } else {
            try exec_cmd.append(cmd);
        }
    }

    test_cmd.setExecCmd(exec_cmd.items);

    const test_step = b.step("test", "Run test with QEMU");
    test_step.dependOn(&test_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        debug_run_cmd.addArgs(args);
    }
}
