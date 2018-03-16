#define PERL_NO_GET_CONTEXT      /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "duktape.h"

#define UNUSED_ARG(x) (void) x
#define DUK_SLOT_CALLBACK "_perl_.callback"

static SV* get_perl_value(pTHX_ duk_context* duk, int pos)
{
    SV* ret = &PL_sv_undef; // return undef by default
    switch (duk_get_type(duk, pos)) {
        case DUK_TYPE_NONE:
        case DUK_TYPE_UNDEFINED:
        case DUK_TYPE_NULL: {
            break;
        }
        case DUK_TYPE_BOOLEAN: {
            duk_bool_t val = duk_get_boolean(duk, pos);
            ret = newSViv(val);
            break;
        }
        case DUK_TYPE_NUMBER: {
            duk_double_t val = duk_get_number(duk, pos);
            ret = newSVnv(val);  // JS numbers are always doubles
            break;
        }
        case DUK_TYPE_STRING: {
            duk_size_t clen = 0;
            const char* cstr = duk_get_lstring(duk, pos, &clen);
            ret = newSVpvn(cstr, clen);
            break;
        }
        case DUK_TYPE_OBJECT: {
            if (duk_is_c_function(duk, pos)) {
                // if the JS function has a slot with the Perl callback,
                // then we know we created it, so we return it
                if (duk_get_prop_string(duk, -1, DUK_SLOT_CALLBACK)) {
                    ret = (SV*) duk_get_pointer(duk, -1);
                    duk_pop(duk);
                }
            } else if (duk_is_array(duk, pos)) {
                int n = duk_get_length(duk, pos);
                AV* array = newAV();
                for (int j = 0; j < n; ++j) {
                    if (!duk_get_prop_index(duk, pos, j)) {
                        continue;
                    }
                    SV* tmp = 0;
                    if (duk_is_number(duk, -1)) {
                        // fprintf(stderr, "NUMBER\n");
                        duk_double_t val = duk_get_number(duk, -1);
                        tmp = sv_2mortal(newSViv((int) val));  // IV for now
                    } else if (duk_is_string(duk, -1)) {
                        // fprintf(stderr, "STRING\n");
                        duk_size_t clen = 0;
                        const char* cstr = duk_get_lstring(duk, pos, &clen);
                        tmp = sv_2mortal(newSVpvn(cstr, clen));
                    } else {
                        fprintf(stderr, "WTF?\n");
                    }
                    duk_pop(duk);
                    if (!tmp) {
                        continue;
                    }
                    if (av_store(array, j, tmp)) {
                        SvREFCNT_inc(tmp);
                        fprintf(stderr, "STORE\n");
                    }
                }
                ret = newRV_noinc((SV*) array);
                // fprintf(stderr, "Created ref\n");
                // sv_dump(ret);
                // duk_pop(duk);
            }
            break;
        }
        case DUK_TYPE_POINTER: {
            fprintf(stderr, "[%p] TODO DUK_TYPE_POINTER\n", duk);
            break;
        }
        case DUK_TYPE_BUFFER: {
            fprintf(stderr, "[%p] TODO DUK_TYPE_BUFFER\n", duk);
            break;
        }
        case DUK_TYPE_LIGHTFUNC: {
            fprintf(stderr, "[%p] TODO DUK_TYPE_LIGHTFUNC\n", duk);
            break;
        }
    }
    duk_pop(duk);
    return ret;
}

static duk_ret_t perl_caller(duk_context *duk)
{
    duk_push_current_function(duk);
    duk_get_prop_string(duk, -1, DUK_SLOT_CALLBACK);
    SV* func = (SV*) duk_get_pointer(duk, -1);
    duk_pop_2(duk);  /* pop pointer and function */
    if (func == 0) {
        croak("Could not get value for property %s\n", DUK_SLOT_CALLBACK);
    }

    // TODO: pass args and return value of CV*
    dTHX;
    dSP;
    PUSHMARK(SP);
    // fprintf(stderr, "Should call function [%p]\n", func);
    // sv_dump(func);
    call_sv(func, G_DISCARD|G_NOARGS);
    return 0;
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
    fprintf(stderr, "[%p] destroying duk\n", duk);
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
    fprintf(stderr, "[%p] created duktape\n", duk);
    static struct Data {
        const char* name;
        duk_c_function func;
    } data[] = {
        { "say", native_say },
    };
    for (unsigned int j = 0; j < sizeof(data) / sizeof(data[0]); ++j) {
        duk_push_c_function(duk, data[j].func, DUK_VARARGS);
        duk_put_global_string(duk, data[j].name);
        fprintf(stderr, "[%p] added native function %s => %p\n", duk, data[j].name, data[j].func);
    }
  OUTPUT: RETVAL

SV*
get(duk_context* duk, const char* name)
  CODE:
    SV* ret = &PL_sv_undef;
    duk_bool_t ok = duk_get_global_string(duk, name);
    if (ok) {
        ret = get_perl_value(aTHX_ duk, -1);
    }
    RETVAL = ret;
  OUTPUT: RETVAL

int
set(duk_context* duk, const char* name, SV* value)
  CODE:
    if (SvIOK(value) || SvNOK(value) || SvPOK(value)) {
        STRLEN vlen = 0;
        const char* vstr = SvPV_const(value, vlen);
        duk_push_lstring(duk, vstr, vlen);
        duk_put_global_string(duk, name);
        // fprintf(stderr, "[%p] value [%s] => [%*.*s]\n", duk, name, vlen, vlen, vstr);
    } else if (SvROK(value)) {
        STRLEN vlen = 0;
        const char* vstr = 0;
        SV* ref = SvRV(value);
        if (SvTYPE(ref) == SVt_PVAV) {
            AV* values = (AV*) ref;
            // sv_dump(values);
            duk_idx_t arr_idx = duk_push_array(duk);
            int n = av_top_index(values);
            int count = 0;
            for (int j = 0; j <= n; ++j) {
                SV** elem = av_fetch(values, j, 0);
                // sv_dump(*elem);
                if (!*elem || *elem == &PL_sv_undef) {
                    break;
                }
                if (!SvOK(*elem)) {
                    continue;
                }
                if (SvIOK(*elem)) {
                    int val = SvIV(*elem);
                    // fprintf(stderr, "ARR %d => int %d\n", count, val);
                    duk_push_int(duk, val);
                    // duk_push_number(duk, val);
                } else if (SvNOK(*elem)) {
                    double val = SvNV(*elem);
                    fprintf(stderr, "ARR %d => double %lf\n", count, val);
                    duk_push_number(duk, val);
                } else {
                    vstr = SvPV_const(*elem, vlen);
                    fprintf(stderr, "ARR %d => string [%*.*s]\n", count, vlen, vlen, vstr);
                    duk_push_lstring(duk, vstr, vlen);
                }
                duk_put_prop_index(duk, arr_idx, count);
                ++count;
            }
            if (count <= 0) {
                duk_pop(duk);  /* pop array */
            } else {
                fprintf(stderr, "ARR %s with %d elems\n", name, count);
                duk_put_global_string(duk, name);
            }
        } else if (SvTYPE(ref) == SVt_PVHV) {
            fprintf(stderr, "[%p] TODO set a hashref\n", duk);
        } else if (SvTYPE(ref) == SVt_PVCV) {
            duk_push_c_function(duk, perl_caller, DUK_VARARGS);
            SV* func = newSVsv(value);
            duk_push_pointer(duk, func);
            duk_put_prop_string(duk, -2, DUK_SLOT_CALLBACK);
            duk_put_global_string(duk, name);
            // fprintf(stderr, "[%p] function [%s] => %p\n", duk, name, func);
            // sv_dump(func);
        }
    }

    RETVAL = 1;
  OUTPUT: RETVAL

SV*
eval(duk_context* duk, const char* js)
  PREINIT:
    SV* ret = 0;
  CODE:
    duk_eval_string(duk, js);
    ret = get_perl_value(aTHX_ duk, -1);
    RETVAL = ret;

  OUTPUT: RETVAL
