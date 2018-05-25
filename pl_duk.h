#ifndef PL_DUK_H
#define PL_DUK_H

#include "util.h"
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

#endif
