# Relaxed Streaming JSON Parser C Library

## Usage

```c
#include <laxjson.h>

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
    struct LaxJsonContext *context = lax_json_create();
    context->userdata = NULL; // can set this to whatever you want
    context->string = on_string;
    context->number = on_number;
    context->primitive = on_primitive;
    context->begin = on_begin;
    context->end = on_end;

    char buf[1024];
    FILE *f = fopen("file.json", "rb");
    int amt_read;
    while (amt_read = fread(buf, 1, sizeof(buf), f)) {
        lax_json_feed(context, amt_read, buf);
    }
    lax_json_destroy(context);
}
```

## Installation

```sh
mkdir build
cd build
cmake ..
make
sudo make install
```

To run the tests, use `make test`.
