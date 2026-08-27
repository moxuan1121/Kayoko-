//
//  KayokoSpringBoardHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import <CaptainHook/CaptainHook.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

#import "KayokoCoreRuntime.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoSpringBoardHooks.h"

CHDeclareClass(FBScene);
CHDeclareClass(UIWindowScene);
CHDeclareClass(UIViewController);
CHDeclareClass(SBCoverSheetPrimarySlidingViewController);
CHDeclareClass(SBHIconManager);
CHDeclareClass(SBSpotlightMultiplexingViewController);
CHDeclareClass(SBHLibrarySearchController);
CHDeclareClass(SBMainDisplaySystemGestureManager);
CHDeclareClass(SBMainSwitcherViewController);
CHDeclareClass(SBMainSwitcherControllerCoordinator);
CHDeclareClass(SBApplicationController);

@class FBSSceneTransitionContext;
@class UIApplicationSceneSettings;
typedef void (^FBSceneUpdateCompletion)(void);

@interface FBScene : NSObject
- (void)updateSettings:(UIApplicationSceneSettings *)settings
    withTransitionContext:(FBSSceneTransitionContext *)context
               completion:(FBSceneUpdateCompletion)completion;
@end

@interface SBCoverSheetPrimarySlidingViewController : UIViewController
@end

@interface SBMainSwitcherViewController : UIViewController
- (BOOL)isMainSwitcherVisible;
@end

@interface SBMainSwitcherControllerCoordinator : NSObject
- (BOOL)isAnySwitcherVisible;
@end

@interface SBHIconManager : NSObject
- (void)rootFolderControllerViewWillAppear:(id)controller;
@end

@interface SBSpotlightMultiplexingViewController : UIViewController
@end

@interface SBHLibrarySearchController : NSObject
- (void)_willDismissSearchAnimated:(BOOL)animated;
- (void)_willPresentSearchAnimated:(BOOL)animated;
- (void)_didDismissSearch;
- (void)_didPresentSearch;
- (void)beginEditingForSearchField;
- (void)endEditingForSearchField;
- (BOOL)isSearchFieldEditing;
@end

@interface SBApplicationController : NSObject
- (void)applicationsAdded:(id)added;
- (void)applicationsDemoted:(id)demoted;
- (void)applicationsRemoved:(id)removed;
- (void)applicationsReplaced:(id)replaced;
- (void)applicationsUpdated:(id)updated;
@end

@interface SBMainDisplaySystemGestureManager : NSObject
- (BOOL)_isGestureWithTypeAllowed:(NSInteger)type;
@end

static const NSInteger kKayokoSystemGestureTypeCoverSheet = 0x1;
static const NSInteger kKayokoSystemGestureTypeMultitaskingA = 0x29;
static const NSInteger kKayokoSystemGestureTypeMultitaskingB = 0x2B;
static const NSInteger kKayokoSystemGestureTypeControlCenter = 0x6;

NS_ASSUME_NONNULL_BEGIN

@interface KayokoSpringBoardHookInstaller ()

#pragma mark - Status Bar Panel

+ (BOOL)isStatusBarWindow:(UIWindow *)window;
+ (void)installPanelIfNeededInStatusBarWindow:(UIWindow *)window;

#pragma mark - Visibility

+ (void)hideForHomeScreenIfVisible:(id)controller;
+ (void)hideForLayoutStateTransition;
+ (void)hideForAppSwitcherIfVisible:(id)switcher;
+ (void)handleWindowWillRotateNotification:(NSNotification *)notification;

#pragma mark - Hook Installation

+ (void)installApplicationMetadataHooks;
+ (void)installRotationObserver;
+ (void)installSceneSettingsHooks;

@end

NS_ASSUME_NONNULL_END

#pragma mark - Status Bar Hooks

CHOptimizedMethod1(self, void, UIWindowScene, _delegate_windowDidBecomeVisible, UIWindow *, window) {
    CHSuper1(UIWindowScene, _delegate_windowDidBecomeVisible, window);
    [KayokoSpringBoardHookInstaller installPanelIfNeededInStatusBarWindow:window];
}

#pragma mark - Visibility Hooks

CHOptimizedMethod1(self, void, UIViewController, viewWillAppear, BOOL, animated) {
    CHSuper1(UIViewController, viewWillAppear, animated);
    [KayokoSpringBoardHookInstaller hideForHomeScreenIfVisible:self];
}

CHOptimizedMethod1(self, void, SBHIconManager, rootFolderControllerViewWillAppear, id, controller) {
    CHSuper1(SBHIconManager, rootFolderControllerViewWillAppear, controller);
    [[KayokoCoreRuntime sharedRuntime] hide];
}

CHOptimizedMethod1(self, void, SBCoverSheetPrimarySlidingViewController, _endTransitionToAppeared, BOOL, appeared) {
    CHSuper1(SBCoverSheetPrimarySlidingViewController, _endTransitionToAppeared, appeared);
    if (appeared) {
        [[KayokoCoreRuntime sharedRuntime] hideImmediately];
    }
}

CHOptimizedMethod1(self, void, SBSpotlightMultiplexingViewController, viewWillDisappear, BOOL, animated) {
    CHSuper1(SBSpotlightMultiplexingViewController, viewWillDisappear, animated);
    if (animated) {
        [[KayokoCoreRuntime sharedRuntime] hide];
    } else {
        [[KayokoCoreRuntime sharedRuntime] hideImmediately];
    }
}

CHOptimizedMethod1(self, void, SBHLibrarySearchController, _willDismissSearchAnimated, BOOL, animated) {
    CHSuper1(SBHLibrarySearchController, _willDismissSearchAnimated, animated);
    if (animated) {
        [[KayokoCoreRuntime sharedRuntime] hide];
    } else {
        [[KayokoCoreRuntime sharedRuntime] hideImmediately];
    }
}

#pragma mark - Application Metadata Hooks

CHOptimizedMethod1(self, void, SBApplicationController, applicationsAdded, id, added) {
    CHSuper1(SBApplicationController, applicationsAdded, added);
    [[KayokoCoreRuntime sharedRuntime] handleApplicationMetadataChanged];
}

CHOptimizedMethod1(self, void, SBApplicationController, applicationsDemoted, id, demoted) {
    CHSuper1(SBApplicationController, applicationsDemoted, demoted);
    [[KayokoCoreRuntime sharedRuntime] handleApplicationMetadataChanged];
}

CHOptimizedMethod1(self, void, SBApplicationController, applicationsRemoved, id, removed) {
    CHSuper1(SBApplicationController, applicationsRemoved, removed);
    [[KayokoCoreRuntime sharedRuntime] handleApplicationMetadataChanged];
}

CHOptimizedMethod1(self, void, SBApplicationController, applicationsReplaced, id, replaced) {
    CHSuper1(SBApplicationController, applicationsReplaced, replaced);
    [[KayokoCoreRuntime sharedRuntime] handleApplicationMetadataChanged];
}

CHOptimizedMethod1(self, void, SBApplicationController, applicationsUpdated, id, updated) {
    CHSuper1(SBApplicationController, applicationsUpdated, updated);
    [[KayokoCoreRuntime sharedRuntime] handleApplicationMetadataChanged];
}

#pragma mark - System Gesture Hooks

CHOptimizedMethod1(self, BOOL, SBMainDisplaySystemGestureManager, _isGestureWithTypeAllowed, NSInteger, type) {
    KayokoCoreRuntime *runtime = [KayokoCoreRuntime sharedRuntime];
    if ((type == kKayokoSystemGestureTypeCoverSheet || type == kKayokoSystemGestureTypeControlCenter) &&
        [runtime fullscreenSearchActive]) {
        return NO;
    }
    if ((type == kKayokoSystemGestureTypeMultitaskingA || type == kKayokoSystemGestureTypeMultitaskingB) &&
        [runtime systemMultitaskingGestureSuppressed]) {
        return NO;
    }

    return CHSuper1(SBMainDisplaySystemGestureManager, _isGestureWithTypeAllowed, type);
}

#pragma mark - App Switcher Hooks

CHOptimizedMethod2(self, void, SBMainSwitcherViewController, layoutStateTransitionCoordinator, id, coordinator,
                   transitionDidBeginWithTransitionContext, id, context) {
    CHSuper2(SBMainSwitcherViewController, layoutStateTransitionCoordinator, coordinator,
             transitionDidBeginWithTransitionContext, context);
    [KayokoSpringBoardHookInstaller hideForLayoutStateTransition];
}

CHOptimizedMethod2(self, void, SBMainSwitcherViewController, layoutStateTransitionCoordinator, id, coordinator,
                   transitionDidEndWithTransitionContext, id, context) {
    CHSuper2(SBMainSwitcherViewController, layoutStateTransitionCoordinator, coordinator,
             transitionDidEndWithTransitionContext, context);
    [KayokoSpringBoardHookInstaller hideForAppSwitcherIfVisible:self];
}

CHOptimizedMethod2(self, void, SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator, id, coordinator,
                   transitionDidBeginWithTransitionContext, id, context) {
    CHSuper2(SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator, coordinator,
             transitionDidBeginWithTransitionContext, context);
    [KayokoSpringBoardHookInstaller hideForLayoutStateTransition];
}

CHOptimizedMethod2(self, void, SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator, id, coordinator,
                   transitionDidEndWithTransitionContext, id, context) {
    CHSuper2(SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator, coordinator,
             transitionDidEndWithTransitionContext, context);
    [KayokoSpringBoardHookInstaller hideForAppSwitcherIfVisible:self];
}

#pragma mark - Scene Hooks

CHOptimizedMethod3(self, void, FBScene, updateSettings, UIApplicationSceneSettings *, settings, withTransitionContext,
                   FBSSceneTransitionContext *, context, completion, FBSceneUpdateCompletion, completion) {
    CHSuper3(FBScene, updateSettings, settings, withTransitionContext, context, completion, completion);
    [[KayokoCoreRuntime sharedRuntime] handleScene:self didUpdateSettings:settings];
}

@implementation KayokoSpringBoardHookInstaller

#pragma mark - Status Bar Panel

+ (BOOL)isStatusBarWindow:(UIWindow *)window {
    Class statusBarWindowClass = NSClassFromString(@"UIStatusBarWindow");
    if (statusBarWindowClass && [window isKindOfClass:statusBarWindowClass]) {
        return YES;
    }

    Class springBoardStatusBarWindowClass = NSClassFromString(@"SBStatusBarWindow");
    return springBoardStatusBarWindowClass && [window isKindOfClass:springBoardStatusBarWindowClass];
}

+ (BOOL)isTextEffectsWindow:(UIWindow *)window {
    Class textEffectsWindowClass = NSClassFromString(@"UITextEffectsWindow");
    return textEffectsWindowClass && [window isKindOfClass:textEffectsWindowClass];
}

+ (void)installPanelIfNeededInStatusBarWindow:(UIWindow *)window {
    if (![self isStatusBarWindow:window]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self isStatusBarWindow:window]) {
          [[KayokoCoreRuntime sharedRuntime] installPanelInStatusBarWindow:window];
      }
    });
}

#pragma mark - Visibility

+ (BOOL)isHomeScreenController:(id)controller {
    static Class iconControllerClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      iconControllerClass = NSClassFromString(@"SBIconController");
    });
    return iconControllerClass && [controller isKindOfClass:iconControllerClass];
}

+ (void)hideForHomeScreenIfVisible:(id)controller {
    if (![self isHomeScreenController:controller]) {
        return;
    }

    [[KayokoCoreRuntime sharedRuntime] hide];
}

+ (void)hideForLayoutStateTransition {
    KayokoCoreRuntime *runtime = [KayokoCoreRuntime sharedRuntime];
    if (![runtime panelVisible]) {
        return;
    }

    [runtime hide];
}

+ (void)hideForAppSwitcherIfVisible:(id)switcher {
    KayokoCoreRuntime *runtime = [KayokoCoreRuntime sharedRuntime];
    if (![runtime panelVisible]) {
        return;
    }

    BOOL switcherVisible = NO;
    if ([switcher respondsToSelector:@selector(isMainSwitcherVisible)]) {
        switcherVisible = [(SBMainSwitcherViewController *)switcher isMainSwitcherVisible];
    } else if ([switcher respondsToSelector:@selector(isAnySwitcherVisible)]) {
        switcherVisible = [(SBMainSwitcherControllerCoordinator *)switcher isAnySwitcherVisible];
    }

    if (switcherVisible) {
        [runtime hide];
    }
}

+ (void)handleWindowWillRotateNotification:(NSNotification *)notification {
    UIWindow *window = notification.object;
    if ([self isTextEffectsWindow:window]) {
        [[KayokoCoreRuntime sharedRuntime] hideForRotation];
    }
}

#pragma mark - Hook Installation

+ (void)installStatusBarHooks {
    Class windowSceneClass = NSClassFromString(@"UIWindowScene");
    SEL windowDidBecomeVisibleSelector = @selector(_delegate_windowDidBecomeVisible:);
    if (windowSceneClass && [windowSceneClass instancesRespondToSelector:windowDidBecomeVisibleSelector]) {
        CHLoadClass_(&UIWindowScene$, windowSceneClass);
        CHHook1(UIWindowScene, _delegate_windowDidBecomeVisible);
        return;
    }

}

+ (void)installHomeScreenHooks {
    Class iconControllerClass = NSClassFromString(@"SBIconController");
    CHLoadClass(UIViewController);
    SEL viewWillAppearSelector = @selector(viewWillAppear:);
    if (iconControllerClass && [CHClass(UIViewController) instancesRespondToSelector:viewWillAppearSelector]) {
        CHHook1(UIViewController, viewWillAppear);
    }

    Class iconManagerClass = NSClassFromString(@"SBHIconManager");
    CHLoadClass_(&SBHIconManager$, iconManagerClass);
    SEL rootFolderWillAppearSelector = @selector(rootFolderControllerViewWillAppear:);
    if ([iconManagerClass instancesRespondToSelector:rootFolderWillAppearSelector]) {
        CHHook1(SBHIconManager, rootFolderControllerViewWillAppear);
    }
}

+ (void)installLockScreenTransitionHooks {
    Class coverSheetClass = NSClassFromString(@"SBCoverSheetPrimarySlidingViewController");
    CHLoadClass_(&SBCoverSheetPrimarySlidingViewController$, coverSheetClass);
    SEL transitionEndSelector = @selector(_endTransitionToAppeared:);
    if ([coverSheetClass instancesRespondToSelector:transitionEndSelector]) {
        CHHook1(SBCoverSheetPrimarySlidingViewController, _endTransitionToAppeared);
    }
}

+ (void)installSpotlightHooks {
    Class spotlightClass = NSClassFromString(@"SBSpotlightMultiplexingViewController");
    CHLoadClass_(&SBSpotlightMultiplexingViewController$, spotlightClass);
    SEL viewWillDisappearSelector = @selector(viewWillDisappear:);
    if ([spotlightClass instancesRespondToSelector:viewWillDisappearSelector]) {
        CHHook1(SBSpotlightMultiplexingViewController, viewWillDisappear);
    }
}

+ (void)installLibrarySearchHooks {
    Class librarySearchControllerClass = NSClassFromString(@"SBHLibrarySearchController");
    CHLoadClass_(&SBHLibrarySearchController$, librarySearchControllerClass);
    SEL willDismissSearchSelector = @selector(_willDismissSearchAnimated:);
    if ([librarySearchControllerClass instancesRespondToSelector:willDismissSearchSelector]) {
        CHHook1(SBHLibrarySearchController, _willDismissSearchAnimated);
    }
}

+ (void)installApplicationMetadataHooks {
    Class applicationControllerClass = NSClassFromString(@"SBApplicationController");
    if (!applicationControllerClass) {
        return;
    }

    CHLoadClass_(&SBApplicationController$, applicationControllerClass);
    if ([applicationControllerClass instancesRespondToSelector:@selector(applicationsAdded:)]) {
        CHHook1(SBApplicationController, applicationsAdded);
    }
    if ([applicationControllerClass instancesRespondToSelector:@selector(applicationsDemoted:)]) {
        CHHook1(SBApplicationController, applicationsDemoted);
    }
    if ([applicationControllerClass instancesRespondToSelector:@selector(applicationsRemoved:)]) {
        CHHook1(SBApplicationController, applicationsRemoved);
    }
    if ([applicationControllerClass instancesRespondToSelector:@selector(applicationsReplaced:)]) {
        CHHook1(SBApplicationController, applicationsReplaced);
    }
    if ([applicationControllerClass instancesRespondToSelector:@selector(applicationsUpdated:)]) {
        CHHook1(SBApplicationController, applicationsUpdated);
    }
}

+ (void)installRotationObserver {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(handleWindowWillRotateNotification:)
                                                   name:@"UIWindowWillRotateNotification"
                                                 object:nil];
    });
}

+ (void)installSceneSettingsHooks {
    Class sceneClass = NSClassFromString(@"FBScene");
    SEL updateSettingsSelector = @selector(updateSettings:withTransitionContext:completion:);
    if (![sceneClass instancesRespondToSelector:updateSettingsSelector]) {
        return;
    }

    CHLoadClass_(&FBScene$, sceneClass);
    CHHook3(FBScene, updateSettings, withTransitionContext, completion);
}

+ (void)installSystemGestureHooks {
    Class gestureManagerClass = NSClassFromString(@"SBMainDisplaySystemGestureManager");
    CHLoadClass_(&SBMainDisplaySystemGestureManager$, gestureManagerClass);
    SEL gestureAllowedSelector = @selector(_isGestureWithTypeAllowed:);
    if ([gestureManagerClass instancesRespondToSelector:gestureAllowedSelector]) {
        CHHook1(SBMainDisplaySystemGestureManager, _isGestureWithTypeAllowed);
    }
}

+ (void)installAppSwitcherHooks {
    SEL transitionBeginSelector = @selector(layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:);
    SEL transitionEndSelector = @selector(layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:);

    Class switcherViewControllerClass = NSClassFromString(@"SBMainSwitcherViewController");
    CHLoadClass_(&SBMainSwitcherViewController$, switcherViewControllerClass);
    if ([switcherViewControllerClass instancesRespondToSelector:transitionBeginSelector]) {
        CHHook2(SBMainSwitcherViewController, layoutStateTransitionCoordinator,
                transitionDidBeginWithTransitionContext);
    }
    if ([switcherViewControllerClass instancesRespondToSelector:transitionEndSelector]) {
        CHHook2(SBMainSwitcherViewController, layoutStateTransitionCoordinator, transitionDidEndWithTransitionContext);
    }

    Class switcherCoordinatorClass = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    CHLoadClass_(&SBMainSwitcherControllerCoordinator$, switcherCoordinatorClass);
    if ([switcherCoordinatorClass instancesRespondToSelector:transitionBeginSelector]) {
        CHHook2(SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator,
                transitionDidBeginWithTransitionContext);
    }
    if ([switcherCoordinatorClass instancesRespondToSelector:transitionEndSelector]) {
        CHHook2(SBMainSwitcherControllerCoordinator, layoutStateTransitionCoordinator,
                transitionDidEndWithTransitionContext);
    }
}

#pragma mark - Entrypoint

+ (void)installHooks {
    [self installStatusBarHooks];


    [self installHomeScreenHooks];
    [self installAppSwitcherHooks];
    [self installLockScreenTransitionHooks];
    [self installSpotlightHooks];
    [self installLibrarySearchHooks];
    [self installApplicationMetadataHooks];
    [self installRotationObserver];
    [self installSceneSettingsHooks];
    [self installSystemGestureHooks];

}

@end
