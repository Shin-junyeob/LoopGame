#ifndef CATOMIC_H
#define CATOMIC_H

#include <stdbool.h>
#include <stdint.h>

/// Atomic render-state pointer + render-callback epoch counter.
typedef struct CAtomicSlot CAtomicSlot;

CAtomicSlot *_Nonnull catomic_slot_create(void);
void catomic_slot_destroy(CAtomicSlot *_Nonnull slot);

void *_Nullable catomic_load(CAtomicSlot *_Nonnull slot);                               // acquire
void *_Nullable catomic_exchange(CAtomicSlot *_Nonnull slot, void *_Nullable state);   // acq_rel
void catomic_epoch_increment(CAtomicSlot *_Nonnull slot);                               // release
uint64_t catomic_epoch_load(CAtomicSlot *_Nonnull slot);                                // acquire

/// SPSC live-hit queue: main pushes `id << 8 | pad`, render pops at callback start and reports the
/// frame it voiced the hit at via catomic_live_done; main polls catomic_live_result (-1 = pending).
typedef struct CLiveQueue CLiveQueue;

CLiveQueue *_Nonnull catomic_live_create(void);
void catomic_live_destroy(CLiveQueue *_Nonnull q);
bool catomic_live_push(CLiveQueue *_Nonnull q, uint64_t event);                          // main
bool catomic_live_pop(CLiveQueue *_Nonnull q, uint64_t *_Nonnull event);                 // render
void catomic_live_done(CLiveQueue *_Nonnull q, uint64_t id, int64_t frame);              // render
int64_t catomic_live_result(CLiveQueue *_Nonnull q, uint64_t id);                        // main

/// Seqlock record of CRECORD_N u64 values: one writer (render), torn-free reads (main).
#define CRECORD_N 8
typedef struct CRecord CRecord;

CRecord *_Nonnull catomic_record_create(void);
void catomic_record_write(CRecord *_Nonnull r, const uint64_t *_Nonnull values);
void catomic_record_read(CRecord *_Nonnull r, uint64_t *_Nonnull out);

#endif
