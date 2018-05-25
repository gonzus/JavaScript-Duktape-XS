#include <stdio.h>
#include "pl_eventloop.h"
#include "c_eventloop.h"

int pl_register_eventloop(Duk* duk)
{
    // Register our event loop dispatcher, otherwise calls to
    // dispatch_function_in_event_loop will not work.
    eventloop_register(duk->ctx);
    return 0;
}

int pl_run_function_in_event_loop(Duk* duk, const char* func)
{
    duk_context* ctx = duk->ctx;

    // Start a zero timer which will call our function from the event loop.
    duk_int_t rc = 0;
    char js[256];
    int len = sprintf(js, "setTimeout(function() { %s(); }, 0);", func);
    rc = duk_peval_lstring(ctx, js, len);
    if (rc != DUK_EXEC_SUCCESS) {
        croak("Could not eval JS event loop dispatcher %*.*s: %d - %s\n",
              len, len, js, rc, duk_safe_to_string(ctx, -1));
    }
    duk_pop(ctx);

    // Launch eventloop; this call only returns after the eventloop terminates.
    rc = duk_safe_call(ctx, eventloop_run, duk, 0 /*nargs*/, 1 /*nrets*/);
    if (rc != DUK_EXEC_SUCCESS) {
        croak("JS event loop run failed: %d - %s\n",
              rc, duk_safe_to_string(ctx, -1));
    }
    duk_pop(ctx);

    return 0;
}
