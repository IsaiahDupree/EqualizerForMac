#import <Foundation/Foundation.h>
#import "LocalLink.h"
#include <math.h>
#include <stdio.h>
#include <unistd.h>

static BOOL exercise(MDPLinkSender *sender, MDPLinkReceiver *receiver,
                     float left, float right, float expectedLeft, float expectedRight) {
    float input[480 * 2], output[480 * 2];
    for (int i = 0; i < 480; ++i) {
        input[i * 2] = left;
        input[i * 2 + 1] = right;
    }
    uint32_t checked = 0;
    BOOL valid = YES;
    for (int round = 0; round < 200 && checked < 960; ++round) {
        [sender pushInterleaved:input frames:480 channels:2];
        usleep(10000);
        uint32_t received = [receiver readInterleaved:output frames:480];
        for (uint32_t i = 0; i < received; ++i) {
            if (fabsf(output[i * 2] - expectedLeft) > 0.00001f ||
                fabsf(output[i * 2 + 1] - expectedRight) > 0.00001f) valid = NO;
        }
        checked += received;
    }
    return valid && checked >= 960;
}

int main(void) {
    @autoreleasepool {
        MDPLinkReceiver *receiver = MDPLinkReceiver.shared;
        MDPLinkSender *sender = MDPLinkSender.shared;
        if (![receiver start]) {
            fprintf(stderr, "Could not bind the route-lab loopback port\n");
            return 1;
        }
        [sender start];
        BOOL valid = exercise(sender, receiver, 0.25f, -0.25f, 0.25f, -0.25f);
        [sender stop];
        for (int i = 0; i < 100 && receiver.hasPeer; ++i) usleep(10000);
        if (receiver.hasPeer) valid = NO;
        float silence[4] = { 1, 1, 1, 1 };
        uint64_t before = receiver.underrunFrames;
        if ([receiver readInterleaved:silence frames:2] != 0 || silence[0] != 0 ||
            silence[1] != 0 || silence[2] != 0 || silence[3] != 0 ||
            receiver.underrunFrames < before + 2) valid = NO;
        [sender start];
        if (!exercise(sender, receiver, NAN, INFINITY, 0, 0)) valid = NO;

        // Keep the receiver unconsumed until its bounded queue drops frames.
        float block[480 * 2] = { 0 };
        for (int i = 0; i < 40; ++i) {
            [sender pushInterleaved:block frames:480 channels:2];
            usleep(10000);
        }
        if (receiver.droppedFrames == 0) valid = NO;

        // One oversized write must drop at least the excess over ring capacity.
        float oversized[16384 * 2] = { 0 };
        [sender pushInterleaved:oversized frames:16384 channels:2];
        if (sender.droppedFrames < 8192) valid = NO;

        // The receiver can disappear while the sender still has samples queued.
        // An unhandled SIGPIPE would terminate this process here.
        [receiver stop];
        for (int i = 0; i < 100 && sender.connected; ++i) {
            [sender pushInterleaved:block frames:480 channels:2];
            usleep(10000);
        }
        if (sender.connected) valid = NO;
        [sender stop];
        if (!valid) {
            fprintf(stderr, "Loopback, reconnection, sanitization or overflow check failed\n");
            return 1;
        }
        puts("PASS: localhost stereo, reconnect, sanitization, underrun, overflow and receiver loss");
        return 0;
    }
}
