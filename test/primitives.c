#include <laxjson.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

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

static void on_primitive_is_false(struct LaxJsonContext *context, enum LaxJsonType type)
{
    char *type_name;
    if (type == LaxJsonTypeTrue)
        type_name = "true";
    else if (type == LaxJsonTypeFalse)
        type_name = "false";
    else
        type_name = "null";
    if (type != LaxJsonTypeFalse) {
        fprintf(stderr, "expected false, got %s\n", type_name);
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
    context->primitive = on_primitive_is_false;
    context->begin = on_begin_fail;
    context->end = on_end_fail;

    input = "false";
    size = strlen(input);

    lax_json_feed(context, size, input);

    lax_json_destroy(context);
}

int main() {
    test_false();
    /*test_true();
    test_null();
    test_string();*/

    return 0;
}
