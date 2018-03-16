#define PERL_NO_GET_CONTEXT      /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "duktape.h"

#define UNUSED_ARG(x) (void) x
#define DUK_SLOT_CALLBACK "_perl_.callback"

static SV* duk_to_perl(pTHX_ duk_context* duk, int pos);
static int perl_to_duk(pTHX_ SV* value, duk_context* duk);

static duk_ret_t perl_caller(duk_context *duk)
{
    duk_push_current_function(duk);
    duk_get_prop_string(duk, -1, DUK_SLOT_CALLBACK);
    SV* func = (SV*) duk_get_pointer(duk, -1);
    duk_pop_2(duk);  /* pop pointer and function */
    if (func == 0) {
        croak("Could not get value for property %s\n", DUK_SLOT_CALLBACK);
    }

    dTHX;
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    // params
    duk_idx_t nargs = duk_get_top(duk);
    // fprintf(stderr, "function called with %d args\n", nargs);
    for (duk_idx_t j = 0; j < nargs; j++) {
        int type = duk_get_type(duk, j);
        // fprintf(stderr, "type of argument %d: %d\n", j, type);
        SV* val = duk_to_perl(aTHX_ duk, j);
        // duk_pop(duk);
        mXPUSHs(val);
    }

    PUTBACK;
    call_sv(func, G_SCALAR | G_EVAL);
    SPAGAIN;
    SV* ret = POPs;
    perl_to_duk(aTHX_ ret, duk);
    PUTBACK;
    FREETMPS;
    LEAVE;
    return 0;
}

static SV* duk_to_perl(pTHX_ duk_context* duk, int pos)
{
    SV* ret = &PL_sv_undef; // return undef by default
    switch (duk_get_type(duk, pos)) {
        case DUK_TYPE_NONE:
        case DUK_TYPE_UNDEFINED:
        case DUK_TYPE_NULL: {
            // fprintf(stderr, "YO UNDEF\n");
            break;
        }
        case DUK_TYPE_BOOLEAN: {
            duk_bool_t val = duk_get_boolean(duk, pos);
            ret = newSViv(val);
            // fprintf(stderr, "YO BOOLEAN %d\n", val);
            break;
        }
        case DUK_TYPE_NUMBER: {
            duk_double_t val = duk_get_number(duk, pos);
            ret = newSVnv(val);  // JS numbers are always doubles
            // fprintf(stderr, "YO NUMBER %lf\n", val);
            break;
        }
        case DUK_TYPE_STRING: {
            duk_size_t clen = 0;
            const char* cstr = duk_get_lstring(duk, pos, &clen);
            ret = newSVpvn(cstr, clen);
            // fprintf(stderr, "YO STRING [%*.*s]\n", clen, clen, cstr);
            break;
        }
        case DUK_TYPE_OBJECT: {
            if (duk_is_c_function(duk, pos)) {
                // if the JS function has a slot with the Perl callback,
                // then we know we created it, so we return it
                if (duk_get_prop_string(duk, -1, DUK_SLOT_CALLBACK)) {
                    ret = (SV*) duk_get_pointer(duk, -1);
                    // fprintf(stderr, "YO OBJECT FUNCTION PERL %p\n", ret);
                    duk_pop(duk); // pop function
                } else {
                    // fprintf(stderr, "YO OBJECT FUNCTION\n");
                }
            } else if (duk_is_array(duk, pos)) {
                int n = duk_get_length(duk, pos);
                // fprintf(stderr, "YO OBJECT ARRAY %d\n", n);
                AV* values = newAV();
                for (int j = 0; j < n; ++j) {
                    if (!duk_get_prop_index(duk, pos, j)) {
                        continue;
                    }
                    SV* nested = sv_2mortal(duk_to_perl(aTHX_ duk, -1));
                    duk_pop(duk);
                    if (!nested) {
                        continue;
                    }
                    if (av_store(values, j, nested)) {
                        SvREFCNT_inc(nested);
                    }
                }
                ret = newRV_noinc((SV*) values);
                // fprintf(stderr, "Created AV ref %p\n", ret);
                // sv_dump(ret);
            } else if (duk_is_object(duk, pos)) {
                HV* values = newHV();
                // fprintf(stderr, "YO OBJECT HASH\n");
                duk_enum(duk, pos, 0);
                while (duk_next(duk, -1, 1)) {
                    // fprintf(stderr, "KEY [%s] VAL [%s]\n", duk_safe_to_string(duk, -2), duk_safe_to_string(duk, -1));
                    duk_size_t klen = 0;
                    const char* kstr = duk_get_lstring(duk, -2, &klen);
                    // fprintf(stderr, "KEY [%*.*s]\n", klen, klen, kstr);
                    SV* nested = sv_2mortal(duk_to_perl(aTHX_ duk, -1));
                    // fprintf(stderr, "VAL nested for KEY [%*.*s]\n", klen, klen, kstr);
                    duk_pop_2(duk); // key and value
                    if (!nested) {
                        continue;
                    }
                    // fprintf(stderr, "Adding ref %p to hash key [%*.*s]\n", nested, klen, klen, kstr);
                    if (hv_store(values, kstr, klen, nested, 0)) {
                        SvREFCNT_inc(nested);
                    }
                }
                duk_pop(duk);  // iterator
                ret = newRV_noinc((SV*) values);
                // fprintf(stderr, "Created HV ref %p\n", ret);
                // sv_dump(ret);
            } else {
                // fprintf(stderr, "YO WOW\n");
            }
            break;
        }
        case DUK_TYPE_POINTER: {
            // fprintf(stderr, "[%p] TODO DUK_TYPE_POINTER\n", duk);
            break;
        }
        case DUK_TYPE_BUFFER: {
            // fprintf(stderr, "[%p] TODO DUK_TYPE_BUFFER\n", duk);
            break;
        }
        case DUK_TYPE_LIGHTFUNC: {
            // fprintf(stderr, "[%p] TODO DUK_TYPE_LIGHTFUNC\n", duk);
            break;
        }
        default:
            // fprintf(stderr, "REALLY WTF?\n");
            break;
    }
    return ret;
}

static int perl_to_duk(pTHX_ SV* value, duk_context* duk)
{
    int ret = 1;
    if (value == &PL_sv_undef) {
        duk_push_null(duk);
        // fprintf(stderr, "[%p] push null\n", duk);
    } else if (SvIOK(value)) {
        int val = SvIV(value);
        duk_push_int(duk, val);
        // fprintf(stderr, "[%p] push int %d\n", duk, val);
    } else if (SvNOK(value)) {
        double val = SvNV(value);
        duk_push_number(duk, val);
        // fprintf(stderr, "[%p] push number %lf\n", duk, val);
    } else if (SvPOK(value)) {
        STRLEN vlen = 0;
        const char* vstr = SvPV_const(value, vlen);
        duk_push_lstring(duk, vstr, vlen);
        // fprintf(stderr, "[%p] push string [%*.*s]\n", duk, vlen, vlen, vstr);
    } else if (SvROK(value)) {
        SV* ref = SvRV(value);
        if (SvTYPE(ref) == SVt_PVAV) {
            AV* values = (AV*) ref;
            // sv_dump(values);
            duk_idx_t pos = duk_push_array(duk);
            int n = av_top_index(values);
            int count = 0;
            for (int j = 0; j <= n; ++j) {
                SV** elem = av_fetch(values, j, 0);
                // sv_dump(*elem);
                if (!elem || !*elem) {
                    break;
                }
                if (!perl_to_duk(aTHX_ *elem, duk)) {
                    continue;
                }
                duk_put_prop_index(duk, pos, count);
                ++count;
            }
            // fprintf(stderr, "[%p] push array with %d elems\n", duk, count);
        } else if (SvTYPE(ref) == SVt_PVHV) {
            HV* values = (HV*) ref;
            // sv_dump(values);
            duk_idx_t obj = duk_push_object(duk);
            hv_iterinit(values);
            int count = 0;
            while (1) {
                SV* value = 0;
                I32 klen = 0;
                char* kstr = 0;
                HE* entry = hv_iternext(values);
                if (!entry) {
                    break; // no more hash keys
                }
                kstr = hv_iterkey(entry, &klen);
                if (!kstr || klen < 0) {
                    continue; // invalid key
                }
                value = hv_iterval(values, entry);
                if (!value) {
                    continue; // invalid value
                }
                // fprintf(stderr, "HASH value #%d ======\n", count);
                // sv_dump(value);
                if (!perl_to_duk(aTHX_ value, duk)) {
                    continue;
                }
                duk_put_prop_lstring(duk, obj, kstr, klen);
                // fprintf(stderr, "HASH #%d key [%*.*s]\n", count, klen, klen, kstr);
                ++count;
            }
            // fprintf(stderr, "[%p] push hash with %d elems\n", duk, count);
        } else if (SvTYPE(ref) == SVt_PVCV) {
            duk_push_c_function(duk, perl_caller, DUK_VARARGS);
            SV* func = newSVsv(value);
            duk_push_pointer(duk, func);
            duk_put_prop_string(duk, -2, DUK_SLOT_CALLBACK);
            // fprintf(stderr, "[%] push (Perl) function %p\n", func);
            // sv_dump(func);
        } else {
            // fprintf(stderr, "WTF #1\n");
            ret = 0;
        }
    } else {
        // fprintf(stderr, "WTF #2\n");
        ret = 0;
    }
    return ret;
}

static duk_ret_t native_say(duk_context *duk)
{
    duk_push_string(duk, " ");
    duk_insert(duk, 0);
    duk_join(duk, duk_get_top(duk) - 1);
    printf("%s\n", duk_safe_to_string(duk, -1));
    return 0;
}

static int session_dtor(pTHX_ SV* sv, MAGIC* mg)
{
    UNUSED_ARG(sv);
    duk_context* duk = (duk_context*) mg->mg_ptr;
    // fprintf(stderr, "[%p] destroying duk\n", duk);
    duk_destroy_heap(duk);
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
    // fprintf(stderr, "[%p] created duktape\n", duk);
    static struct Data {
        const char* name;
        duk_c_function func;
    } data[] = {
        { "say", native_say },
    };
    for (unsigned int j = 0; j < sizeof(data) / sizeof(data[0]); ++j) {
        duk_push_c_function(duk, data[j].func, DUK_VARARGS);
        duk_put_global_string(duk, data[j].name);
        // fprintf(stderr, "[%p] added native function %s => %p\n", duk, data[j].name, data[j].func);
    }
  OUTPUT: RETVAL

SV*
get(duk_context* duk, const char* name)
  CODE:
    SV* ret = &PL_sv_undef;
    duk_bool_t ok = duk_get_global_string(duk, name);
    if (ok) {
        ret = duk_to_perl(aTHX_ duk, -1);
        duk_pop(duk);
    }
    RETVAL = ret;
    // fprintf(stderr, "******* set done\n");
  OUTPUT: RETVAL

int
set(duk_context* duk, const char* name, SV* value)
  CODE:
    if (perl_to_duk(aTHX_ value, duk)) {
        duk_put_global_string(duk, name);
        RETVAL = 1;
    } else {
        RETVAL = 0;
    }
    // fprintf(stderr, "******* set done\n");
  OUTPUT: RETVAL

SV*
eval(duk_context* duk, const char* js)
  PREINIT:
    SV* ret = 0;
  CODE:
    duk_eval_string(duk, js);
    ret = duk_to_perl(aTHX_ duk, -1);
    duk_pop(duk);
    RETVAL = ret;

  OUTPUT: RETVAL
