#include "CAtomic.h"
#include <stdatomic.h>
#include <stdlib.h>

struct CAtomicSlot {
    _Atomic(void *) state;
    _Atomic(uint64_t) epoch;
};

CAtomicSlot *catomic_slot_create(void) {
    CAtomicSlot *slot = malloc(sizeof *slot);
    atomic_init(&slot->state, NULL);
    atomic_init(&slot->epoch, 0);
    return slot;
}

void catomic_slot_destroy(CAtomicSlot *slot) { free(slot); }

void *catomic_load(CAtomicSlot *slot) {
    return atomic_load_explicit(&slot->state, memory_order_acquire);
}

void *catomic_exchange(CAtomicSlot *slot, void *state) {
    return atomic_exchange_explicit(&slot->state, state, memory_order_acq_rel);
}

void catomic_epoch_increment(CAtomicSlot *slot) {
    atomic_fetch_add_explicit(&slot->epoch, 1, memory_order_release);
}

uint64_t catomic_epoch_load(CAtomicSlot *slot) {
    return atomic_load_explicit(&slot->epoch, memory_order_acquire);
}

uint64_t catomic_next_generation(void) {
    static _Atomic(uint64_t) counter = 0;
    return atomic_fetch_add_explicit(&counter, 1, memory_order_relaxed) + 1;
}

#define CLIVE_CAP 256
#define CLIVE_RESULTS 1024

struct CLiveQueue {
    _Atomic(uint64_t) head, tail;
    uint64_t buf[CLIVE_CAP];
    _Atomic(uint64_t) resultTag[CLIVE_RESULTS];  // id + 1 once done
    _Atomic(int64_t) resultFrame[CLIVE_RESULTS];
};

CLiveQueue *catomic_live_create(void) { return calloc(1, sizeof(CLiveQueue)); }
void catomic_live_destroy(CLiveQueue *q) { free(q); }

bool catomic_live_push(CLiveQueue *q, uint64_t event) {
    uint64_t t = atomic_load_explicit(&q->tail, memory_order_relaxed);
    if (t - atomic_load_explicit(&q->head, memory_order_acquire) == CLIVE_CAP) return false;
    q->buf[t % CLIVE_CAP] = event;
    atomic_store_explicit(&q->tail, t + 1, memory_order_release);
    return true;
}

bool catomic_live_pop(CLiveQueue *q, uint64_t *event) {
    uint64_t h = atomic_load_explicit(&q->head, memory_order_relaxed);
    if (h == atomic_load_explicit(&q->tail, memory_order_acquire)) return false;
    *event = q->buf[h % CLIVE_CAP];
    atomic_store_explicit(&q->head, h + 1, memory_order_release);
    return true;
}

void catomic_live_done(CLiveQueue *q, uint64_t id, int64_t frame) {
    atomic_store_explicit(&q->resultFrame[id % CLIVE_RESULTS], frame, memory_order_relaxed);
    atomic_store_explicit(&q->resultTag[id % CLIVE_RESULTS], id + 1, memory_order_release);
}

int64_t catomic_live_result(CLiveQueue *q, uint64_t id) {
    if (atomic_load_explicit(&q->resultTag[id % CLIVE_RESULTS], memory_order_acquire) != id + 1) return -1;
    return atomic_load_explicit(&q->resultFrame[id % CLIVE_RESULTS], memory_order_relaxed);
}

struct CRecord {
    _Atomic(uint64_t) seq;
    _Atomic(uint64_t) v[CRECORD_N];
};

CRecord *catomic_record_create(void) { return calloc(1, sizeof(CRecord)); }

void catomic_record_write(CRecord *r, const uint64_t *values) {
    uint64_t s = atomic_load_explicit(&r->seq, memory_order_relaxed);
    atomic_store_explicit(&r->seq, s + 1, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
    for (int i = 0; i < CRECORD_N; i++) atomic_store_explicit(&r->v[i], values[i], memory_order_relaxed);
    atomic_store_explicit(&r->seq, s + 2, memory_order_release);
}

void catomic_record_read(CRecord *r, uint64_t *out) {
    for (;;) {
        uint64_t s1 = atomic_load_explicit(&r->seq, memory_order_acquire);
        if (s1 & 1) continue;
        for (int i = 0; i < CRECORD_N; i++) out[i] = atomic_load_explicit(&r->v[i], memory_order_relaxed);
        atomic_thread_fence(memory_order_acquire);
        if (atomic_load_explicit(&r->seq, memory_order_relaxed) == s1) return;
    }
}
