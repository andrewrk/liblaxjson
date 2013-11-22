#include <laxjson.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static enum LaxJsonType expected_primitive;

static void on_string_fail(struct LaxJsonContext *context,
    enum LaxJsonType type, const char *value, int length)
{
    fprintf(stderr, "nexpected string\n");
    exit(1);
}

static void on_number_fail(struct LaxJsonContext *context, double x)
{
    fprintf(stderr, "unexpected number\n");
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

static void on_primitive_expect(struct LaxJsonContext *context, enum LaxJsonType type)
{
    if (type != expected_primitive) {
        fprintf(stderr, "expected %s, got %s\n", type_to_str(expected_primitive),
                type_to_str(type));
        exit(1);
    }
}

static void on_begin_fail(struct LaxJsonContext *context, enum LaxJsonType type)
{
    fprintf(stderr, "unexpected array or object\n");
    exit(1);
}

static void on_end_fail(struct LaxJsonContext *context, enum LaxJsonType type)
{
    fprintf(stderr, "unexpected end of array or object\n");
    exit(1);
}

static void test_false() {
    struct LaxJsonContext *context;
    char *input;
    int size;
    
    context = lax_json_create();
    if (!context)
        exit(1);

    context->userdata = NULL; /* can set this to whatever you want */
    context->string = on_string_fail;
    context->number = on_number_fail;
    expected_primitive = LaxJsonTypeFalse;
    context->primitive = on_primitive_expect;
    context->begin = on_begin_fail;
    context->end = on_end_fail;

    input = "// this is a comment\n"
            " false";
    size = strlen(input);

    lax_json_feed(context, size, input);

    lax_json_destroy(context);
}

static void test_true() {
    struct LaxJsonContext *context;
    char *input;
    int size;
    
    context = lax_json_create();
    if (!context)
        exit(1);

    context->userdata = NULL; /* can set this to whatever you want */
    context->string = on_string_fail;
    context->number = on_number_fail;
    expected_primitive = LaxJsonTypeTrue;
    context->primitive = on_primitive_expect;
    context->begin = on_begin_fail;
    context->end = on_end_fail;

    input = " /* before comment */true";
    size = strlen(input);

    lax_json_feed(context, size, input);

    lax_json_destroy(context);
}

int main() {
    test_false();
    test_true();
    /*test_null();
    test_string();*/

    return 0;
}
