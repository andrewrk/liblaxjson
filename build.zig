const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const static = b.option(bool, "static", "build static library instead of shared") orelse false;

    const lib_cflags = [][]const u8{
        "-std=c99",
        "-pedantic",
        "-Werror",
        "-Wall",
        "-Werror=strict-prototypes",
        "-Werror=old-style-definition",
        "-Werror=missing-prototypes",
    };

    const example_cflags = [][]const u8{
        "-std=c99",
        "-pedantic",
        "-Werror",
        "-Wall",
    };

    const lib = if (static)
        b.addStaticLibrary("laxjson", null)
    else
        b.addSharedLibrary("laxjson", null, b.version(1, 0, 5));
    lib.setBuildMode(mode);
    lib.addCSourceFile("src/laxjson.c", lib_cflags);
    lib.linkSystemLibrary("c");
    lib.addIncludeDir("include");
    b.default_step.dependOn(&lib.step);

    // examples

    const token_list_exe = b.addExecutable("token_list", null);
    token_list_exe.setBuildMode(mode);
    token_list_exe.addCSourceFile("example/token_list.c", example_cflags);
    token_list_exe.linkLibrary(lib);
    token_list_exe.addIncludeDir("include");

    b.default_step.dependOn(&token_list_exe.step);

    // test

    const primitives_test_exe = b.addExecutable("primitives_test", null);
    primitives_test_exe.setBuildMode(mode);
    primitives_test_exe.addCSourceFile("test/primitives.c", example_cflags);
    primitives_test_exe.addIncludeDir("include");
    primitives_test_exe.linkLibrary(lib);

    const run_test_cmd = primitives_test_exe.run();

    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_test_cmd.step);

    // install
    b.installArtifact(lib);
    b.installFile("include/laxjson.h", "include/laxjson.h");
}
