const std = @import("std");
const fs = std.fs;
const json = std.json;
const zig = std.zig;
const Allocator = std.mem.Allocator;
const mem = std.mem;
const heap = std.heap;
const debug = std.debug;

var test_filter: ?[]const u8 = null;

const Config = struct {
    target: ?[]const u8 = null,
    board: ?[]const u8 = null,
};

fn readAllFileContents(allocator: Allocator, rel_path: []const u8) ![:0]u8 {
    const file: fs.File = try fs.cwd().openFile(rel_path, .{});
    defer file.close();
    const size = try file.getEndPos();
    var buffered = std.io.bufferedReader(file.reader());
    const reader = buffered.reader();

    const buf = try allocator.allocSentinel(u8, size, 0);
    const read_bytes = try reader.readAll(buf);
    std.debug.assert(read_bytes == size);

    return buf;
}

pub fn build(b: *std.Build) !void {
    var config = config_setting: {
        const buf = readAllFileContents(b.allocator, "build.json") catch break :config_setting Config{};
        var token_stream = json.TokenStream.init(buf);
        const result_json = json.parse(Config, &token_stream, .{ .allocator = b.allocator }) catch break :config_setting Config{};

        break :config_setting result_json;
    };

    var target = b.standardTargetOptions(.{ .default_target = try zig.CrossTarget.parse(.{ .arch_os_abi = config.target orelse "native" }) });
    const optimize = b.standardOptimizeOption(.{});

    var board: ?[]const u8 = b.option([]const u8, "board", "Supported board: virt") orelse config.board orelse null;

    if (board == null) {
        @panic("Target board must be specified; -Dboard=[board name]");
    }

    var linker_path = std.ArrayList(u8).init(b.allocator);
    try linker_path.appendSlice("linker/");
    try linker_path.appendSlice(board.?);
    try linker_path.appendSlice(".ld");

    const exe = b.addExecutable(.{ .name = "gizmos", .root_source_file = .{ .path = "src/main.zig" }, .target = target, .optimize = optimize });
    exe.code_model = .medium;

    b.installArtifact(exe);

    exe.setLinkerScriptPath(.{ .path = linker_path.items });
    // exe.setOutputDir("zig-out/bin");

    // TODO(hobo0xcc): Obtain kernel binary image from builder
    const kernel_binary_path = "zig-out/bin/gizmos";
    var run_emulator_command = std.ArrayList([]const u8).init(b.allocator);
    switch (target.cpu_arch.?) {
        .riscv64 => try run_emulator_command.appendSlice(&[_][]const u8{
            "qemu-system-riscv64",
            "-machine",
            "virt",
            "-bios",
            "none",
            "-m",
            "256M",
            "-smp",
            "1",
            "-serial",
            "stdio",
            // Specify kernel binary after this switch
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
    debug_run_cmd.addArgs(&[_][]const u8{
        "-s", // shorthand for -gdb tcp::1234
        "-S", // freeze CPU at startup
    });
    debug_run_cmd.step.dependOn(b.getInstallStep());

    // zig build debug
    const debug_run_step = b.step("debug", "Run gizmos in debug mode");
    debug_run_step.dependOn(&debug_run_cmd.step);

    test_filter = b.option([]const u8, "filter", "Skip tests that do not match filter");

    var test_cmd = b.addTest(.{ .root_source_file = .{ .path = "src/main.zig" }, .optimize = optimize, .target = target, .test_runner = "src/test_runner.zig" });
    test_cmd.*.step.makeFn = testMake;

    // test_cmd.setTestRunner("src/test_runner.zig");
    test_cmd.code_model = .medium;
    test_cmd.setLinkerScriptPath(.{ .path = linker_path.items });

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
    try exec_cmd.append("-display");
    try exec_cmd.append("none");

    test_cmd.setExecCmd(exec_cmd.items);

    const test_step = b.step("test", "Run test with QEMU");
    // test_step.dependOn(&test_cmd.step);
    test_step.dependOn(&test_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        debug_run_cmd.addArgs(args);
    }
}
fn testMake(step: *std.Build.Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const b = step.owner;
    const self = @fieldParentPtr(std.Build.CompileStep, "step", step);

    var argv = std.ArrayList([]const u8).init(b.allocator);
    defer argv.deinit();

    try argv.append(b.zig_exe);
    try argv.append("test");
    try argv.append(self.root_src.?.getPath(b));
    try argv.append("--test-runner");
    try argv.append(b.pathFromRoot(self.test_runner.?));
    try argv.append("--cache-dir");
    try argv.append(b.cache_root.path orelse ".");
    try argv.append("--global-cache-dir");
    try argv.append(b.global_cache_root.path orelse ".");
    try argv.append("--name");
    try argv.append(self.name);
    try argv.append("-mcmodel");
    try argv.append(@tagName(self.code_model));
    try argv.appendSlice(&.{
        "-target", try self.target.zigTriple(b.allocator),
        "-mcpu",   try std.Build.serializeCpu(b.allocator, self.target.getCpu()),
    });
    if (self.linker_script) |linker_script| {
        try argv.append("--script");
        try argv.append(linker_script.getPath(b));
    }
    if (test_filter) |filter| {
        try argv.append("--test-filter");
        try argv.append(filter);
    }
    if (self.exec_cmd_args) |exec_cmd_args| {
        for (exec_cmd_args) |cmd_arg| {
            if (cmd_arg) |arg| {
                try argv.append("--test-cmd");
                try argv.append(arg);
            } else {
                try argv.append("--test-cmd-bin");
            }
        }
    }

    var child = std.ChildProcess.init(argv.items, b.allocator);
    child.env_map = b.env_map;
    const term = try child.spawnAndWait();
    switch (term.Exited) {
        0 => {},
        else => |_| {
            return step.fail("Test failed", .{});
        },
    }
}
