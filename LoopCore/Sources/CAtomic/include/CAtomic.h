#ifndef CATOMIC_H
#define CATOMIC_H

#include <stdint.h>

/// Atomic render-state pointer + render-callback epoch counter.
typedef struct CAtomicSlot CAtomicSlot;

CAtomicSlot *_Nonnull catomic_slot_create(void);
void catomic_slot_destroy(CAtomicSlot *_Nonnull slot);

void *_Nullable catomic_load(CAtomicSlot *_Nonnull slot);                               // acquire
void *_Nullable catomic_exchange(CAtomicSlot *_Nonnull slot, void *_Nullable state);   // acq_rel
void catomic_epoch_increment(CAtomicSlot *_Nonnull slot);                               // release
uint64_t catomic_epoch_load(CAtomicSlot *_Nonnull slot);                                // acquire

#endif
