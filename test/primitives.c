#include <laxjson.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static char out_buf[16384];
static int out_buf_index;

static void add_buf(const char *str, int len) {
    if (len == 0)
        len = strlen(str);
    memcpy(&out_buf[out_buf_index], str, len);
    out_buf_index += len;
}

static const char *err_to_str(enum LaxJsonError err) {
    switch(err) {
        case LaxJsonErrorNone:
            return "";
        case LaxJsonErrorUnexpectedChar:
            return "unexpected char";
        case LaxJsonErrorExpectedEof:
            return "expected EOF";
        case LaxJsonErrorExceededMaxStack:
            return "exceeded max stack";
        case LaxJsonErrorNoMem:
            return "no mem";
        case LaxJsonErrorExceededMaxValueSize:
            return "exceeded max value size";
        case LaxJsonErrorInvalidHexDigit:
            return "invalid hex digit";
        case LaxJsonErrorInvalidUnicodePoint:
            return "invalid unicode point";
        case LaxJsonErrorExpectedColon:
            return "expected colon";
    }
    exit(1);
}

static const char *type_to_str(enum LaxJsonType type) {
    switch (type) {
        case LaxJsonTypeString:
            return "string";
        case LaxJsonTypeProperty:
            return "property";
        case LaxJsonTypeNumber:
            return "number";
        case LaxJsonTypeObject:
            return "object";
        case LaxJsonTypeArray:
            return "array";
        case LaxJsonTypeTrue:
            return "true";
        case LaxJsonTypeFalse:
            return "false";
        case LaxJsonTypeNull:
            return "null";
    }
    exit(1);
}

static void feed(struct LaxJsonContext *context, const char *data) {
    int size = strlen(data);

    enum LaxJsonError err = lax_json_feed(context, size, data);

    if (!err)
        return;

    fprintf(stderr, "line %d column %d parse error: %s\n", context->line,
            context->column, err_to_str(err));
    exit(1);
}

static void on_string_build(struct LaxJsonContext *context,
    enum LaxJsonType type, const char *value, int length)
{
    add_buf(type_to_str(type), 0);
    add_buf("\n", 0);
    add_buf(value, length);
    add_buf("\n", 0);
}

static void on_number_build(struct LaxJsonContext *context, double x)
{
    out_buf_index += snprintf(&out_buf[out_buf_index], 30, "number %g\n", x);
}

static void on_primitive_build(struct LaxJsonContext *context, enum LaxJsonType type)
{
    out_buf_index += snprintf(&out_buf[out_buf_index], 50, "%s\n", type_to_str(type));
}

static void on_begin_build(struct LaxJsonContext *context, enum LaxJsonType type)
{
    out_buf_index += snprintf(&out_buf[out_buf_index], 50, "begin %s\n", type_to_str(type));
}

static void on_end_build(struct LaxJsonContext *context, enum LaxJsonType type)
{
    out_buf_index += snprintf(&out_buf[out_buf_index], 50, "end %s\n", type_to_str(type));
}

static void check_build(struct LaxJsonContext *context, const char *output) {
    int expected_len = strlen(output);
    if (out_buf_index != expected_len) {
        fprintf(stderr, "\n"
                "EXPECTED:\n"
                "---------\n"
                "%s\n"
                "RECEIVED:\n"
                "---------\n"
                "%s\n", output, out_buf);
        exit(1);
    }
    if (memcmp(output, out_buf, expected_len) != 0) {
        fprintf(stderr,
                "EXPECTED:\n"
                "---------\n"
                "%s\n"
                "RECEIVED:\n"
                "---------\n"
                "%s\n", output, out_buf);
        exit(1);
    }
    lax_json_destroy(context);
}

static struct LaxJsonContext *init_for_build(void) {
    struct LaxJsonContext *context = lax_json_create();
    if (!context)
        exit(1);

    out_buf_index = 0;

    context->userdata = NULL;
    context->string = on_string_build;
    context->number = on_number_build;
    context->primitive = on_primitive_build;
    context->begin = on_begin_build;
    context->end = on_end_build;

    return context;
}

static void test_false() {
    struct LaxJsonContext *context = init_for_build();

    feed(context,
        "// this is a comment\n"
        " false"
        );

    check_build(context,
            "false\n"
            );
}

static void test_true() {
    struct LaxJsonContext *context = init_for_build();

    feed(context,
        " /* before comment */true"
        );

    check_build(context,
            "true\n"
            );
}

static void test_null() {
    struct LaxJsonContext *context = init_for_build();

    feed(context,
        "null/* after comment*/ // line comment"
        );

    check_build(context,
            "null\n"
            );
}

static void test_string() {
    struct LaxJsonContext *context = init_for_build();

    feed(context,
        "\"foo\""
        );

    check_build(context,
            "string\n"
            "foo\n"
            );
}

static void test_basic_json() {
    struct LaxJsonContext *context;

    context = init_for_build();

    feed(context,
        "// comments are OK :)\n"
        "// single quotes, double quotes, and no quotes are OK\n"
        "{\n"
        "  textures: {\n"
        "    cockpit: {\n"
        "      images: {\n"
        "        arrow: {\n"
        "          path: \"img/arrow.png\",\n"
        "          anchor: \"left\"\n"
        "        },"
        "        'radar-circle': {\n"
        "          path: \"img/radar-circle.png\",\n"
        "          anchor: \"center\"\n"
        "        }\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "}\n"
        );

    check_build(context,
            "begin object\n"
            "property\n"
            "textures\n"
            "begin object\n"
            "property\n"
            "cockpit\n"
            "begin object\n"
            "property\n"
            "images\n"
            "begin object\n"
            "property\n"
            "arrow\n"
            "begin object\n"
            "property\n"
            "path\n"
            "string\n"
            "img/arrow.png\n"
            "property\n"
            "anchor\n"
            "string\n"
            "left\n"
            "end object\n"
            "property\n"
            "radar-circle\n"
            "begin object\n"
            "property\n"
            "path\n"
            "string\n"
            "img/radar-circle.png\n"
            "property\n"
            "anchor\n"
            "string\n"
            "center\n"
            "end object\n"
            "end object\n"
            "end object\n"
            "end object\n"
            "end object\n"
            );
}

static void test_empty_object() {
    struct LaxJsonContext *context;

    context = init_for_build();

    feed(context, "{}");

    check_build(context,
            "begin object\n"
            "end object\n"
            );
}

static void test_float_value() {
    struct LaxJsonContext *context;

    context = init_for_build();

    feed(context,
            "{\n"
            "\"PI\": 3.141E-10"
            "}"
            );

    check_build(context,
            "begin object\n"
            "property\n"
            "PI\n"
            "number 3.141e-10\n"
            "end object\n"
            );
}

static void test_simple_digit_array() {
    struct LaxJsonContext *context = init_for_build();

    feed(context,
            "[ 1,2,3,4]"
            );

    check_build(context,
            "begin array\n"
            "number 1\n"
            "number 2\n"
            "number 3\n"
            "number 4\n"
            "end array\n"
            );
}

struct Test {
    const char *name;
    void (*fn)(void);
};

static struct Test tests[] = {
    {"false primitive", test_false},
    {"true primitive", test_true},
    {"null primitive", test_null},
    {"string primitive", test_string},
    {"basic json", test_basic_json},
    {"empty object", test_empty_object},
    {"float value", test_float_value},
    {"simple digit array", test_simple_digit_array},
    {NULL, NULL},
};

int main(int argc, char *argv[]) {
    struct Test *test = &tests[0];

    while (test->name) {
        fprintf(stderr, "testing %s...", test->name);
        test->fn();
        fprintf(stderr, "OK\n");
        test += 1;
    }

    return 0;
}
