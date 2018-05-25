#ifndef PL_DUK_H
#define PL_DUK_H

#include "util.h"
#include "duktape.h"

#include "EXTERN.h"
#include "perl.h"

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

#endif
