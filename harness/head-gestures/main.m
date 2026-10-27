// AirPods gestures' detector (Shared/HeadGestures/SGHeadDetector.m, as the tweak compiles it) over head
// motion made up to look like what AirPods report: 25 attitudes a second, pitch and yaw in radians, with a
// little noise on each. Every trace says what it should fire and the run fails on the first that does
// not; the negatives (walking, glancing, one nod, a slow turn) are the point as much as the gestures.
//
//     ./build.sh && build/head-gestures                 # the synthetic traces
//     build/head-gestures <trace.csv> [nod] [shake]     # a recording, one "time,pitch,yaw" a line
#import <Foundation/Foundation.h>
#import "Shared/HeadGestures/SGHeadDetector.h"

enum { kRate = 25, kMax = 25 * 60 };

typedef struct {
    double t[kMax], pitch[kMax], yaw[kMax];
    int count;
    double basePitch, baseYaw;   // where the head rests between moves
} Trace;

static unsigned sg_seed = 1;
static double noise(void) {
    sg_seed = sg_seed * 1103515245 + 12345;
    return ((sg_seed >> 8 & 0xffff) / 65535.0 - 0.5) * 0.006;   // +-0.003 rad
}

static void sample(Trace *trace, double dPitch, double dYaw) {
    int i = trace->count++;
    trace->t[i] = 100.0 + (double)i / kRate;
    trace->pitch[i] = trace->basePitch + dPitch + noise();
    trace->yaw[i] = remainder(trace->baseYaw + dYaw + noise(), 2 * M_PI);
}

static void hold(Trace *trace, double seconds) {
    for (int n = (int)(seconds * kRate); n > 0; n--) sample(trace, 0, 0);
}

// One nod: the head down by `depth` and back up over `length` seconds.
static void nod(Trace *trace, double depth, double length) {
    for (int n = 0, steps = (int)(length * kRate); n < steps; n++) {
        double s = sin(M_PI * n / steps);
        sample(trace, -depth * s * s, 0);
    }
}

// A shake: `swings` half cycles of the yaw at `hertz`, `width` either side.
static void shake(Trace *trace, double width, double hertz, double swings) {
    for (int n = 0, steps = (int)(swings / (2 * hertz) * kRate); n < steps; n++)
        sample(trace, 0, width * sin(2 * M_PI * hertz * n / kRate));
}

// The yaw moved from where it rests to `to` over `seconds`, smoothly, and left there.
static void turn(Trace *trace, double to, double seconds) {
    double from = 0;
    for (int n = 1, steps = (int)(seconds * kRate); n <= steps; n++) {
        double s = 0.5 - 0.5 * cos(M_PI * n / steps);
        sample(trace, 0, from + (to - from) * s);
    }
    trace->baseYaw += to;
}

static void walk(Trace *trace, double seconds) {
    for (int n = 0, steps = (int)(seconds * kRate); n < steps; n++) {
        double t = (double)n / kRate;
        sample(trace, 0.05 * sin(2 * M_PI * 2 * t), 0.03 * sin(2 * M_PI * 1 * t));
    }
}

// Running: the head bobs at the stride, near 3 Hz, by more than a walk and with a sway.
static void run(Trace *trace, double seconds) {
    for (int n = 0, steps = (int)(seconds * kRate); n < steps; n++) {
        double t = (double)n / kRate;
        sample(trace, 0.12 * sin(2 * M_PI * 2.8 * t), 0.08 * sin(2 * M_PI * 1.4 * t));
    }
}

static int replayTrace(const Trace *trace, double nodThreshold, double shakeThreshold, int *likes, int *skips) {
    SGHeadDetector detector;
    SGHeadDetectorReset(&detector, nodThreshold, shakeThreshold);
    *likes = *skips = 0;
    for (int i = 0; i < trace->count; i++) {
        SGHeadGesture gesture = SGHeadDetectorFeed(&detector, trace->t[i], trace->pitch[i], trace->yaw[i]);
        if (gesture == SGHeadGestureDoubleNod) ++*likes;
        if (gesture == SGHeadGestureShake) ++*skips;
    }
    return *likes + *skips;
}

static int failures;

static void expect(const char *name, const Trace *trace, double nod, double shake, int likes, int skips) {
    int gotLikes, gotSkips;
    replayTrace(trace, nod, shake, &gotLikes, &gotSkips);
    bool ok = gotLikes == likes && gotSkips == skips;
    if (!ok) failures++;
    printf("%-4s %-52s likes %d skips %d (want %d, %d)\n", ok ? "ok" : "FAIL", name, gotLikes, gotSkips, likes, skips);
}

static void nothingLearned(const char *name, const Trace *trace, SGHeadAxis axis) {
    double learned = SGHeadLearn(trace->t, trace->pitch, trace->yaw, trace->count, axis,
                                 axis == SGHeadAxisPitch ? SGHeadDefaultShake : SGHeadDefaultNod);
    bool ok = learned == 0;
    if (!ok) failures++;
    printf("%-4s %-52s %.2f (want 0)\n", ok ? "ok" : "FAIL", name, learned);
}

static void start(Trace *trace) {
    memset(trace, 0, sizeof *trace);
    trace->basePitch = 0.1;
    trace->baseYaw = 3.0;   // near +-pi, so a shake crosses the wrap
    hold(trace, 1);
}

static Trace *fresh(void) {
    static Trace trace;
    start(&trace);
    return &trace;
}

// What the teaching sheet learns from its five recordings: all of them but one at least must fire.
static double learnFive(Trace *const five[5], SGHeadAxis axis, double other) {
    SGHeadRecording recordings[5];
    for (int i = 0; i < 5; i++) recordings[i] = (SGHeadRecording){five[i]->t, five[i]->pitch, five[i]->yaw, five[i]->count};
    return SGHeadLearnSamples(recordings, 5, axis, other, 4);
}

static void inRange(const char *name, double threshold) {
    bool ok = threshold >= SGHeadMinThreshold && threshold <= SGHeadMaxThreshold;
    if (!ok) failures++;
    printf("%-4s %-52s %.2f (want %.1f to %.1f)\n", ok ? "ok" : "FAIL", name, threshold, SGHeadMinThreshold, SGHeadMaxThreshold);
}

static int replay(const char *path, double nod, double shake) {
    FILE *file = fopen(path, "r");
    if (!file) {
        fprintf(stderr, "cannot open %s\n", path);
        return 1;
    }
    SGHeadDetector detector;
    SGHeadDetectorReset(&detector, nod, shake);
    double t, pitch, yaw;
    while (fscanf(file, "%lf,%lf,%lf", &t, &pitch, &yaw) == 3) {
        SGHeadGesture gesture = SGHeadDetectorFeed(&detector, t, pitch, yaw);
        if (gesture) printf("%.2f %s\n", t, gesture == SGHeadGestureDoubleNod ? "double nod" : "shake");
    }
    fclose(file);
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1) return replay(argv[1], argc > 2 ? atof(argv[2]) : SGHeadDefaultNod, argc > 3 ? atof(argv[3]) : SGHeadDefaultShake);
    const double nodD = SGHeadDefaultNod, shakeD = SGHeadDefaultShake;
    Trace *t;

    // The gestures, at the defaults. A 20 degree nod in 0.4 s peaks at 2.7 rad/s; a 12 degree shake at
    // 2.5 Hz at 3.3.
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    expect("double nod", t, nodD, shakeD, 1, 0);
    t = fresh(); nod(t, 0.35, 0.4); hold(t, 0.1); nod(t, 0.35, 0.4); hold(t, 1);
    expect("double nod with a pause between", t, nodD, shakeD, 1, 0);
    t = fresh(); shake(t, 0.21, 2.5, 4); hold(t, 1);
    expect("shake, 4 swings across the wrap of the yaw", t, nodD, shakeD, 0, 1);
    t = fresh(); shake(t, 0.21, 2.5, 3); hold(t, 1);
    expect("shake, 3 swings", t, nodD, shakeD, 0, 1);
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 2); shake(t, 0.21, 2.5, 4); hold(t, 1);
    expect("double nod, then a shake 2 s later", t, nodD, shakeD, 1, 1);
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 0.5); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    expect("two double nods in a second: the cooldown", t, nodD, shakeD, 1, 0);

    // What must not fire.
    t = fresh(); nod(t, 0.35, 0.4); hold(t, 2);
    expect("one nod", t, nodD, shakeD, 0, 0);
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    expect("three nods", t, nodD, shakeD, 0, 0);
    t = fresh(); turn(t, -0.8, 0.6); hold(t, 0.6); turn(t, 1.6, 1.0); hold(t, 0.6); turn(t, -0.8, 0.6); hold(t, 1);
    expect("a glance left, then right, then back", t, nodD, shakeD, 0, 0);
    t = fresh(); turn(t, 1.2, 0.8); hold(t, 2);
    expect("one turn of the head", t, nodD, shakeD, 0, 0);
    t = fresh(); walk(t, 10); hold(t, 1);
    expect("walking, 10 s", t, nodD, shakeD, 0, 0);
    // A walk bobs the head under the thresholds, so a double nod on the move still counts; a run bobs it
    // over them, on and on, which is too long for a gesture.
    t = fresh(); walk(t, 3); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); walk(t, 3); hold(t, 1);
    expect("a double nod in the middle of a walk", t, nodD, shakeD, 1, 0);
    t = fresh(); run(t, 10); hold(t, 1);
    expect("running, 10 s", t, nodD, shakeD, 0, 0);
    t = fresh(); shake(t, 0.21, 2.5, 14); hold(t, 1);
    expect("shaking on and on (dancing)", t, nodD, shakeD, 0, 0);
    t = fresh(); nod(t, 0.35, 0.4); hold(t, 1.2); nod(t, 0.35, 0.4); hold(t, 1);
    expect("two nods 1.2 s apart", t, nodD, shakeD, 0, 0);
    // The headphones stop sending for a second between the nods: a gap starts over.
    t = fresh(); nod(t, 0.35, 0.4);
    for (int i = 0; i < t->count; i++) t->t[i] -= 1;
    nod(t, 0.35, 0.4); hold(t, 1);
    expect("a 1 s gap in the samples between the nods", t, nodD, shakeD, 0, 0);

    // Learning: one double nod and one shake of someone who moves small and slow.
    t = fresh(); nod(t, 0.17, 0.5); nod(t, 0.17, 0.5); hold(t, 1);
    double learnedNod = SGHeadLearn(t->t, t->pitch, t->yaw, t->count, SGHeadAxisPitch, shakeD);
    expect("a small slow double nod, at the default", t, nodD, shakeD, 0, 0);
    expect("the same, at what was learned from it", t, learnedNod, shakeD, 1, 0);
    t = fresh(); shake(t, 0.12, 2, 4); hold(t, 1);
    double learnedShake = SGHeadLearn(t->t, t->pitch, t->yaw, t->count, SGHeadAxisYaw, learnedNod);
    expect("a small slow shake, at what was learned from it", t, learnedNod, learnedShake, 0, 1);
    printf("     learned nod %.2f rad/s, shake %.2f rad/s\n", learnedNod, learnedShake);
    t = fresh(); walk(t, 10); hold(t, 1);
    expect("walking, at what was learned", t, learnedNod, learnedShake, 0, 0);
    nothingLearned("learning from a walk learns nothing", t, SGHeadAxisPitch);
    t = fresh(); nod(t, 0.35, 0.4); hold(t, 2);
    nothingLearned("learning from one nod learns nothing", t, SGHeadAxisPitch);
    // Enough swings, but more than a double nod has, or slower than one takes: the detector would never
    // fire on them, so nothing is learned rather than a threshold that says Learned and then does nothing.
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    nothingLearned("learning from three nods learns nothing", t, SGHeadAxisPitch);
    t = fresh(); nod(t, 0.35, 1.0); nod(t, 0.35, 1.0); hold(t, 1);
    nothingLearned("learning from a double nod of 2 s learns nothing", t, SGHeadAxisPitch);
    // A double nod whose settle bounces back hard: at the first margin the bounce counts as two more swings,
    // six in all, which is no double nod; a closer threshold leaves it out.
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); nod(t, 0.2, 0.3); hold(t, 1);
    double bounced = SGHeadLearn(t->t, t->pitch, t->yaw, t->count, SGHeadAxisPitch, shakeD);
    expect("a double nod with a hard settle, at 0.6 of its swings", t, 0.6 * 0.35 * M_PI / 0.4, shakeD, 0, 0);
    expect("the same, at what was learned from it", t, bounced, shakeD, 1, 0);
    printf("     learned %.2f rad/s from it\n", bounced);
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    expect("a plain double nod, at what was learned from the hard settle", t, bounced, shakeD, 1, 0);

    // Sensitivity divides the threshold: a nod half the size passes at 200% and not at 100%.
    t = fresh(); nod(t, 0.35, 0.4); nod(t, 0.35, 0.4); hold(t, 1);
    double fullNod = SGHeadLearn(t->t, t->pitch, t->yaw, t->count, SGHeadAxisPitch, shakeD);
    t = fresh(); nod(t, 0.17, 0.4); nod(t, 0.17, 0.4); hold(t, 1);
    expect("a half size double nod, sensitivity 100%", t, fullNod, shakeD, 0, 0);
    expect("a half size double nod, sensitivity 200%", t, fullNod / 2, shakeD, 1, 0);

    // Teaching: five recordings of a gesture, one each, the way the sheet takes them.
    Trace *five[5];
    for (int i = 0; i < 5; i++) five[i] = calloc(1, sizeof(Trace));
    const double depths[5] = {0.35, 0.28, 0.32, 0.30, 0.26}, lengths[5] = {0.4, 0.45, 0.4, 0.4, 0.45};
    for (int i = 0; i < 5; i++) {
        start(five[i]); nod(five[i], depths[i], lengths[i]); nod(five[i], depths[i], lengths[i]); hold(five[i], 0.8);
    }
    double taught = learnFive(five, SGHeadAxisPitch, shakeD);
    inRange("five double nods of different sizes teach", taught);
    // From the smallest of them, whose swings peak at 0.26 * pi / 0.45 = 1.8 rad/s, under it with room.
    bool fromSmallest = taught > SGHeadMinThreshold && taught < 0.26 * M_PI / 0.45;
    if (!fromSmallest) failures++;
    printf("%-4s %-52s %.2f (want over %.1f, under 1.8)\n", fromSmallest ? "ok" : "FAIL", "what they teach comes from the smallest", taught, SGHeadMinThreshold);
    for (int i = 0; i < 5; i++) {
        char name[64];
        snprintf(name, sizeof name, "taught from five, double nod %d (%.2f rad deep)", i + 1, depths[i]);
        expect(name, five[i], taught, shakeD, 1, 0);
    }
    printf("     taught nod %.2f rad/s\n", taught);
    t = fresh(); walk(t, 10); hold(t, 1);
    expect("walking, at what five double nods taught", t, taught, shakeD, 0, 0);
    // One of the five is three nods, no double nod at any threshold: four out of five still teach.
    start(five[2]); nod(five[2], 0.3, 0.4); nod(five[2], 0.3, 0.4); nod(five[2], 0.3, 0.4); hold(five[2], 0.8);
    taught = learnFive(five, SGHeadAxisPitch, shakeD);
    inRange("four double nods and three nods teach", taught);
    expect("taught from four of five, double nod 1", five[0], taught, shakeD, 1, 0);
    expect("taught from four of five, double nod 5", five[4], taught, shakeD, 1, 0);
    // Two of them three nods: only three out of five, nothing is taught.
    start(five[3]); nod(five[3], 0.3, 0.4); nod(five[3], 0.3, 0.4); nod(five[3], 0.3, 0.4); hold(five[3], 0.8);
    taught = learnFive(five, SGHeadAxisPitch, shakeD);
    bool none = taught == 0;
    if (!none) failures++;
    printf("%-4s %-52s %.2f (want 0)\n", none ? "ok" : "FAIL", "three double nods and two of three nods teach nothing", taught);
    // Five shakes, narrower and slower each time.
    const double widths[5] = {0.21, 0.18, 0.15, 0.12, 0.2}, hertz[5] = {2.5, 2.2, 2.0, 2.0, 2.4};
    for (int i = 0; i < 5; i++) { start(five[i]); shake(five[i], widths[i], hertz[i], 4); hold(five[i], 0.8); }
    double taughtShake = learnFive(five, SGHeadAxisYaw, nodD);
    inRange("five shakes of different sizes teach", taughtShake);
    for (int i = 0; i < 5; i++) {
        char name[64];
        snprintf(name, sizeof name, "taught from five, shake %d (%.2f rad wide)", i + 1, widths[i]);
        expect(name, five[i], nodD, taughtShake, 0, 1);
    }
    printf("     taught shake %.2f rad/s\n", taughtShake);
    for (int i = 0; i < 5; i++) free(five[i]);

    printf(failures ? "%d failed\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
