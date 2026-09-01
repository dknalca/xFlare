/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_rt.h"

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>

/* ns -> unidades de mach_absolute_time */
static double xf_rt_ticks_per_ns(void) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    /* mach_absolute_time() * (numer/denom) = ns  =>  ns * (denom/numer) = ticks */
    return (double)tb.denom / (double)tb.numer;
}

bool xf_rt_time_constraint_params(double sample_rate, uint32_t buffer_frames,
                                  uint32_t *period, uint32_t *computation,
                                  uint32_t *constraint) {
    if (sample_rate <= 0.0 || buffer_frames == 0) return false;

    double period_ns = (double)buffer_frames / sample_rate * 1e9;
    double tpns = xf_rt_ticks_per_ns();

    uint32_t p = (uint32_t)(period_ns * tpns);
    if (p == 0) p = 1;
    uint32_t comp = (uint32_t)(p * 0.5);
    uint32_t cons = (uint32_t)(p * 0.9);
    if (comp == 0) comp = 1;
    if (cons < comp) cons = comp;

    if (period)      *period = p;
    if (computation) *computation = comp;
    if (constraint)  *constraint = cons;
    return true;
}

bool xf_rt_promote_current_thread(double sample_rate, uint32_t buffer_frames) {
    uint32_t period = 0, computation = 0, constraint = 0;
    if (!xf_rt_time_constraint_params(sample_rate, buffer_frames,
                                      &period, &computation, &constraint)) {
        return false;
    }

    thread_time_constraint_policy_data_t policy;
    policy.period      = period;
    policy.computation = computation;
    policy.constraint  = constraint;
    policy.preemptible = 0;   /* el hilo de audio no debe ceder la CPU a mitad */

    kern_return_t kr = thread_policy_set(
        mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY,
        (thread_policy_t)&policy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);

    return kr == KERN_SUCCESS;
}
