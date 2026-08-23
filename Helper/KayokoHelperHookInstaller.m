//
//  KayokoHelperHookInstaller.m
//  Kayoko
//

#import "KayokoHelperHookInstaller.h"
#import "KayokoPreferenceKeys.h"

@implementation KayokoHelperHookInstaller

+ (void)installActivationHooksWithActivationMethod:(NSUInteger)activationMethod {
    if (activationMethod & kActivationMethodSwipeUp) {
        [self installSwipeUpHooks];
    }
}

+ (void)installApplicationHooksWithActivationMethod:(NSUInteger)activationMethod {
    [self installActivationHooksWithActivationMethod:activationMethod];
}

+ (void)installSpringBoardActivationHooksWithActivationMethod:(NSUInteger)activationMethod {
    [self installActivationHooksWithActivationMethod:activationMethod];
}

+ (void)installKeyboardExtensionHooksWithActivationMethod:(NSUInteger)activationMethod
                                     spotlightSwipeUpOnly:(BOOL)spotlightSwipeUpOnly {
    if (activationMethod & kActivationMethodSwipeUp) {
        [self installKeyboardExtensionSwipeUpHooksForSpotlightOnly:NO];
    } else if (spotlightSwipeUpOnly) {
        [self installKeyboardExtensionSwipeUpHooksForSpotlightOnly:YES];
    }
}

@end
