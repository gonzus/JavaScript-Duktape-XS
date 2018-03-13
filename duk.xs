#define PERL_NO_GET_CONTEXT      /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
/* #include "ppport.h" */

#include "duktape.h"
#define UNUSED_ARG(x) (void) x

static int session_dtor(pTHX_ SV* sv, MAGIC* mg)
{
    UNUSED_ARG(sv);
    duk_context* duk = (duk_context*) mg->mg_ptr;
    fprintf(stderr, "[%p] destroying duk\n", duk);
    duk_destroy_heap(duk);
    return 0;
}

static duk_ret_t native_print(duk_context *duk) {
    duk_push_string(duk, " ");
    duk_insert(duk, 0);
    duk_join(duk, duk_get_top(duk) - 1);
    printf("%s\n", duk_safe_to_string(duk, -1));
    return 0;
}

static MGVTBL session_magic_vtbl = { .svt_free = session_dtor };

MODULE = JavaScript::Duktape::XS       PACKAGE = JavaScript::Duktape::XS
PROTOTYPES: DISABLE

#################################################################

duk_context*
new(char* CLASS, HV* opt = NULL)
  CODE:
    duk_context *duk = duk_create_heap_default();
    RETVAL = duk;
    fprintf(stderr, "[%p] created duktape\n", duk);

    duk_push_c_function(duk, native_print, DUK_VARARGS);
    duk_put_global_string(duk, "print");
    fprintf(stderr, "[%p] added function print\n", duk);
  OUTPUT: RETVAL

int
run(duk_context* duk)
  CODE:
    fprintf(stderr, "[%p] entering run\n", duk);
    if (!duk) {
        croak("OOPS");
    }

    const char* cmd = "print('Hello world from Javascript!');";
    fprintf(stderr, "[%p] calling eval [%s]\n", duk, cmd);
    duk_eval_string(duk, cmd);
    fprintf(stderr, "[%p] called eval, result is: %s\n", duk, duk_get_string(duk, -1));
    duk_pop(duk);
    fprintf(stderr, "[%p] popped stack\n", duk);

    RETVAL = 1;
  OUTPUT: RETVAL
