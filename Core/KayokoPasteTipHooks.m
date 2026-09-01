//
//  KayokoPasteTipHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>

#import "KayokoCore.h"
#import "KayokoCoreRuntime.h"

CHDeclareClass(DRPasteAnnouncer);

@interface DRPasteAnnouncer : NSObject
@end

CHOptimizedMethod0(self, void, DRPasteAnnouncer, announceDeniedPaste) {
    if ([[KayokoCoreRuntime sharedRuntime] pasteTipsDisabled]) {
        return;
    }
    CHSuper0(DRPasteAnnouncer, announceDeniedPaste);
}

CHOptimizedMethod1(self, void, DRPasteAnnouncer, announcePaste, id, arg1) {
    if ([[KayokoCoreRuntime sharedRuntime] pasteTipsDisabled]) {
        return;
    }
    CHSuper1(DRPasteAnnouncer, announcePaste, arg1);
}

@implementation KayokoPasteTipHookInstaller

+ (void)installHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      CHLoadClass_(&DRPasteAnnouncer$, NSClassFromString(@"DRPasteAnnouncer"));
      CHHook0(DRPasteAnnouncer, announceDeniedPaste);
      CHHook1(DRPasteAnnouncer, announcePaste);
    });
}

@end
