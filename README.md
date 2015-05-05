# Relaxed Streaming JSON Parser C Library

## Differences from RFC 4627

 * unquoted keys
 * single quotes `'`
 * `//` and `/* */` style comments
 * extra commas `,` in arrays and objects

## Why?

[Official JSON](http://json.org/) is *almost* human-readable and
human-writable. If we disable a few of the strict rules, we can make it
significantly more so.

You would use this library when parsing user input, such as a config file.
You would *not* use this library when serializing or deserializing, or
as a format for computer-to-computer communication.

I could not find another JSON parser that fit all of these requirements:

 * C library
 * Relaxed parsing rules as outlined above. As a rule of thumb the parser
   should be compatible with [GYP](https://code.google.com/p/gyp/).
 * Streaming - ability to not buffer the entire JSON string in memory
   before parsing it.
 * In Debian/Ubuntu's package repository or at least scheduled to be in it.

So I wrote one that satisfies all these requirements. It has a
[test suite](test) and is already in use by
[another project](https://github.com/andrewrk/rucksack). It has been uploaded
to Debian and is scheduled to be released in "jessie" and Ubuntu 14.10
Utopic Unicorn.

## Usage

See include/laxjson.h for more details.

```c
#include <laxjson.h>
#include <stdio.h>

static int on_string(struct LaxJsonContext *context,
    enum LaxJsonType type, const char *value, int length)
{
    const char *type_name = type == LaxJsonTypeProperty ? "property" : "string";
    printf("%s: %s\n", type_name, value);
    return 0;
}

static int on_number(struct LaxJsonContext *context, double x) {
    printf("number: %f\n", x);
    return 0;
}

static int on_primitive(struct LaxJsonContext *context, enum LaxJsonType type) {
    const char *type_name;
    if (type == LaxJsonTypeTrue)
        type_name = "true";
    else if (type == LaxJsonTypeFalse)
        type_name = "false";
    else
        type_name = "null";

    printf("primitive: %s\n", type_name);
    return 0;
}

static int on_begin(struct LaxJsonContext *context, enum LaxJsonType type) {
    const char *type_name = (type == LaxJsonTypeArray) ? "array" : "object";
    printf("begin %s\n", type_name);
    return 0;
}

static int on_end(struct LaxJsonContext *context, enum LaxJsonType type) {
    const char *type_name = (type == LaxJsonTypeArray) ? "array" : "object";
    printf("end %s\n", type_name);
    return 0;
}

int main() {
    char buf[1024];
    struct LaxJsonContext *context;
    FILE *f;
    int amt_read;
    enum LaxJsonError err;

    context = lax_json_create();

    context->userdata = NULL; /* can set this to whatever you want */
    context->string = on_string;
    context->number = on_number;
    context->primitive = on_primitive;
    context->begin = on_begin;
    context->end = on_end;

    f = fopen("file.json", "rb");
    while ((amt_read = fread(buf, 1, sizeof(buf), f))) {
        if ((err = lax_json_feed(context, amt_read, buf))) {
            fprintf(stderr, "Line %d, column %d: %s\n",
                    context->line, context->column, lax_json_str_err(err));
            return -1;
        }
        lax_json_feed(context, amt_read, buf);
    }
    if ((err = lax_json_eof(context))) {
        fprintf(stderr, "Line %d, column %d: %s\n",
                context->line, context->column, lax_json_str_err(err));
        return -1;
    }
    lax_json_destroy(context);

    return 0;
}
```

## Installation

### Pre-Built Packages

 * [Ubuntu PPA](https://launchpad.net/~andrewrk/+archive/rucksack)

   ```
   sudo apt-add-repository ppa:andrewrk/rucksack
   sudo apt-get update
   sudo apt-get install liblaxjson-dev
   ```

### From Source

```sh
mkdir build
cd build
cmake ..
make
sudo make install
```

To run the tests, use `make test`.

## Projects Using liblaxjson

Feel free to make a pull request adding to this list.

 * [rucksack](https://github.com/andrewrk/rucksack) - a texture packer and
   resource bundler
 * [Genesis](https://github.com/andrewrk/genesis) - digital audio workstation
