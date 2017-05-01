const Builder = @import("std").build.Builder;

pub fn build(b: &Builder) {
    const release = b.option(bool, "release", "optimizations on and safety off") ?? false;
    const static = b.option(bool, "static", "build static library instead of shared") ?? false;

    const lib_cflags = [][]const u8 {
        "-std=c99",
        "-pedantic",
        "-Werror",
        "-Wall",
        "-Werror=strict-prototypes",
        "-Werror=old-style-definition",
        "-Werror=missing-prototypes",
    };

    const example_cflags = [][]const u8 {
        "-std=c99",
        "-pedantic",
        "-Werror",
        "-Wall",
    };

    const lib = if (static) {
        b.addCStaticLibrary("laxjson")
    } else {
        b.addCSharedLibrary("laxjson", b.version(1, 0, 5))
    };
    lib.addCompileFlagsForRelease(release);
    lib.addCompileFlags(lib_cflags);
    lib.addSourceFile("src/laxjson.c");
    lib.linkSystemLibrary("c");
    lib.addIncludeDir("include");
    b.default_step.dependOn(&lib.step);

    // examples

    const token_list_exe = b.addCExecutable("token_list");
    token_list_exe.addCompileFlagsForRelease(release);
    token_list_exe.addCompileFlags(example_cflags);
    token_list_exe.addSourceFile("example/token_list.c");
    token_list_exe.linkCLibrary(lib);
    token_list_exe.addIncludeDir("include");

    b.default_step.dependOn(&token_list_exe.step);

    // test

    const primitives_test_exe = b.addCExecutable("primitives_test");
    primitives_test_exe.addCompileFlagsForRelease(release);
    primitives_test_exe.addCompileFlags(example_cflags);
    primitives_test_exe.addSourceFile("test/primitives.c");
    primitives_test_exe.addIncludeDir("include");
    primitives_test_exe.linkCLibrary(lib);

    const run_test_cmd = b.addCommand(".", b.env_map, primitives_test_exe.getOutputPath(), [][]const u8{});
    run_test_cmd.step.dependOn(&primitives_test_exe.step);
    
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_test_cmd.step);

    // install
    b.installCLibrary(lib);
    b.installFile("include/laxjson.h", "include/laxjson.h");
}
