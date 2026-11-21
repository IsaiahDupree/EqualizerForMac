#import <Foundation/Foundation.h>
#import "LocalLink.h"
#include <math.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    @autoreleasepool {
        MDPLinkReceiver *receiver = MDPLinkReceiver.shared;
        MDPLinkSender *sender = MDPLinkSender.shared;
        if (![receiver start]) {
            fprintf(stderr, "Could not bind the route-lab loopback port\n");
            return 1;
        }
        [sender start];
        float input[480 * 2];
        float output[480 * 2];
        for (int i = 0; i < 480; ++i) {
            input[i * 2] = 0.25f;
            input[i * 2 + 1] = -0.25f;
        }
        uint32_t checked = 0;
        BOOL valid = YES;
        for (int round = 0; round < 200 && checked < 960; ++round) {
            [sender pushInterleaved:input frames:480 channels:2];
            usleep(10000);
            uint32_t received = [receiver readInterleaved:output frames:480];
            for (uint32_t i = 0; i < received; ++i) {
                if (fabsf(output[i * 2] - 0.25f) > 0.00001f ||
                    fabsf(output[i * 2 + 1] + 0.25f) > 0.00001f) valid = NO;
            }
            checked += received;
        }
        [sender stop];
        [receiver stop];
        if (!valid || checked < 960) {
            fprintf(stderr, "Loopback samples were corrupted or missing (received %u frames)\n", checked);
            return 1;
        }
        printf("PASS: %u stereo frames crossed the real localhost link intact\n", checked);
        return 0;
    }
}
