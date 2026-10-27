// The render handoff stays ordered through overflow, index wrap and a concurrent drain.
#define SG_DRIVER 1
#include "../../tweak/Sources/Shared/Lossless/SGAnchorRing.h"
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <sched.h>

static SGAnchorRing ring;
enum { count = 200000 };
static void *produce(void *unused) {
    for (unsigned i = 0; i < count; ++i) {
        SGAnchorSample sample = {.epoch = i, .sourceFrame = i * 1024., .frames = 1024};
        while (!SGAnchorPush(&ring, sample)) sched_yield();
    }
    return NULL;
}
int main(void) {
    SGAnchorSample sample;
    assert(!SGAnchorPop(&ring, &sample));
    atomic_store(&ring.read, UINT_MAX - 100);
    atomic_store(&ring.write, UINT_MAX - 100);
    for (unsigned i = 0; i < kSGAnchorCapacity; ++i)
        assert(SGAnchorPush(&ring, (SGAnchorSample){.epoch = i}));
    assert(!SGAnchorPush(&ring, (SGAnchorSample){0}));
    assert(atomic_load(&ring.dropped) == 1);
    for (unsigned i = 0; i < kSGAnchorCapacity; ++i) {
        assert(SGAnchorPop(&ring, &sample));
        assert(sample.epoch == i);
    }
    assert(!SGAnchorPop(&ring, &sample));
    pthread_t producer;
    assert(!pthread_create(&producer, NULL, produce, NULL));
    for (unsigned i = 0; i < count; ++i) {
        while (!SGAnchorPop(&ring, &sample)) sched_yield();
        assert(sample.epoch == i && sample.sourceFrame == i * 1024. && sample.frames == 1024);
    }
    assert(!pthread_join(producer, NULL));
    assert(!SGAnchorPop(&ring, &sample));
    puts("ANCHOR RING PASS");
}
