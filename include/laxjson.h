/*
 * Copyright (c) 2013 Andrew Kelley
 *
 * This file is part of liblaxjson, which is MIT licensed.
 * See http://opensource.org/licenses/MIT
 */

#ifndef LAXJSON_H_INCLUDED
#define LAXJSON_H_INCLUDED

enum LaxJsonType {
    LaxJsonTypeString,
    LaxJsonTypeProperty,
    LaxJsonTypeNumber,
    LaxJsonTypeObject,
    LaxJsonTypeArray,
    LaxJsonTypeTrue,
    LaxJsonTypeFalse,
    LaxJsonTypeNull
};

enum LaxJsonState {
    LaxJsonStateValue,
    LaxJsonStateObject,
    LaxJsonStateArray,
    LaxJsonStateString,
    LaxJsonStateStringEscape,
    LaxJsonStateUnicodeEscape,
    LaxJsonStateBareProp,
    LaxJsonStateCommentBegin,
    LaxJsonStateCommentLine,
    LaxJsonStateCommentMultiLine,
    LaxJsonStateCommentMultiLineStar,
    LaxJsonStateExpect,
    LaxJsonStateEnd,
    LaxJsonStateColon,
    LaxJsonStateNumber,
    LaxJsonStateNumberDecimal,
    LaxJsonStateNumberExponent,
    LaxJsonStateNumberExponentSign
};

enum LaxJsonError {
    LaxJsonErrorNone,
    LaxJsonErrorUnexpectedChar,
    LaxJsonErrorExpectedEof,
    LaxJsonErrorExceededMaxStack,
    LaxJsonErrorNoMem,
    LaxJsonErrorExceededMaxValueSize,
    LaxJsonErrorInvalidHexDigit,
    LaxJsonErrorInvalidUnicodePoint,
    LaxJsonErrorExpectedColon
};

struct LaxJsonContext {
    void *userdata;
    /* type can be property or string */
    void (*string)(struct LaxJsonContext *, enum LaxJsonType type, const char *value, int length);
    /* type is always number */
    void (*number)(struct LaxJsonContext *, double x);
    /* type can be true, false, or null */
    void (*primitive)(struct LaxJsonContext *, enum LaxJsonType type);
    /* type can be array or object */
    void (*begin)(struct LaxJsonContext *, enum LaxJsonType type);
    /* type can be array or object */
    void (*end)(struct LaxJsonContext *, enum LaxJsonType type);

    int line;
    int column;

    int max_state_stack_size;
    int max_value_buffer_size;

    /* private members */
    enum LaxJsonState state;
    enum LaxJsonState *state_stack;
    int state_stack_index;
    int state_stack_size;

    char *value_buffer;
    int value_buffer_index;
    int value_buffer_size;

    int unicode_point;
    int unicode_digit_index;

    char *expected;
    char delim;
    enum LaxJsonType string_type;
};

struct LaxJsonContext *lax_json_create(void);
void lax_json_destroy(struct LaxJsonContext *context);

enum LaxJsonError lax_json_feed(struct LaxJsonContext *context, int size, const char *data);

#endif /* LAXJSON_H_INCLUDED */