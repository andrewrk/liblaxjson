/*
 * Copyright (c) 2013 Andrew Kelley
 *
 * This file is part of liblaxjson, which is MIT licensed.
 * See http://opensource.org/licenses/MIT
 */

#version("1.0.5")
export library "laxjson";

#link("c")
#c_include("stdlib.h");

#c_header_name("void")
const c_void = u8;

#c_header_name("char")
const c_char = u8;

export enum LaxJsonType {
    String,
    Property,
    Number,
    Object,
    Array,
    True,
    False,
    Null,
}

export enum LaxJsonState {
    Value,
    Object,
    Array,
    String,
    StringEscape,
    UnicodeEscape,
    BareProp,
    CommentBegin,
    CommentLine,
    CommentMultiLine,
    CommentMultiLineStar,
    Expect,
    End,
    Colon,
    Number,
    NumberDecimal,
    NumberExponent,
    NumberExponentSign,
}

export enum LaxJsonError {
    None,
    UnexpectedChar,
    ExpectedEof,
    ExceededMaxStack,
    NoMem,
    ExceededMaxValueSize,
    InvalidHexDigit,
    InvalidUnicodePoint,
    ExpectedColon,
    UnexpectedEof,
    Aborted,
}

/// All callbacks must be provided. Return nonzero to abort the ongoing feed operation.
export struct LaxJsonContext {
    userdata: &c_void,

    /// type can be property or string
    string: fn(&LaxJsonContext, ty: LaxJsonType, value: &c_char, length: c_int),
    /// type is always number
    number: fn(&LaxJsonContext, x: f64),
    /// type can be true, false, or null
    primitive: fn(&LaxJsonContext, ty: LaxJsonType),
    /// type can be array or object
    begin: fn(&LaxJsonContext, ty: LaxJsonType),
    /// type can be array or object
    end: fn(&LaxJsonContext, ty: LaxJsonType),

    line: c_int,
    column: c_int,

    max_state_stack_size: c_int,
    max_value_buffer_size: c_int,

    /// private members

    state: LaxJsonState,
    state_stack: &LaxJsonState,
    state_stack_index: c_int,
    state_stack_size: c_int,

    value_buffer: &c_char,
    value_buffer_index: c_int,
    value_buffer_size: c_int,

    unicode_point: c_uint,
    unicode_digit_index: c_uint,

    expected: &c_char,
    delim: c_char;
    string_type: LaxJsonType,

}

export fn lax_json_create() ?&LaxJsonContext => {
    const context : &LaxJsonContext = ??return calloc(1, @sizeof(LaxJsonContext));
    ?defer lax_json_destroy(context);

    context.value_buffer_size = 1024;
    context.value_buffer = ??return malloc(context.value_buffer_size);

    context.state_stack_size = 1024;
    context.state_stack = ??return malloc(context.state_stack_size * @sizeof(LaxJsonState));

    context.line = 1;
    context.max_state_stack_size = 16384;
    context.max_value_buffer_size = 1048576; /* 1 MB */

    push_state(context, LaxJsonState.End);

    return context;
}

export fn lax_json_destroy(context: &LaxJsonContext) => {
    free(context.state_stack);
    free(context.value_buffer);
    free(context);
}

export fn lax_json_feed(context: &LaxJsonContext, size: c_int, data: &const c_char) LaxJsonError => {
    return feed(data[0...size]);
}

export fn lax_json_eof(context: &LaxJsonContext) LaxJsonError => {
    while (true) {
        switch (context.state) {
            LaxJsonState.End => return LaxJsonError.None,
            LaxJsonState.CommentLine => {
                pop_state(context);
                continue;
            },
            else => return LaxJsonError.UnexpectedEof,
        }
    }
}

export fn lax_json_str_err(err: LaxJsonError) &const c_char => {
    switch (err) {
        LaxJsonError.None => return "none",
        LaxJsonError.UnexpectedChar => return "unexpected character",
        LaxJsonError.ExpectedEof => return "expected end of file",
        LaxJsonError.ExceededMaxStack => return "exceeded max stack",
        LaxJsonError.NoMem => return "out of memory",
        LaxJsonError.ExceededMaxValueSize => return "exceeded maximum value size",
        LaxJsonError.InvalidHexDigit => return "invalid hex digit",
        LaxJsonError.InvalidUnicodePoint => return "invalid unicode point",
        LaxJsonError.ExpectedColon => return "expected colon",
        LaxJsonError.UnexpectedEof => return "unexpected end of file",
        LaxJsonError.Aborted => return "aborted",
    }
    return "(invalid error code)";
}

const HEX_MULT = []i32{4096, 256, 16, 1};

fn feed(context: &LaxJsonContext, data: []const u8) LaxJsonError => {
    var err : LaxJsonError = LaxJsonError.None;
    var byte : u8;
    for (c, data, *index) {
        if (c == '\n') {
            context.line += 1;
            context.column = 0;
        } else {
            context.column += 1;
        }
        switch (context.state) {
            LaxJsonState.End => {
                if (is_whitespace(c)) {
                    // ignore
                } else if (c == '/') {
                    context.state = LaxJsonState.CommentBegin;
                    %%return push_state(context, LaxJsonStateEnd);
                } else {
                    return LaxJsonErrorExpectedEof;
                }
            },
            LaxJsonState.Object => {
                if (is_whitespace(c) || c == ',') {
                    // do nothing except eat these characters
                } else if (c == '/') {
                    context.state = LaxJsonState.CommentBegin;
                    %%return push_state(context, LaxJsonState.Object);
                } else if (c == '"' || c == '\'') {
                    context.state = LaxJsonState.String;
                    context.value_buffer_index = 0;
                    context.delim = c;
                    context.string_type = LaxJsonType.Property;
                    %%return push_state(context, LaxJsonState.Colon);
                } else if (is_valid_unquoted(c)) {
                    context.state = LaxJsonState.BareProp;
                    context.value_buffer[0] = c;
                    context.value_buffer_index = 1;
                    context.delim = 0;
                } else if (c == '}') {
                    if context.end(context, LaxJsonType.Object)
                        return LaxJsonError.Aborted;
                    pop_state(context);
                } else {
                    return LaxJsonError.UnexpectedChar;
                }
            },
            LaxJsonState.BareProp => {
                if (is_valid_unquoted(c)) {
                    %%return buffer_char(context, c);
                    break;
                } else if (is_whitespace(c)) {
                    %%return buffer_char(context, '\0');
                    if (context.string(context, LaxJsonTypeProperty, context.value_buffer,
                        context.value_buffer_index - 1))
                    {
                        return LaxJsonErrorAborted;
                    }
                    context.state = LaxJsonStateColon;
                    break;
                } else if (c == ':') {
                    %%return buffer_char(context, '\0');
                    if (context.string(context, LaxJsonTypeProperty, context.value_buffer,
                                context.value_buffer_index - 1))
                    {
                        return LaxJsonErrorAborted;
                    }
                    context.state = LaxJsonStateValue;
                    context.string_type = LaxJsonTypeString;
                    %%return push_state(context, LaxJsonStateObject);
                    break;
                } else {
                    return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.String => {
                if (c == context.delim) {
                    %%return buffer_char(context, '\0');
                    if (context.string(context, context.string_type, context.value_buffer,
                            context.value_buffer_index - 1))
                    {
                        return LaxJsonErrorAborted;
                    }
                    pop_state(context);
                } else if (c == '\\') {
                    context.state = LaxJsonStateStringEscape;
                } else {
                    %%return buffer_char(context, c);
                }
            }
            LaxJsonState.StringEscape => {
                if (c == '\'' || c == '"' || c == '/' || c == '\\') {
                    %%return buffer_char(context, c);
                    context.state = LaxJsonStateString;
                } else if (c == 'b') {
                    %%return buffer_char(context, '\b');
                    context.state = LaxJsonStateString;
                } else if (c == 'f') {
                    %%return buffer_char(context, '\f');
                    context.state = LaxJsonStateString;
                } else if (c == 'n') {
                    %%return buffer_char(context, '\n');
                    context.state = LaxJsonStateString;
                } else if (c == 'r') {
                    %%return buffer_char(context, '\r');
                    context.state = LaxJsonStateString;
                } else if (c == 't') {
                    %%return buffer_char(context, '\t');
                    context.state = LaxJsonStateString;
                } else if (c == 'u') {
                    context.state = LaxJsonStateUnicodeEscape;
                    context.unicode_digit_index = 0;
                    context.unicode_point = 0;
                }
            },
            LaxJsonState.UnicodeEscape => {
                const x: i32 = switch (c) {
                    '0' => 0,
                    '1' => 1,
                    '2' => 2,
                    '3' => 3,
                    '4' => 4,
                    '5' => 5,
                    '6' => 6,
                    '7' => 7,
                    '8' => 8,
                    '9' => 9,
                    'a', 'A' => 10,
                    'b', 'B' => 11,
                    'c', 'C' => 12,
                    'd', 'D' => 13,
                    'e', 'E' => 14,
                    'f', 'F' => 15,
                    else => return LaxJsonError.InvalidHexDigit,
                };
                context.unicode_point += x * HEX_MULT[context.unicode_digit_index];
                context.unicode_digit_index += 1;
                if (context.unicode_digit_index == 4) {
                    if (context.unicode_point <= 0x007f) {
                        /* 1 byte */
                        %%return buffer_char(context, (char)context.unicode_point);
                        context.state = LaxJsonStateString;
                    } else if (context.unicode_point <= 0x07ff) {
                        /* 2 bytes */
                        byte = (0xc0 | (context.unicode_point >> 6));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                    } else if (context.unicode_point <= 0xffff) {
                        /* 3 bytes */
                        byte = (0xe0 | (context.unicode_point >> 12));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 6) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                    } else if (context.unicode_point <= 0x1fffff) {
                        /* 4 bytes */
                        byte = (0xf0 | (context.unicode_point >> 18));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 12) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 6) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                    } else if (context.unicode_point <= 0x3ffffff) {
                        /* 5 bytes */
                        byte = (0xf8 | (context.unicode_point >> 24));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point >> 18));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 12) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 6) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                    } else if (context.unicode_point <= 0x7fffffff) {
                        /* 6 bytes */
                        byte = (0xfc | (context.unicode_point >> 30));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 24) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 18) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 12) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context.unicode_point >> 6) & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context.unicode_point & 0x3f));
                        %%return buffer_char(context, *(char *)(&byte));
                    } else {
                        return LaxJsonErrorInvalidUnicodePoint;
                    }
                    context.state = LaxJsonStateString;
                }
            },
            LaxJsonState.Colon => switch (c) {
                switch (c) {
                    case WHITESPACE:
                        /* ignore it */
                        break;
                    case '/':
                        context.state = LaxJsonStateCommentBegin;
                        %%return push_state(context, LaxJsonStateColon);
                        break;
                    case ':':
                        context.state = LaxJsonStateValue;
                        context.string_type = LaxJsonTypeString;
                        %%return push_state(context, LaxJsonStateObject);
                        break;
                    default:
                        return LaxJsonErrorExpectedColon;
                }
            },
            LaxJsonState.Value => switch (c) {
                switch (c) {
                    case WHITESPACE:
                        /* ignore */
                        break;
                    case '/':
                        context.state = LaxJsonStateCommentBegin;
                        %%return push_state(context, LaxJsonStateValue);
                        break;
                    case '{':
                        if (context.begin(context, LaxJsonTypeObject))
                            return LaxJsonErrorAborted;
                        context.state = LaxJsonStateObject;
                        break;
                    case '[':
                        if (context.begin(context, LaxJsonTypeArray))
                            return LaxJsonErrorAborted;
                        context.state = LaxJsonStateArray;
                        break;
                    case '\'':
                    case '"':
                        context.state = LaxJsonStateString;
                        context.delim = c;
                        context.value_buffer_index = 0;
                        break;
                    case '-':
                        context.state = LaxJsonStateNumber;
                        context.value_buffer[0] = c;
                        context.value_buffer_index = 1;
                        break;
                    case '+':
                        context.state = LaxJsonStateNumber;
                        context.value_buffer_index = 0;
                        break;
                    case DIGIT:
                        context.state = LaxJsonStateNumber;
                        context.value_buffer_index = 1;
                        context.value_buffer[0] = c;
                        break;
                    case 't':
                        if (context.primitive(context, LaxJsonTypeTrue))
                            return LaxJsonErrorAborted;
                        context.state = LaxJsonStateExpect;
                        context.expected = "rue";
                        break;
                    case 'f':
                        if (context.primitive(context, LaxJsonTypeFalse))
                            return LaxJsonErrorAborted;
                        context.state = LaxJsonStateExpect;
                        context.expected = "alse";
                        break;
                    case 'n':
                        if (context.primitive(context, LaxJsonTypeNull))
                            return LaxJsonErrorAborted;
                        context.state = LaxJsonStateExpect;
                        context.expected = "ull";
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.Array => switch (c) {
                switch (c) {
                    case WHITESPACE:
                    case ',':
                        /* ignore */
                        break;
                    case '/':
                        context.state = LaxJsonStateCommentBegin;
                        %%return push_state(context, LaxJsonStateArray);
                        break;
                    case ']':
                        if (context.end(context, LaxJsonTypeArray))
                            return LaxJsonErrorAborted;
                        pop_state(context);
                        break;
                    default:
                        context.state = LaxJsonStateValue;
                        %%return push_state(context, LaxJsonStateArray);

                        /* rewind 1 character */
                        *index -= 1;
                        context.column -= 1;
                        continue;
                }
            },
            LaxJsonState.Number => switch (c) {
                switch (c) {
                    case DIGIT:
                        %%return buffer_char(context, c);
                        break;
                    case '.':
                        %%return buffer_char(context, c);
                        context.state = LaxJsonStateNumberDecimal;
                        break;
                    case NUMBER_TERMINATOR:
                        %%return buffer_char(context, '\0');
                        if (context.number(context, atof(context.value_buffer)))
                            return LaxJsonErrorAborted;
                        pop_state(context);

                        /* rewind 1 */
                        *index -= 1;
                        context.column -= 1;
                        continue;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberDecimal => switch (c) {
                switch (c) {
                    case DIGIT:
                        %%return buffer_char(context, c);
                        break;
                    case 'e':
                    case 'E':
                        %%return buffer_char(context, 'e');
                        context.state = LaxJsonStateNumberExponentSign;
                        break;
                    case NUMBER_TERMINATOR:
                        context.state = LaxJsonStateNumber;
                        /* rewind 1 */
                        *index -= 1;
                        context.column -= 1;
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberExponentSign => switch (c) {
                switch (c) {
                    case '+':
                    case '-':
                        %%return buffer_char(context, c);
                        context.state = LaxJsonStateNumberExponent;
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberExponent => switch (c) {
                switch (c) {
                    case DIGIT:
                        %%return buffer_char(context, c);
                        break;
                    case ',':
                    case WHITESPACE:
                    case ']':
                    case '}':
                    case '/':
                        %%return buffer_char(context, '\0');
                        if (context.number(context, atof(context.value_buffer)))
                            return LaxJsonErrorAborted;
                        pop_state(context);

                        /* rewind 1 */
                        *index -= 1;
                        context.column -= 1;
                        continue;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.Expect => {
                if (c == *context.expected) {
                    context.expected += 1;
                    if (*context.expected == 0) {
                        pop_state(context);
                    }
                } else {
                    return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.CommentBegin => switch (c) {
                switch (c) {
                    case '/':
                        context.state = LaxJsonState.CommentLine;
                        break;
                    case '*':
                        context.state = LaxJsonState.CommentMultiLine;
                        break;
                    default:
                        return LaxJsonError.UnexpectedChar;
                }
            },
            LaxJsonState.CommentLine => {
                if (c == '\n')
                    pop_state(context);
            },
            LaxJsonState.CommentMultiLine => {
                if (c == '*')
                    context.state = LaxJsonState.CommentMultiLineStar;
            },
            LaxJsonState.CommentMultiLineStar => {
                if (c == '/')
                    pop_state(context);
                else
                    context.state = LaxJsonState.CommentMultiLine;
            },
        }
    }
    return err;
}

fn push_state(context: &LaxJsonContext, state: LaxJsonState) LaxJsonError => {
    var new_ptr: &LaxJsonState;

    if context.state_stack_index >= context.state_stack_size {
        context.state_stack_size += 1024;
        if context.state_stack_size > context.max_state_stack_size {
            return LaxJsonError.ExceededMaxStack;
        }
        new_ptr = realloc(context.state_stack, context.state_stack_size * @sizeof(LaxJsonState)) ?? {
            return LaxJsonError.NoMem;
        };
        context.state_stack = new_ptr;
    }
    context.state_stack[context.state_stack_index] = state;
    context.state_stack_index += 1;
    return LaxJsonError.None;
}

fn buffer_char(context: &LaxJsonContext, c: u8) LaxJsonError => {
    if (context.value_buffer_index >= context.value_buffer_size) {
        context.value_buffer_size += 16384;
        if (context.value_buffer_size > context.max_value_buffer_size) {
            return LaxJsonError.ExceededMaxValueSize;
        }
        context.value_buffer = realloc(context.value_buffer, context.value_buffer_size)
            ?? return LaxJsonError.NoMem;
    }
    context.value_buffer[context.value_buffer_index] = c;
    context.value_buffer_index += 1;
    return LaxJsonError.None;
}

fn pop_state(context: &LaxJsonContext) => {
    context.state_stack_index -= 1;
    context.state = context.state_stack[context.state_stack_index];
    if (!(context.state_stack_index >= 0)) { unreachable{} }
}

fn is_whitespace(c : u8) bool => {
    switch (c) {
        ' ', '\t', '\n', '\f', '\r', 0xb => true,
        _ => false,
    }
}

fn is_digit(c : u8) bool => {
    switch (c) {
        '0' .. '9' => true,
        _ => false,
    }
}

fn is_alphanumeric(c : u8) bool => {
    switch (c) {
        'a' .. 'z', 'A' .. 'Z', '0' .. '9' => true,
        _ => false,
    }
}

fn is_number_terminator(c : u8) bool => {
    switch (c) {
        ',', ']', '}', '/' => true,
        _ => is_whitespace(c),
    }
}

fn is_valid_unquoted(c : u8) bool => {
    switch (c) {
        '-', '_', '#', '$', '%', '&', '<', '>', '=', '~', '|', '@',
        '?', ';', '.', '+', '*', '(', ')' => true,
        _ => is_alphanumeric(c),
    }
}
