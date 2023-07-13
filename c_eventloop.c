/*
 *  Timer insertion is an O(n) operation; in a real world eventloop based on a
 *  heap insertion would be O(log N).
 */
#include <stdio.h>

#if defined(_WIN32)
#include <WinSock2.h>
#define poll WSAPoll
#pragma comment(lib, "ws2_32")
#else
#include <poll.h>
#endif

#include "duktape.h"
#include "c_eventloop.h"
#include "pl_util.h"

#if !defined(DUKTAPE_EVENTLOOP_DEBUG)
#define DUKTAPE_EVENTLOOP_DEBUG 0       /* set to 1 to debug with printf */
#endif

#define  TIMERS_SLOT_NAME       "eventTimers"
#define  MIN_DELAY              1.0
#define  MIN_WAIT               1.0
#define  MAX_WAIT               60000.0
#define  MAX_EXPIRIES           10
#define  MAX_TIMERS             4096     /* this is quite excessive for embedded use, but good for testing */

typedef struct {
    int64_t id;       /* numeric ID (returned from e.g. setTimeout); zero if unused */
    double target;    /* next target time */
    double delay;     /* delay/interval */
    int oneshot;      /* oneshot=1 (setTimeout), repeated=0 (setInterval) */
    int removed;      /* timer has been requested for removal */

    /* The callback associated with the timer is held in the "global stash",
     * in <stash>.eventTimers[String(id)].  The references must be deleted
     * when a timer struct is deleted.
     */
} ev_timer;

/* Active timers.  Dense list, terminates to end of list or first unused timer.
 * The list is sorted by 'target', with lowest 'target' (earliest expiry) last
 * in the list.  When a timer's callback is being called, the timer is moved
 * to 'timer_expiring' as it needs special handling should the user callback
 * delete that particular timer.
 */
static ev_timer timer_list[MAX_TIMERS];
static ev_timer timer_expiring;
static int timer_count;  /* last timer at timer_count - 1 */
static int64_t timer_next_id = 1;

static ev_timer *find_nearest_timer(void) {
    /* Last timer expires first (list is always kept sorted). */
    if (timer_count <= 0) {
        return NULL;
    }
    return timer_list + timer_count - 1;
}

/* Bubble last timer on timer list backwards until it has been moved to
 * its proper sorted position (based on 'target' time).
 */
static void bubble_last_timer(void) {
    int i;
    int n = timer_count;
    ev_timer *t;
    ev_timer tmp;

    for (i = n - 1; i > 0; i--) {
        /* Timer to bubble is at index i, timer to compare to is
         * at i-1 (both guaranteed to exist).
         */
        t = timer_list + i;
        if (t->target <= (t-1)->target) {
            /* 't' expires earlier than (or same time as) 't-1', so we're done. */
            break;
        } else {
            /* 't' expires later than 't-1', so swap them and repeat. */
            memcpy((void *) &tmp, (void *) (t - 1), sizeof(ev_timer));
            memcpy((void *) (t - 1), (void *) t, sizeof(ev_timer));
            memcpy((void *) t, (void *) &tmp, sizeof(ev_timer));
        }
    }
}

static void expire_timers(duk_context *ctx) {
    ev_timer *t;
    int sanity = MAX_EXPIRIES;
    double now;
    int rc;

    /* Because a user callback can mutate the timer list (by adding or deleting
     * a timer), we expire one timer and then rescan from the end again.  There
     * is a sanity limit on how many times we do this per expiry round.
     */

    duk_push_global_stash(ctx);
    duk_get_prop_string(ctx, -1, TIMERS_SLOT_NAME);
    /* [ ... stash eventTimers ] */

    now = now_us() / 1000.0;
    while (sanity-- > 0) {
        /*
         *  Expired timer(s) still exist?
         */
        if (timer_count <= 0) {
            break;
        }
        t = timer_list + timer_count - 1;
        if (t->target > now) {
            break;
        }

        /*
         *  Move the timer to 'expiring' for the duration of the callback.
         *  Mark a one-shot timer deleted, compute a new target for an interval.
         */
        memcpy((void *) &timer_expiring, (void *) t, sizeof(ev_timer));
        memset((void *) t, 0, sizeof(ev_timer));
        timer_count--;
        t = &timer_expiring;

        if (t->oneshot) {
            t->removed = 1;
        } else {
            t->target = now + t->delay;  /* XXX: or t->target + t->delay? */
        }

        /*
         *  Call timer callback.  The callback can operate on the timer list:
         *  add new timers, remove timers.  The callback can even remove the
         *  expired timer whose callback we're calling.  However, because the
         *  timer being expired has been moved to 'timer_expiring', we don't
         *  need to worry about the timer's offset changing on the timer list.
         */
#if DUKTAPE_EVENTLOOP_DEBUG > 0
        fprintf(stderr, "calling user callback for timer id %d\n", (int) t->id);
        fflush(stderr);
#endif

        duk_push_number(ctx, (double) t->id);
        duk_get_prop(ctx, -2);  /* -> [ ... stash eventTimers func ] */
        rc = duk_pcall(ctx, 0 /*nargs*/);  /* -> [ ... stash eventTimers retval ] */
        check_duktape_call_for_errors(rc, ctx);
        duk_pop(ctx);    /* [ ... stash eventTimers ] */

        if (t->removed) {
            /* One-shot timer (always removed) or removed by user callback. */
#if DUKTAPE_EVENTLOOP_DEBUG > 0
            fprintf(stderr, "deleting callback state for timer %d\n", (int) t->id);
            fflush(stderr);
#endif
            duk_push_number(ctx, (double) t->id);
            duk_del_prop(ctx, -2);
        } else {
            /* Interval timer, not removed by user callback.  Queue back to
             * timer list and bubble to its final sorted position.
             */
#if DUKTAPE_EVENTLOOP_DEBUG > 0
            fprintf(stderr, "queueing timer %d back into active list\n", (int) t->id);
            fflush(stderr);
#endif
            if (timer_count >= MAX_TIMERS) {
                (void) duk_error(ctx, DUK_ERR_RANGE_ERROR, "out of timer slots");
            }
            memcpy((void *) (timer_list + timer_count), (void *) t, sizeof(ev_timer));
            timer_count++;
            bubble_last_timer();
        }
    }

    memset((void *) &timer_expiring, 0, sizeof(ev_timer));

    duk_pop_2(ctx);  /* -> [ ... ] */
}

duk_ret_t eventloop_run(duk_context *ctx, void *udata) {
    ev_timer *t;
    double now;
    double diff;
    int timeout;
    int rc;

    (void) udata;
    for (;;) {
        /*
         *  Expire timers.
         */
        expire_timers(ctx);

        /*
         *  Determine poll() timeout (as close to poll() as possible as
         *  the wait is relative).
         */
        now = now_us() / 1000.0;
        t = find_nearest_timer();
        if (t) {
            diff = t->target - now;
            if (diff < MIN_WAIT) {
                diff = MIN_WAIT;
            } else if (diff > MAX_WAIT) {
                diff = MAX_WAIT;
            }
            timeout = (int) diff;  /* clamping ensures that fits */
        } else {
#if DUKTAPE_EVENTLOOP_DEBUG > 0
            fprintf(stderr, "no timers to poll, exiting\n");
            fflush(stderr);
#endif
            break;
        }

        /*
         *  Poll for timeout.
         */
#if DUKTAPE_EVENTLOOP_DEBUG > 0
        fprintf(stderr, "going to poll, timeout %d ms\n", timeout);
        fflush(stderr);
#endif
        rc = poll(0, 0, timeout);
#if DUKTAPE_EVENTLOOP_DEBUG > 0
        fprintf(stderr, "poll rc: %d\n", rc);
        fflush(stderr);
#endif
        if (rc < 0) {
            /* error */
        } else if (rc == 0) {
            /* timeout */
        } else {
            /* 'rc' fds active  -- huh?*/
        }
    }

    return 0;
}

static int create_timer(duk_context *ctx) {
    double delay;
    int oneshot;
    int idx;
    int64_t timer_id;
    double now;
    ev_timer *t;

    now = now_us() / 1000.0;

    /* indexes:
     *   0 = function (callback)
     *   1 = delay
     *   2 = boolean: oneshot
     */
    delay = duk_require_number(ctx, 1);
    if (delay < MIN_DELAY) {
        delay = MIN_DELAY;
    }
    oneshot = duk_require_boolean(ctx, 2);

    if (timer_count >= MAX_TIMERS) {
        (void) duk_error(ctx, DUK_ERR_RANGE_ERROR, "out of timer slots");
    }
    idx = timer_count++;
    timer_id = timer_next_id++;
    t = timer_list + idx;

    memset((void *) t, 0, sizeof(ev_timer));
    t->id = timer_id;
    t->target = now + delay;
    t->delay = delay;
    t->oneshot = oneshot;
    t->removed = 0;

    /* Timer is now at the last position; use swaps to "bubble" it to its
     * correct sorted position.
     */
    bubble_last_timer();

    /* Finally, register the callback to the global stash 'eventTimers' object. */
    duk_push_global_stash(ctx);
    duk_get_prop_string(ctx, -1, TIMERS_SLOT_NAME);  /* -> [ func delay oneshot stash eventTimers ] */
    duk_push_number(ctx, (double) timer_id);
    duk_dup(ctx, 0);
    duk_put_prop(ctx, -3);  /* eventTimers[timer_id] = callback */

    /* Return timer id. */
    duk_push_number(ctx, (double) timer_id);
#if DUKTAPE_EVENTLOOP_DEBUG > 0
    fprintf(stderr, "created timer id: %d\n", (int) timer_id);
    fflush(stderr);
#endif
    return 1;
}

static int delete_timer(duk_context *ctx) {
    int i, n;
    int64_t timer_id;
    ev_timer *t;
    int found = 0;

    /* indexes:
     *   0 = timer id
     */
    timer_id = (int64_t) duk_require_number(ctx, 0);

    /*
     *  Unlike insertion, deletion needs a full scan of the timer list
     *  and an expensive remove.  If no match is found, nothing is deleted.
     *  Caller gets a boolean return code indicating match.
     *
     *  When a timer is being expired and its user callback is running,
     *  the timer has been moved to 'timer_expiring' and its deletion
     *  needs special handling: just mark it to-be-deleted and let the
     *  expiry code remove it.
     */

    t = &timer_expiring;
    if (t->id == timer_id) {
        t->removed = 1;
        duk_push_true(ctx);
#if DUKTAPE_EVENTLOOP_DEBUG > 0
        fprintf(stderr, "deleted expiring timer id: %d\n", (int) timer_id);
        fflush(stderr);
#endif
        return 1;
    }

    n = timer_count;
    for (i = 0; i < n; i++) {
        t = timer_list + i;
        if (t->id == timer_id) {
            found = 1;

            /* Shift elements downwards to keep the timer list dense
             * (no need if last element).
             */
            if (i < timer_count - 1) {
                memmove((void *) t, (void *) (t + 1), (timer_count - i - 1) * sizeof(ev_timer));
            }

            /* Zero last element for clarity. */
            memset((void *) (timer_list + n - 1), 0, sizeof(ev_timer));

            /* Update timer_count. */
            timer_count--;

            /* The C state is now up-to-date, but we still need to delete
             * the timer callback state from the global 'stash'.
             */
            duk_push_global_stash(ctx);
            duk_get_prop_string(ctx, -1, TIMERS_SLOT_NAME);  /* -> [ timer_id stash eventTimers ] */
            duk_push_number(ctx, (double) timer_id);
            duk_del_prop(ctx, -2);  /* delete eventTimers[timer_id] */

#if DUKTAPE_EVENTLOOP_DEBUG > 0
            fprintf(stderr, "deleted timer id: %d\n", (int) timer_id);
            fflush(stderr);
#endif
            break;
        }
    }

#if DUKTAPE_EVENTLOOP_DEBUG > 0
    if (!found) {
        fprintf(stderr, "trying to delete timer id %d, but not found; ignoring\n", (int) timer_id);
        fflush(stderr);
    }
#endif

    duk_push_boolean(ctx, found);
    return 1;
}

static duk_function_list_entry eventloop_funcs[] = {
    { "createTimer", create_timer, 3 },
    { "deleteTimer", delete_timer, 1 },
    { NULL, NULL, 0 }
};

void eventloop_register(duk_context *ctx) {
    memset((void *) timer_list, 0, MAX_TIMERS * sizeof(ev_timer));
    memset((void *) &timer_expiring, 0, sizeof(ev_timer));

    /* Set global 'EventLoop'. */
    duk_push_global_object(ctx);
    duk_push_object(ctx);
    duk_put_function_list(ctx, -1, eventloop_funcs);
    duk_put_prop_string(ctx, -2, "EventLoop");
    duk_pop(ctx);

    /* Initialize global stash 'eventTimers'. */
    duk_push_global_stash(ctx);
    duk_push_object(ctx);
    duk_put_prop_string(ctx, -2, TIMERS_SLOT_NAME);
    duk_pop(ctx);
}
