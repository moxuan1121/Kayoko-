//
//  KayokoHelperHookInstaller.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KayokoHelperHookInstaller : NSObject
+ (void)installApplicationHooksWithActivationMethod:(NSUInteger)activationMethod;
+ (void)installSpringBoardActivationHooksWithActivationMethod:(NSUInteger)activationMethod;
+ (void)installKeyboardExtensionHooksWithActivationMethod:(NSUInteger)activationMethod
                                     spotlightSwipeUpOnly:(BOOL)spotlightSwipeUpOnly;
@end

@interface KayokoHelperHookInstaller (SwipeUp)
+ (void)installSwipeUpHooks;
+ (void)installKeyboardExtensionSwipeUpHooksForSpotlightOnly:(BOOL)spotlightOnly;
@end

NS_ASSUME_NONNULL_END
