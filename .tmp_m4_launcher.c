#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *task;
@end

@implementation AppDelegate
- (NSString *)runPath {
    NSString *resPath = [[NSBundle mainBundle] resourcePath];
    return [resPath stringByAppendingPathComponent:@"run.sh"];
}

- (void)startServer {
    if (self.task && self.task.isRunning) return;
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[[self runPath]];
    [task launch];
    self.task = task;
}

- (void)openBrowser {
    NSURL *url = [NSURL URLWithString:@"http://localhost:8000/login"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self startServer];
    [self openBrowser];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self openBrowser];
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.task && self.task.isRunning) {
        [self.task terminate];
    }
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
