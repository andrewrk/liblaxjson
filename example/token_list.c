#include <laxjson.h>
#include <stdio.h>

static void on_string(struct LaxJsonContext *context,
    enum LaxJsonType type, const char *value, int length)
{
    char *type_name = type == LaxJsonTypeProperty ? "property" : "string";
    printf("%s: %s\n", type_name, value);
}

static void on_number(struct LaxJsonContext *context, double x)
{
    printf("number: %f\n", x);
}

static void on_primitive(struct LaxJsonContext *context, enum LaxJsonType type)
{
    char *type_name;
    if (type == LaxJsonTypeTrue)
        type_name = "true";
    else if (type == LaxJsonTypeFalse)
        type_name = "false";
    else
        type_name = "null";

    printf("primitive: %s\n", type_name);
}

static void on_begin(struct LaxJsonContext *context, enum LaxJsonType type)
{
    char *type_name = LaxJsonTypeArray ? "array" : "object";
    printf("begin %s\n", type_name);
}

static void on_end(struct LaxJsonContext *context, enum LaxJsonType type)
{
    char *type_name = LaxJsonTypeArray ? "array" : "object";
    printf("end %s\n", type_name);
}

int main() {
    char buf[1024];
    struct LaxJsonContext *context;
    FILE *f;
    int amt_read;
    
    context = lax_json_create();

    context->userdata = NULL; /* can set this to whatever you want */
    context->string = on_string;
    context->number = on_number;
    context->primitive = on_primitive;
    context->begin = on_begin;
    context->end = on_end;

    f = fopen("file.json", "rb");
    while ((amt_read = fread(buf, 1, sizeof(buf), f))) {
        lax_json_feed(context, amt_read, buf);
    }
    lax_json_destroy(context);

    return 0;
}
