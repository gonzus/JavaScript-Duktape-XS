#if !defined(DUK_CONSOLE_H_INCLUDED)
#define DUK_CONSOLE_H_INCLUDED

#include "duktape.h"

#if defined(__cplusplus)
extern "C" {
#endif

/* Use a proxy wrapper to make undefined methods (console.foo()) no-ops. */
#define DUK_CONSOLE_PROXY_WRAPPER  (1 << 0)

/* Flush output after every call. */
#define DUK_CONSOLE_FLUSH          (1 << 1)

void duk_console_init(duk_context *ctx, duk_uint_t flags);

/* Expose this so it is callable from C */
int duk_c_console_log(int to_stderr, int do_flush, const char* fmt, ...);

#if defined(__cplusplus)
}
#endif  /* end 'extern "C"' wrapper */

#endif  /* DUK_CONSOLE_H_INCLUDED */
