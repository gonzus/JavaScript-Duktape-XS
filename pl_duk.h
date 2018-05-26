#ifndef PL_DUK_H
#define PL_DUK_H

#include "duktape.h"

#include "EXTERN.h"
#include "perl.h"

#define DUK_OPT_NAME_GATHER_STATS      "gather_stats"
#define DUK_OPT_NAME_SAVE_MESSAGES     "save_messages"

#define DUK_OPT_FLAG_GATHER_STATS      0x01
#define DUK_OPT_FLAG_SAVE_MESSAGES     0x02

/*
 * This is our internal data structure.  For now it only contains a pointer to
 * a duktape context.  We will add other stuff here.
 */
typedef struct Duk {
    duk_context* ctx;
    int pagesize;
    unsigned long flags;
    HV* stats;
    HV* msgs;
} Duk;

/*
 * We use these two functions to convert back and forth between the Perl
 * representation of an object and the JS one.
 *
 * Because data in Perl and JS can be nested (array of hashes of arrays of...),
 * the functions are recursive.
 *
 * pl_duk_to_perl: takes a JS value from a given position in the duktape stack,
 * and creates the equivalent Perl value.
 *
 * pl_perl_to_duk: takes a Perl value and leaves the equivalent JS value at the
 * top of the duktape stack.
 */
SV* pl_duk_to_perl(pTHX_ duk_context* ctx, int pos);
int pl_perl_to_duk(pTHX_ SV* value, duk_context* ctx);

/*
 * This is a generic dispatcher that allows calling any Perl function from JS.
 */
int pl_call_perl_sv(duk_context* ctx, SV* func);

#endif
