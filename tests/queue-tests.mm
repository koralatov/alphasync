#import "../AlphaSync/Application/ASDeviceController.h"
#include <cstdio>
#include <cstdlib>
#define CHECK(value) do { if (!(value)) { std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #value); std::abort(); } } while (false)

// These seams belong to the test only.  Inject a device tree without enabling IOKit
// or opening a USB device, then exercise the same public scheduler as the interface.
@interface ASNode (TestConstruction)
- (id)initForDisplay;
@end
@interface ASDeviceController (TestDisconnect)
- (void)deviceDisconnected:(ts::ASDevice*)device;
@end
@interface TestDeviceNode : ASDeviceNode
- (id)initWithTestDevice:(ts::ASDevice*)value;
@end
@implementation TestDeviceNode
- (id)initWithTestDevice:(ts::ASDevice*)value
{
    if ((self = [super initForDisplay]))
    {
        device = value;
        [self setConnectionID:1];
        [self setDisplayName:@"Test Neo"];
    }
    return self;
}
@end

class TestDevice : public ts::ASDevice
{
    bool read(void*, unsigned, unsigned*, unsigned) override { std::abort(); }
    bool write(const void*, unsigned, unsigned) override { std::abort(); }
};

static void pumpUntil(BOOL (^condition)(void))
{
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    CHECK(condition());
}

int main()
{
    @autoreleasepool
    {
        TestDevice device;
        ASNode* sorted = [[[ASNode alloc] init] autorelease];
        for (NSString* name in @[@"File 10", @"File 2", @"File 1"])
        {
            ASNode* child = [[[ASNode alloc] init] autorelease];
            [child setDisplayName:name];
            [sorted addChild:child];
        }
        [sorted sortChildren];
        CHECK([[[sorted children] valueForKey:@"displayName"] isEqual:@[@"File 1", @"File 2", @"File 10"]]);
        ts::ASDevice* testDevice = &device;
        ASDeviceController* controller = [[ASDeviceController alloc] init];
        dispatch_queue_t queue = (dispatch_queue_t)[controller valueForKey:@"deviceQueue"];
        NSMutableDictionary* nodes = [controller valueForKey:@"workerNodes"];
        TestDeviceNode* worker = [[TestDeviceNode alloc] initWithTestDevice:&device];
        ASDeviceNode* display = (ASDeviceNode*)[worker copyForDisplay];
        [[controller systemRoot] addChild:display];
        dispatch_sync(queue, ^{ nodes[@1] = worker; [worker setDisplayName:@"Changed on worker"]; });
        CHECK([[display displayName] isEqualToString:@"Test Neo"]);
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        dispatch_semaphore_t proceed = dispatch_semaphore_create(0);
        __block NSUInteger completed = 0;
        __block unsigned order = 0;
        [controller performTaskForNode:display refresh:NO task:^id(ASNode* node) {
            CHECK(![NSThread isMainThread] && node != display && ++order == 1);
            dispatch_semaphore_signal(entered);
            CHECK(dispatch_semaphore_wait(proceed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
            return @YES;
        } completion:^(id result, NSString* error) {
            CHECK([NSThread isMainThread] && [result boolValue] && !error);
            ++completed;
        }];
        [controller performTaskForNode:display refresh:NO task:^id(ASNode* node) {
            (void)node; CHECK(![NSThread isMainThread] && ++order == 2); return @YES;
        } completion:^(id result, NSString* error) {
            CHECK([NSThread isMainThread] && [result boolValue] && !error); ++completed;
        }];
        CHECK(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
        __block BOOL heartbeat = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ heartbeat = YES; });
        pumpUntil(^BOOL { return heartbeat; });
        CHECK(completed == 0 && [controller isBusy]);
        dispatch_semaphore_signal(proceed);
        pumpUntil(^BOOL { return completed == 2; });
        CHECK(order == 2 && ![controller isBusy]);

        // Disconnect between two queued requests.  The later request must never touch
        // the old device, even though its display copy is still retained by the caller.
        __block BOOL staleTaskExecuted = NO;
        [controller performTaskForNode:display refresh:NO task:^id(ASNode* node) {
            (void)node; dispatch_semaphore_signal(entered);
            CHECK(dispatch_semaphore_wait(proceed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
            return @YES;
        } completion:^(id result, NSString* error) { (void)result; CHECK(!error); ++completed; }];
        CHECK(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
        dispatch_async(queue, ^{ [controller deviceDisconnected:testDevice]; });
        [controller performTaskForNode:display refresh:NO task:^id(ASNode* node) {
            (void)node; staleTaskExecuted = YES; return @YES;
        } completion:^(id result, NSString* error) { CHECK(!result && error); ++completed; }];
        dispatch_semaphore_signal(proceed);
        pumpUntil(^BOOL { return completed == 4; });
        CHECK(!staleTaskExecuted && [[controller systemRoot] numberOfChildren] == 0);
        __block BOOL stopped = NO;
        [controller shutdownWithCompletion:^{ CHECK([NSThread isMainThread]); stopped = YES; }];
        pumpUntil(^BOOL { return stopped; });
        dispatch_release(entered);
        dispatch_release(proceed);
        [display release]; [worker release]; [controller release];
        std::puts("All serial device queue checks passed.");
    }
}
