/*
 * Copyright (c) 2013 Andrew Kelley
 *
 * This file is part of liblaxjson, which is MIT licensed.
 * See http://opensource.org/licenses/MIT
 */

#version("1.0.5")
export library "laxjson";

#link("c")
include!("stdlib.h");

#c_header_name("void")
type c_void = u8;
#c_header_name("char")
type c_char = u8;

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
    int (*string)(struct LaxJsonContext *, enum LaxJsonType type, const char *value, int length);
    /// type is always number
    int (*number)(struct LaxJsonContext *, double x);
    /// type can be true, false, or null
    int (*primitive)(struct LaxJsonContext *, enum LaxJsonType type);
    /// type can be array or object
    int (*begin)(struct LaxJsonContext *, enum LaxJsonType type);
    /// type can be array or object
    int (*end)(struct LaxJsonContext *, enum LaxJsonType type);

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

export fn lax_json_create() -> ?&LaxJsonContext {
    const context : &LaxJsonContext = calloc(1, #sizeof(LaxJsonContext)) ?? return None;

    context.value_buffer_size = 1024;
    context.value_buffer = malloc(context.value_buffer_size) ?? {
        lax_json_destroy(context);
        return None;
    };

    context.state_stack_size = 1024;
    context.state_stack = malloc(context.state_stack_size * #sizeof(LaxJsonState)) ?? {
        lax_json_destroy(context);
        return None;
    };

    context.line = 1;
    context.max_state_stack_size = 16384;
    context.max_value_buffer_size = 1048576; /* 1 MB */

    push_state(context, LaxJsonStateEnd);

    return context;
}

export fn lax_json_destroy(context: &LaxJsonContext) {
    free(context.state_stack);
    free(context.value_buffer);
    free(context);
}

const HEX_MULT = [4096, 256, 16, 1];

export fn lax_json_feed(context: &LaxJsonContext, size: c_int, data: &const c_char) -> LaxJsonError {
    var err : LaxJsonError = LaxJsonError.None;
    var x : i32;
    var byte : u8;
    var end : &const u8 = data + size;
    for end = data + size; data < end; data += 1 {
        const c = *data;
        if c == '\n' {
            context.line += 1;
            context.column = 0;
        } else {
            context.column += 1;
        }
        match context.state {
            LaxJsonState.End => {
                if is_whitespace(c) {
                    // ignore
                } else if c == '/' {
                    context.state = LaxJsonState.CommentBegin;
                    return_if_error push_state(context, LaxJsonStateEnd);
                } else {
                    return LaxJsonErrorExpectedEof;
                }
            },
            LaxJsonState.Object => {
                if is_whitespace(c) || c == ',' {
                    // do nothing except eat these characters
                } else if c == '/' {
                    context.state = LaxJsonState.CommentBegin;
                    return_if_error push_state(context, LaxJsonState.Object);
                } else if c == '"' || c == '\'' {
                    context.state = LaxJsonState.String;
                    context.value_buffer_index = 0;
                    context.delim = c;
                    context.string_type = LaxJsonType.Property;
                    return_if_error push_state(context, LaxJsonState.Colon);
                } else if is_valid_unquoted(c) {
                    context.state = LaxJsonState.BareProp;
                    context.value_buffer[0] = c;
                    context.value_buffer_index = 1;
                    context.delim = 0;
                } else if c == '}' {
                    if context.end(context, LaxJsonType.Object)
                        return LaxJsonError.Aborted;
                    pop_state(context);
                } else {
                    return LaxJsonError.UnexpectedChar;
                }
            },
            LaxJsonState.BareProp => {
                if is_valid_unquoted(c) {
                        return_if_error buffer_char(context, c);
                        break;
                } else if is_whitespace(c) {
                        return_if_error buffer_char(context, '\0');
                        if (context->string(context, LaxJsonTypeProperty, context->value_buffer,
                                context->value_buffer_index - 1))
                        {
                            return LaxJsonErrorAborted;
                        }
                        context->state = LaxJsonStateColon;
                        break;
                } else if c == ':' {
                        return_if_error buffer_char(context, '\0');
                        if (context->string(context, LaxJsonTypeProperty, context->value_buffer,
                                context->value_buffer_index - 1))
                        {
                            return LaxJsonErrorAborted;
                        }
                        context->state = LaxJsonStateValue;
                        context->string_type = LaxJsonTypeString;
                        return_if_error push_state(context, LaxJsonStateObject);
                        break;
                } else {
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.String => {
                if (c == context->delim) {
                    return_if_error buffer_char(context, '\0');
                    if (context->string(context, context->string_type, context->value_buffer,
                            context->value_buffer_index - 1))
                    {
                        return LaxJsonErrorAborted;
                    }
                    pop_state(context);
                } else if (c == '\\') {
                    context->state = LaxJsonStateStringEscape;
                } else {
                    return_if_error buffer_char(context, c);
                }
            }
            LaxJsonState.StringEscape => {
                if c == '\'' || c == '"' || c == '/' || c == '\\' {
                        return_if_error buffer_char(context, c);
                        context->state = LaxJsonStateString;
                } else if c == 'b' {
                        return_if_error buffer_char(context, '\b');
                        context->state = LaxJsonStateString;
                } else if c == 'f' {
                        return_if_error buffer_char(context, '\f');
                        context->state = LaxJsonStateString;
                } else if c == 'n' {
                        return_if_error buffer_char(context, '\n');
                        context->state = LaxJsonStateString;
                } else if c == 'r' {
                        return_if_error buffer_char(context, '\r');
                        context->state = LaxJsonStateString;
                } else if c == 't' {
                        return_if_error buffer_char(context, '\t');
                        context->state = LaxJsonStateString;
                } else if c == 'u' {
                        context->state = LaxJsonStateUnicodeEscape;
                        context->unicode_digit_index = 0;
                        context->unicode_point = 0;
                }
            },
            LaxJsonState.UnicodeEscape => {
                switch (c) {
                    case '0':
                        x = 0;
                        break;
                    case '1':
                        x = 1;
                        break;
                    case '2':
                        x = 2;
                        break;
                    case '3':
                        x = 3;
                        break;
                    case '4':
                        x = 4;
                        break;
                    case '5':
                        x = 5;
                        break;
                    case '6':
                        x = 6;
                        break;
                    case '7':
                        x = 7;
                        break;
                    case '8':
                        x = 8;
                        break;
                    case '9':
                        x = 9;
                        break;
                    case 'a':
                    case 'A':
                        x = 10;
                        break;
                    case 'b':
                    case 'B':
                        x = 11;
                        break;
                    case 'c':
                    case 'C':
                        x = 12;
                        break;
                    case 'd':
                    case 'D':
                        x = 13;
                        break;
                    case 'e':
                    case 'E':
                        x = 14;
                        break;
                    case 'f':
                    case 'F':
                        x = 15;
                        break;
                    default:
                        return LaxJsonErrorInvalidHexDigit;
                }
                context->unicode_point += x * HEX_MULT[context->unicode_digit_index];
                context->unicode_digit_index += 1;
                if (context->unicode_digit_index == 4) {
                    if (context->unicode_point <= 0x007f) {
                        /* 1 byte */
                        return_if_error buffer_char(context, (char)context->unicode_point);
                        context->state = LaxJsonStateString;
                    } else if (context->unicode_point <= 0x07ff) {
                        /* 2 bytes */
                        byte = (0xc0 | (context->unicode_point >> 6));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                    } else if (context->unicode_point <= 0xffff) {
                        /* 3 bytes */
                        byte = (0xe0 | (context->unicode_point >> 12));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 6) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                    } else if (context->unicode_point <= 0x1fffff) {
                        /* 4 bytes */
                        byte = (0xf0 | (context->unicode_point >> 18));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 12) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 6) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                    } else if (context->unicode_point <= 0x3ffffff) {
                        /* 5 bytes */
                        byte = (0xf8 | (context->unicode_point >> 24));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point >> 18));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 12) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 6) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                    } else if (context->unicode_point <= 0x7fffffff) {
                        /* 6 bytes */
                        byte = (0xfc | (context->unicode_point >> 30));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 24) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 18) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 12) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | ((context->unicode_point >> 6) & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                        byte = (0x80 | (context->unicode_point & 0x3f));
                        return_if_error buffer_char(context, *(char *)(&byte));
                    } else {
                        return LaxJsonErrorInvalidUnicodePoint;
                    }
                    context->state = LaxJsonStateString;
                }
            },
            LaxJsonState.Colon => match c {
                switch (c) {
                    case WHITESPACE:
                        /* ignore it */
                        break;
                    case '/':
                        context->state = LaxJsonStateCommentBegin;
                        return_if_error push_state(context, LaxJsonStateColon);
                        break;
                    case ':':
                        context->state = LaxJsonStateValue;
                        context->string_type = LaxJsonTypeString;
                        return_if_error push_state(context, LaxJsonStateObject);
                        break;
                    default:
                        return LaxJsonErrorExpectedColon;
                }
            },
            LaxJsonState.Value => match c {
                switch (c) {
                    case WHITESPACE:
                        /* ignore */
                        break;
                    case '/':
                        context->state = LaxJsonStateCommentBegin;
                        return_if_error push_state(context, LaxJsonStateValue);
                        break;
                    case '{':
                        if (context->begin(context, LaxJsonTypeObject))
                            return LaxJsonErrorAborted;
                        context->state = LaxJsonStateObject;
                        break;
                    case '[':
                        if (context->begin(context, LaxJsonTypeArray))
                            return LaxJsonErrorAborted;
                        context->state = LaxJsonStateArray;
                        break;
                    case '\'':
                    case '"':
                        context->state = LaxJsonStateString;
                        context->delim = c;
                        context->value_buffer_index = 0;
                        break;
                    case '-':
                        context->state = LaxJsonStateNumber;
                        context->value_buffer[0] = c;
                        context->value_buffer_index = 1;
                        break;
                    case '+':
                        context->state = LaxJsonStateNumber;
                        context->value_buffer_index = 0;
                        break;
                    case DIGIT:
                        context->state = LaxJsonStateNumber;
                        context->value_buffer_index = 1;
                        context->value_buffer[0] = c;
                        break;
                    case 't':
                        if (context->primitive(context, LaxJsonTypeTrue))
                            return LaxJsonErrorAborted;
                        context->state = LaxJsonStateExpect;
                        context->expected = "rue";
                        break;
                    case 'f':
                        if (context->primitive(context, LaxJsonTypeFalse))
                            return LaxJsonErrorAborted;
                        context->state = LaxJsonStateExpect;
                        context->expected = "alse";
                        break;
                    case 'n':
                        if (context->primitive(context, LaxJsonTypeNull))
                            return LaxJsonErrorAborted;
                        context->state = LaxJsonStateExpect;
                        context->expected = "ull";
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.Array => match c {
                switch (c) {
                    case WHITESPACE:
                    case ',':
                        /* ignore */
                        break;
                    case '/':
                        context->state = LaxJsonStateCommentBegin;
                        return_if_error push_state(context, LaxJsonStateArray);
                        break;
                    case ']':
                        if (context->end(context, LaxJsonTypeArray))
                            return LaxJsonErrorAborted;
                        pop_state(context);
                        break;
                    default:
                        context->state = LaxJsonStateValue;
                        return_if_error push_state(context, LaxJsonStateArray);

                        /* rewind 1 character */
                        data -= 1;
                        context->column -= 1;
                        continue;
                }
            },
            LaxJsonState.Number => match c {
                switch (c) {
                    case DIGIT:
                        return_if_error buffer_char(context, c);
                        break;
                    case '.':
                        return_if_error buffer_char(context, c);
                        context->state = LaxJsonStateNumberDecimal;
                        break;
                    case NUMBER_TERMINATOR:
                        return_if_error buffer_char(context, '\0');
                        if (context->number(context, atof(context->value_buffer)))
                            return LaxJsonErrorAborted;
                        pop_state(context);

                        /* rewind 1 */
                        data -= 1;
                        context->column -= 1;
                        continue;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberDecimal => match c {
                switch (c) {
                    case DIGIT:
                        return_if_error buffer_char(context, c);
                        break;
                    case 'e':
                    case 'E':
                        return_if_error buffer_char(context, 'e');
                        context->state = LaxJsonStateNumberExponentSign;
                        break;
                    case NUMBER_TERMINATOR:
                        context->state = LaxJsonStateNumber;
                        /* rewind 1 */
                        data -= 1;
                        context->column -= 1;
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberExponentSign => match c {
                switch (c) {
                    case '+':
                    case '-':
                        return_if_error buffer_char(context, c);
                        context->state = LaxJsonStateNumberExponent;
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.NumberExponent => match c {
                switch (c) {
                    case DIGIT:
                        return_if_error buffer_char(context, c);
                        break;
                    case ',':
                    case WHITESPACE:
                    case ']':
                    case '}':
                    case '/':
                        return_if_error buffer_char(context, '\0');
                        if (context->number(context, atof(context->value_buffer)))
                            return LaxJsonErrorAborted;
                        pop_state(context);

                        /* rewind 1 */
                        data -= 1;
                        context->column -= 1;
                        continue;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.Expect => {
                if (c == *context->expected) {
                    context->expected += 1;
                    if (*context->expected == 0) {
                        pop_state(context);
                    }
                } else {
                    return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.CommentBegin => match c {
                switch (c) {
                    case '/':
                        context->state = LaxJsonStateCommentLine;
                        break;
                    case '*':
                        context->state = LaxJsonStateCommentMultiLine;
                        break;
                    default:
                        return LaxJsonErrorUnexpectedChar;
                }
            },
            LaxJsonState.CommentLine => {
                if (c == '\n')
                    pop_state(context);
            },
            LaxJsonState.CommentMultiLine => {
                if (c == '*')
                    context->state = LaxJsonStateCommentMultiLineStar;
            },
            LaxJsonState.CommentMultiLineStar => {
                if (c == '/')
                    pop_state(context);
                else
                    context->state = LaxJsonStateCommentMultiLine;
            },
        }
    }
    return err;
}

export fn lax_json_eof(context: &LaxJsonContext) -> LaxJsonError {
    while true {
        match context.state {
            LaxJsonStateEnd => return LaxJsonError.None,
            LaxJsonStateCommentLine => {
                pop_state(context);
                continue;
            },
            _ => return LaxJsonError.UnexpectedEof
        }
    }
}

export fn lax_json_str_err(err: LaxJsonError) -> &const c_char {
    match err {
        LaxJsonError.None =>  return "none",
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

fn push_state(context: &LaxJsonContext, state: LaxJsonState) -> LaxJsonError {
    var new_ptr: &LaxJsonState;

    if context.state_stack_index >= context.state_stack_size {
        context.state_stack_size += 1024;
        if context.state_stack_size > context.max_state_stack_size {
            return LaxJsonError.ExceededMaxStack;
        }
        new_ptr = realloc(context.state_stack, context.state_stack_size * #sizeof(LaxJsonState)) ?? {
            return LaxJsonError.NoMem;
        };
        context.state_stack = new_ptr;
    }
    context.state_stack[context.state_stack_index] = state;
    context.state_stack_index += 1;
    return LaxJsonError.None;
}

fn buffer_char(context: &LaxJsonContext, c: u8) -> LaxJsonError {
    var new_ptr: &u8;

    if context.value_buffer_index >= context.value_buffer_size {
        context.value_buffer_size += 16384;
        if context.value_buffer_size > context.max_value_buffer_size {
            return LaxJsonError.ExceededMaxValueSize;
        }
        new_ptr = realloc(context.value_buffer, context.value_buffer_size);
        if !new_ptr {
            return LaxJsonError.NoMem;
        }
        context.value_buffer = new_ptr;
    }
    context.value_buffer[context.value_buffer_index] = c;
    context.value_buffer_index += 1;
    return LaxJsonError.None;
}

fn pop_state(context: &LaxJsonContext) {
    context.state_stack_index -= 1;
    context.state = context.state_stack[context.state_stack_index];
    assert(context.state_stack_index >= 0);
}

fn is_whitespace(c : u8) -> bool {
    match c {
        ' ' | '\t' | '\n' | '\f' | '\r' | 0xb => true,
        _ => false,
    }
}

fn is_digit(c : u8) -> bool {
    match c {
        '0' ... '9' => true,
        _ => false,
    }
}

fn is_alphanumeric(c : u8) -> bool {
    match c {
        'a' ... 'z' | 'A' ... 'Z' | '0' ... '9' => true,
        _ => false,
    }
}

fn is_number_terminator(c : u8) -> bool {
    match c {
        ',' | ']' | '}' | '/' => true,
        _ => is_whitespace(c),
    }
}

fn is_valid_unquoted(c : u8) -> bool {
    match c {
        '-' | '_' | '#' | '$' | '%' | '&' | '<' | '>' | '=' | '~' | '|' | '@' |
        '?' | ';' | '.' | '+' | '*' | '(' | ')' => true,
        _ => is_alphanumeric(c),
    }
}
