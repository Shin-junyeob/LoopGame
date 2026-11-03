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
