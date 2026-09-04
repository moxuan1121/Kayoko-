//
//  KayokoCoreRuntime.m
//  Kayoko
//

#import "KayokoCoreRuntime.h"
#import "KayokoKeyboardHostResolver.h"
#import "KayokoMainViewController.h"
#import "KayokoHeaderButtonStyle.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPanelPresentationMode.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoPreferenceKeys.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import <HBLog.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <notify.h>
#import <roothide.h>

static NSTimeInterval const kKayokoMinimumFeedbackInterval = 0.6;
static NSTimeInterval const kKayokoPasteSuppressionExpirationDelay = 1.0;

@interface UIApplication (KayokoPrivate)
- (UIInterfaceOrientation)_frontMostAppOrientation;
@end

@interface UIApplicationSceneSettings : NSObject
- (UIUserInterfaceStyle)userInterfaceStyle;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

@protocol KayokoSBLockScreenManagerClass <NSObject>
+ (SBLockScreenManager *)sharedInstance;
@end

@protocol KayokoKeyboardAppearanceProviding <NSObject>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface TITextInputTraits : NSObject <KayokoKeyboardAppearanceProviding>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
- (TITextInputTraits *)textInputTraits;
- (NSObject<KayokoKeyboardAppearanceProviding> *)inputDelegate;
- (NSObject<KayokoKeyboardAppearanceProviding> *)delegate;
@end

@protocol KayokoUIKeyboardImplClass <NSObject>
+ (UIKeyboardImpl *)activeInstance;
@end

@interface KayokoOverlayWindow : UIWindow
@end

@interface KayokoWordSelectionPromptWindow : UIWindow
@property(nonatomic, weak) UIView *interactiveView;
@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoPasteSuppressionState : NSObject
@property(nonatomic, assign, readonly, getter=isActive) BOOL active;
- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay;
- (BOOL)consumeIfActive;
@end

@interface KayokoPasteSuppressionState ()

#pragma mark - State

@property(nonatomic, assign, readwrite, getter=isActive) BOOL active;
@property(nonatomic, assign) NSUInteger token;

#pragma mark - Expiration

@property(nonatomic, copy, nullable) dispatch_block_t expirationBlock;

#pragma mark - Lifecycle

- (void)clear;

#pragma mark - Expiration

- (void)cancelExpiration;
- (void)expireForToken:(NSUInteger)token;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *rootView = [[self rootViewController] view];
    if (!rootView || [rootView isHidden]) {
        return nil;
    }

    return [super hitTest:point withEvent:event];
}

@end

@implementation KayokoWordSelectionPromptWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return hitView == self.interactiveView || [hitView isDescendantOfView:self.interactiveView] ? hitView : nil;
}

@end

@implementation KayokoPasteSuppressionState

- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay {
    self.token++;
    self.active = YES;

    [self cancelExpiration];

    NSUInteger token = self.token;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t expirationBlock = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || strongSelf.token != token) {
          return;
      }

      [strongSelf expireForToken:token];
    });
    self.expirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(expirationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), expirationBlock);
}

- (BOOL)consumeIfActive {
    if (!self.active) {
        return NO;
    }

    [self clear];
    return YES;
}

- (void)clear {
    [self cancelExpiration];
    self.active = NO;
}

- (void)cancelExpiration {
    dispatch_block_t expirationBlock = self.expirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.expirationBlock = nil;
    }
}

- (void)expireForToken:(NSUInteger)token {
    if (self.token != token) {
        return;
    }

    self.expirationBlock = nil;
    self.active = NO;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoCoreRuntime () <KayokoMainViewControllerDelegate>

#pragma mark - Runtime Configuration

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) BOOL pasteTipsDisabled;

#pragma mark - View State

@property(nonatomic, strong, nullable) KayokoMainViewController *mainViewController;
@property(nonatomic, weak, nullable) UIWindow *statusBarWindow;
@property(nonatomic, strong, nullable) UIControl *portraitOutsideDismissOverlayView;
@property(nonatomic, strong, nullable) UIWindow *overlayWindow;
@property(nonatomic, assign) KayokoPanelPresentationMode activePresentationMode;
@property(nonatomic, assign) BOOL pendingHeightPreferenceApply;
@property(nonatomic, strong, nullable) KayokoWordSelectionPromptWindow *wordSelectionPromptWindow;
@property(nonatomic, strong, nullable) KayokoPasteboardItem *wordSelectionPromptItem;
@property(nonatomic, copy, nullable) dispatch_block_t wordSelectionPromptHideBlock;

#pragma mark - Preferences

@property(nonatomic, strong, nullable) NSUserDefaults *preferences;
@property(nonatomic, assign) NSUInteger maximumHistoryAmount;
@property(nonatomic, assign) BOOL saveText;
@property(nonatomic, assign) BOOL saveImages;
@property(nonatomic, assign) BOOL swipeToSelectWords;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) KayokoAutomaticPasteMode automaticPasteMode;
@property(nonatomic, assign) KayokoAutomaticPromotionMode automaticPromotionMode;
@property(nonatomic, assign) KayokoInitialViewMode initialViewMode;
@property(nonatomic, assign) BOOL alwaysScrollToTop;
@property(nonatomic, assign) KayokoClearButtonMode clearButtonMode;
@property(nonatomic, assign) BOOL dismissOnOutsideTouch;
@property(nonatomic, assign) BOOL playHapticFeedback;
@property(nonatomic, assign) KayokoItemDetailsMode itemDetailsMode;
@property(nonatomic, assign) CGFloat heightInPoints;
@property(nonatomic, assign) KayokoOverlayWindowLevelMode overlayWindowLevelMode;
@property(nonatomic, assign) CGFloat customOverlayWindowLevel;

#pragma mark - Feedback

@property(nonatomic, assign) NSTimeInterval lastPasteFeedbackOccurred;
@property(nonatomic, assign) NSTimeInterval lastCopyFeedbackOccurred;

#pragma mark - Pasteboard Capture

@property(nonatomic, strong) KayokoPasteSuppressionState *pasteSuppressionState;

#pragma mark - Device State

@property(nonatomic, assign) int lockStateToken;
@property(nonatomic, assign, getter=isPackageMaintenanceMode) BOOL packageMaintenanceMode;
@property(nonatomic, assign) BOOL observingMemoryWarnings;

#pragma mark - Panel Host

- (BOOL)preparePanelHostForPresentationMode:(KayokoPanelPresentationMode)presentationMode;
- (CGRect)fullscreenPanelFrameInWindow:(nullable UIWindow *)window;
- (KayokoPanelPresentationMode)currentPresentationMode;
- (void)hideWordSelectionPrompt;
- (void)showWordSelectionPromptForItem:(KayokoPasteboardItem *)item;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoCoreRuntime

+ (instancetype)sharedRuntime {
    static KayokoCoreRuntime *runtime = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      runtime = [[self alloc] initPrivate];
    });
    return runtime;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _itemDetailsMode = kKayokoPreferenceKeyItemDetailsModeDefaultValue;
        _heightInPoints = 420;
        _activePresentationMode = KayokoPanelPresentationModePortraitDrawer;
        _pasteSuppressionState = [[KayokoPasteSuppressionState alloc] init];
    }
    return self;
}

- (BOOL)panelVisible {
    return self.mainViewController && ![self.mainViewController isHidden];
}

- (BOOL)fullscreenSearchActive {
    if (!self.panelVisible) {
        return NO;
    }

    return [self activePresentationMode] == KayokoPanelPresentationModeCompactLandscapeFullscreen ||
           [self.mainViewController isFullscreenSearchActive];
}

- (BOOL)systemMultitaskingGestureSuppressed {
    return self.panelVisible && [self.mainViewController shouldSuppressSystemMultitaskingGesture];
}

#pragma mark - Panel


- (CGRect)referenceBoundsForWindow:(nullable UIWindow *)window {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    if (!window) {
        return screenBounds;
    }
    CGRect windowBounds = [window bounds];
    if (CGRectGetWidth(windowBounds) < 200.0 || CGRectGetHeight(windowBounds) < 200.0) {
        return screenBounds;
    }
    return windowBounds;
}

- (CGRect)portraitPanelFrameInWindow:(nullable UIWindow *)window {
    // Full-width bottom sheet: no side or bottom gaps. Height follows the
    // user's panel-height preference exactly.
    CGRect bounds = [self referenceBoundsForWindow:window];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat maxHeight = MAX(CGRectGetHeight(bounds), 220.0);
    CGFloat height = MIN(MAX(self.heightInPoints, 220.0), maxHeight);
    CGFloat y = CGRectGetMaxY(bounds) - height;
    return CGRectMake(CGRectGetMinX(bounds), y, width, height);
}

- (CGRect)fullscreenPanelFrameInWindow:(UIWindow *)window {
    // Landscape keeps the same floating-card language as portrait: cap the
    // width, honor the configured height, and center the card in the host.
    CGRect bounds = [self referenceBoundsForWindow:window];
    CGFloat inset = kKayokoPanelFloatingInset;
    CGFloat width = MIN(kKayokoPanelFloatingMaxWidth, MAX(CGRectGetWidth(bounds) - inset * 2.0, 0.0));
    CGFloat maximumHeight = MAX(CGRectGetHeight(bounds) - inset * 2.0, 0.0);
    CGFloat preferredHeight = MIN(MAX(self.heightInPoints, 220.0), maximumHeight);
    CGFloat x = CGRectGetMidX(bounds) - width * 0.5;
    CGFloat y = CGRectGetMidY(bounds) - preferredHeight * 0.5;
    // Preserve the reference top position while extending the card to the
    // screen bottom, avoiding an exposed strip below the landscape panel.
    CGFloat height = MAX(CGRectGetMaxY(bounds) - y, 0.0);
    return CGRectMake(x, y, width, height);
}





- (UIControl *)ensurePortraitOutsideDismissOverlayInWindow:(UIWindow *)window {
    if (self.portraitOutsideDismissOverlayView && [self.portraitOutsideDismissOverlayView superview] == window) {
        return self.portraitOutsideDismissOverlayView;
    }

    [self.portraitOutsideDismissOverlayView removeFromSuperview];
    UIControl *outsideDismissOverlayView = [[UIControl alloc] initWithFrame:[window bounds]];
    [outsideDismissOverlayView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    // Keep outside dim very light so the floating card blur samples a bright scene and stays transparent.
    [outsideDismissOverlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.06]];
    [outsideDismissOverlayView setAlpha:0];
    [outsideDismissOverlayView setHidden:YES];
    [outsideDismissOverlayView setUserInteractionEnabled:NO];
    [window addSubview:outsideDismissOverlayView];
    self.portraitOutsideDismissOverlayView = outsideDismissOverlayView;
    return outsideDismissOverlayView;
}

- (void)createMainViewControllerIfNeeded {
    if (self.mainViewController) {
        return;
    }

    CGRect initialFrame = [self portraitPanelFrameInWindow:self.statusBarWindow];
    self.mainViewController = [[KayokoMainViewController alloc] initWithFrame:initialFrame];
    [self.mainViewController setDelegate:self];
    [self applyPreferencesToView];
}

- (void)installPanelInStatusBarWindow:(UIWindow *)window {
    if (!window) {
        return;
    }

    self.statusBarWindow = window;
    if (!self.mainViewController) {
        return;
    }

    if (![self.mainViewController isHidden]) {
        // The status-bar window can be recreated when SpringBoard changes scenes. Rebind
        // the visible card to the current scene instead of leaving the old overlay behind.
        [self preparePanelHostForPresentationMode:[self currentPresentationMode]];
        return;
    }

    [self preparePanelHostForPresentationMode:KayokoPanelPresentationModePortraitDrawer];
}

- (CGFloat)overlayWindowLevel {
    if (self.overlayWindowLevelMode == kKayokoOverlayWindowLevelModeCustom) {
        return self.customOverlayWindowLevel;
    }

    // UIWindowLevel has no public maximum. Use CGFloat's largest finite value for the
    // dedicated Kayoko overlay window; the card itself remains bounded and transparent
    // outside its content.
    return CGFLOAT_MAX;
}

- (UIInterfaceOrientation)frontmostAppInterfaceOrientation {
    UIApplication *application = [UIApplication sharedApplication];
    if (![application respondsToSelector:@selector(_frontMostAppOrientation)]) {
        return UIInterfaceOrientationUnknown;
    }

    return [application _frontMostAppOrientation];
}

- (UIInterfaceOrientationMask)compactLandscapeSupportedInterfaceOrientations {
    switch ([self frontmostAppInterfaceOrientation]) {
    case UIInterfaceOrientationLandscapeLeft:
        return UIInterfaceOrientationMaskLandscapeLeft;
    case UIInterfaceOrientationLandscapeRight:
        return UIInterfaceOrientationMaskLandscapeRight;
    default:
        return UIInterfaceOrientationMaskLandscape;
    }
}

- (nullable UIWindow *)overlayWindowCreatingIfNeeded {
    UIWindowScene *windowScene = [self.statusBarWindow windowScene];
    if (!windowScene) {
        return nil;
    }

    if (self.overlayWindow && [self.overlayWindow windowScene] != windowScene) {
        [self.overlayWindow setHidden:YES];
        [self.overlayWindow setRootViewController:nil];
        self.overlayWindow = nil;
    }

    if (!self.overlayWindow) {
        UIWindow *window = [[KayokoOverlayWindow alloc] initWithWindowScene:windowScene];
        [window setBackgroundColor:[UIColor clearColor]];
        [window setOpaque:NO];
        [window setClipsToBounds:YES];
        [window setHidden:YES];
        self.overlayWindow = window;
    }

    [self.overlayWindow setWindowLevel:[self overlayWindowLevel]];
    return self.overlayWindow;
}

- (void)applyOverlayWindowFrame:(UIWindow *)window {
    CGRect bounds = [[UIScreen mainScreen] bounds];
    [window setFrame:bounds];
    [[window rootViewController].view setFrame:[window bounds]];
    [[window rootViewController].view setNeedsLayout];
}

- (void)tearDownOverlayWindowHost {
    [self.overlayWindow setHidden:YES];
    if ([self.overlayWindow rootViewController] == self.mainViewController) {
        [self.overlayWindow setRootViewController:nil];
    }
    [self.mainViewController setKayokoSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
}

- (void)handleMainPanelDidHide {
    // Thumbnails can be reconstructed from the bounded disk cache when the
    // panel opens again; do not keep decoded images resident in SpringBoard.
    [[KayokoPasteboardManager sharedInstance] resetThumbnailMemoryCache];

    if ([self activePresentationMode] != KayokoPanelPresentationModeCompactLandscapeFullscreen &&
        [self.overlayWindow rootViewController] != self.mainViewController) {
        return;
    }

    [self tearDownOverlayWindowHost];
}

- (void)mainViewControllerDidRequestFocusRestore:(KayokoMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self requestHelperFocusRestore];
}

- (void)mainViewControllerDidHide:(KayokoMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self handleMainPanelDidHide];
}

- (BOOL)prepareCompactLandscapeHost {
    UIWindow *window = [self overlayWindowCreatingIfNeeded];
    if (!window) {
        return NO;
    }

    UIControl *outsideDismissOverlayView = [self ensurePortraitOutsideDismissOverlayInWindow:window];
    [self.mainViewController setOutsideDismissOverlayView:outsideDismissOverlayView];
    [self.mainViewController
        setKayokoSupportedInterfaceOrientations:[self compactLandscapeSupportedInterfaceOrientations]];
    // The overlay window still follows the foreground app's landscape
    // orientation, but its content uses the regular floating-card layout.
    [self.mainViewController setPresentationMode:KayokoPanelPresentationModePortraitDrawer];
    [self applyOverlayWindowFrame:window];
    if ([window rootViewController] != self.mainViewController) {
        [[self.mainViewController view] removeFromSuperview];
        [window setRootViewController:self.mainViewController];
    }
    [window setHidden:NO];
    [self applyOverlayWindowFrame:window];

    UIView *panelView = [self.mainViewController view];
    [window bringSubviewToFront:outsideDismissOverlayView];
    [window bringSubviewToFront:panelView];
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [panelView setFrame:[self fullscreenPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = KayokoPanelPresentationModeCompactLandscapeFullscreen;
    return YES;
}

- (BOOL)preparePortraitHost {
    UIWindow *window = [self overlayWindowCreatingIfNeeded];
    if (!window) {
        return NO;
    }

    UIControl *outsideDismissOverlayView = [self ensurePortraitOutsideDismissOverlayInWindow:window];
    [self.mainViewController setOutsideDismissOverlayView:outsideDismissOverlayView];
    [self.mainViewController setKayokoSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
    [self.mainViewController setPresentationMode:KayokoPanelPresentationModePortraitDrawer];

    UIView *panelView = [self.mainViewController view];
    [self applyOverlayWindowFrame:window];
    if ([window rootViewController] != self.mainViewController) {
        [panelView removeFromSuperview];
        [window setRootViewController:self.mainViewController];
    }
    [window setHidden:NO];
    [self applyOverlayWindowFrame:window];
    [window bringSubviewToFront:outsideDismissOverlayView];
    [window bringSubviewToFront:panelView];
    // Portrait floating card: center horizontally, pin to bottom with gaps.
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin];
    [panelView setFrame:[self portraitPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = KayokoPanelPresentationModePortraitDrawer;
    return YES;
}

- (BOOL)preparePanelHostForPresentationMode:(KayokoPanelPresentationMode)presentationMode {
    if (!self.mainViewController) {
        return NO;
    }

    if (!CGAffineTransformIsIdentity([[self.mainViewController view] transform])) {
        [[self.mainViewController view] setTransform:CGAffineTransformIdentity];
    }

    if (presentationMode == KayokoPanelPresentationModeCompactLandscapeFullscreen) {
        return [self prepareCompactLandscapeHost];
    }

    return [self preparePortraitHost];
}

- (void)applyHeightPreferenceToViewApplyingWhenHidden:(BOOL)applyWhenHidden {
    if (!self.mainViewController) {
        return;
    }

    if (!applyWhenHidden && [self.mainViewController isHidden]) {
        return;
    }

    if ([self activePresentationMode] == KayokoPanelPresentationModeCompactLandscapeFullscreen) {
        UIWindow *window = self.overlayWindow;
        UIView *panelView = [self.mainViewController view];
        CGRect newFrame = [self fullscreenPanelFrameInWindow:window];
        if (!CGRectEqualToRect([panelView frame], newFrame)) {
            if (!CGAffineTransformIsIdentity([panelView transform])) {
                [panelView setTransform:CGAffineTransformIdentity];
            }
            [panelView setFrame:newFrame];
            [panelView setNeedsLayout];
        }
        return;
    }

    // Don't fight transient presentation frames (portrait search above keyboard, note editor, etc.).
    if ([self.mainViewController isFullscreenSearchActive] || [self.mainViewController isNoteEditing]) {
        return;
    }

    UIView *panelView = [self.mainViewController view];
    UIWindow *hostWindow = (UIWindow *)[panelView superview];
    if (![hostWindow isKindOfClass:[UIWindow class]]) {
        hostWindow = self.statusBarWindow;
    }
    // Portrait/landscape share floating-card geometry.
    CGRect newFrame = [self portraitPanelFrameInWindow:hostWindow];
    if (!CGRectEqualToRect([panelView frame], newFrame)) {
        if (!CGAffineTransformIsIdentity([panelView transform])) {
            [panelView setTransform:CGAffineTransformIdentity];
        }
        [panelView setFrame:newFrame];
        [panelView setNeedsLayout];
    }
}

- (void)applyPreferencesToView {
    if (!self.mainViewController) {
        return;
    }

    if ([self.mainViewController automaticallyPaste] != self.automaticallyPaste) {
        [self.mainViewController setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([self.mainViewController dismissOnOutsideTouch] != self.dismissOnOutsideTouch) {
        [self.mainViewController setDismissOnOutsideTouch:self.dismissOnOutsideTouch];
    }
    if ([self.mainViewController swipeToSelectWords] != self.swipeToSelectWords) {
        [self.mainViewController setSwipeToSelectWords:self.swipeToSelectWords];
    }
    if ([self.mainViewController itemDetailsMode] != self.itemDetailsMode) {
        [self.mainViewController setItemDetailsMode:self.itemDetailsMode];
    }
    if ([self.mainViewController initialViewMode] != self.initialViewMode) {
        [self.mainViewController setInitialViewMode:self.initialViewMode];
    }
    if ([self.mainViewController alwaysScrollToTop] != self.alwaysScrollToTop) {
        [self.mainViewController setAlwaysScrollToTop:self.alwaysScrollToTop];
    }
    if ([self.mainViewController clearButtonMode] != self.clearButtonMode) {
        [self.mainViewController setClearButtonMode:self.clearButtonMode];
    }
    if ([self.mainViewController shouldPlayFeedback] != self.playHapticFeedback) {
        [self.mainViewController setShouldPlayFeedback:self.playHapticFeedback];
    }

    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
}

- (void)requestHelperFocusRestore {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyHelperRestoreFocus, nil, nil, YES);
}

#pragma mark - Preferences

- (void)readPasteTipPreferencesFromPreferences:(NSUserDefaults *)preferences {
    self.enabled = [[preferences objectForKey:kKayokoPreferenceKeyEnabled] boolValue];
    self.pasteTipsDisabled = [[preferences objectForKey:kKayokoPreferenceKeyDisablePasteTips] boolValue];
}

- (BOOL)refreshPasteTipPreferences {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyDisablePasteTips : @(kKayokoPreferenceKeyDisablePasteTipsDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:preferences];
    return self.enabled;
}

- (void)loadPreferences {
    self.preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [self.preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyMaximumHistoryAmount : @(kKayokoPreferenceKeyMaximumHistoryAmountDefaultValue),
        kKayokoPreferenceKeySaveText : @(kKayokoPreferenceKeySaveTextDefaultValue),
        kKayokoPreferenceKeySaveImages : @(kKayokoPreferenceKeySaveImagesDefaultValue),
        kKayokoPreferenceKeySwipeToSelectWords : @(kKayokoPreferenceKeySwipeToSelectWordsDefaultValue),
        kKayokoPreferenceKeyAutomaticallyPaste : @(kKayokoPreferenceKeyAutomaticallyPasteDefaultValue),
        kKayokoPreferenceKeyAutomaticPasteMode : @(kKayokoPreferenceKeyAutomaticPasteModeDefaultValue),
        kKayokoPreferenceKeyAutomaticPromotionMode : @(kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue),
        kKayokoPreferenceKeyInitialViewMode : @(kKayokoPreferenceKeyInitialViewModeDefaultValue),
        kKayokoPreferenceKeyAlwaysScrollToTop : @(kKayokoPreferenceKeyAlwaysScrollToTopDefaultValue),
        kKayokoPreferenceKeyClearButtonMode : @(kKayokoPreferenceKeyClearButtonModeDefaultValue),
        kKayokoPreferenceKeyDismissOnOutsideTouch : @(kKayokoPreferenceKeyDismissOnOutsideTouchDefaultValue),
        kKayokoPreferenceKeyDisablePasteTips : @(kKayokoPreferenceKeyDisablePasteTipsDefaultValue),
        kKayokoPreferenceKeyPlayHapticFeedback : @(kKayokoPreferenceKeyPlayHapticFeedbackDefaultValue),
        kKayokoPreferenceKeyItemDetailsMode : @(kKayokoPreferenceKeyItemDetailsModeDefaultValue),
        kKayokoPreferenceKeyHeightInPoints : @(kKayokoPreferenceKeyHeightInPointsDefaultValue),
        kKayokoPreferenceKeyOverlayWindowLevelMode : @(kKayokoPreferenceKeyOverlayWindowLevelModeDefaultValue),
        kKayokoPreferenceKeyOverlayWindowLevel : @(kKayokoPreferenceKeyOverlayWindowLevelDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:self.preferences];
    self.maximumHistoryAmount = [KayokoPasteboardManager
        normalizedMaximumHistoryAmountForValue:[[self.preferences objectForKey:kKayokoPreferenceKeyMaximumHistoryAmount]
                                                   unsignedIntegerValue]];
    self.saveText = [[self.preferences objectForKey:kKayokoPreferenceKeySaveText] boolValue];
    self.saveImages = [[self.preferences objectForKey:kKayokoPreferenceKeySaveImages] boolValue];
    self.swipeToSelectWords = [[self.preferences objectForKey:kKayokoPreferenceKeySwipeToSelectWords] boolValue];
    self.automaticallyPaste = [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticallyPaste] boolValue];
    self.automaticPasteMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticPasteMode] unsignedIntegerValue];
    if (self.automaticPasteMode != kKayokoAutomaticPasteModeClassic &&
        self.automaticPasteMode != kKayokoAutomaticPasteModeSimulated &&
        self.automaticPasteMode != kKayokoAutomaticPasteModeAutomatic) {
        self.automaticPasteMode = kKayokoPreferenceKeyAutomaticPasteModeDefaultValue;
    }
    self.automaticPromotionMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticPromotionMode] unsignedIntegerValue];
    if (self.automaticPromotionMode != kKayokoAutomaticPromotionModeOff &&
        self.automaticPromotionMode != kKayokoAutomaticPromotionModeHistoryOnly &&
        self.automaticPromotionMode != kKayokoAutomaticPromotionModeAlways) {
        self.automaticPromotionMode = kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue;
    }
    self.initialViewMode = [[self.preferences objectForKey:kKayokoPreferenceKeyInitialViewMode] unsignedIntegerValue];
    if (self.initialViewMode != kKayokoInitialViewModeHistory &&
        self.initialViewMode != kKayokoInitialViewModeFavorites &&
        self.initialViewMode != kKayokoInitialViewModePreviousSelection) {
        self.initialViewMode = kKayokoPreferenceKeyInitialViewModeDefaultValue;
    }
    self.alwaysScrollToTop = [[self.preferences objectForKey:kKayokoPreferenceKeyAlwaysScrollToTop] boolValue];
    self.clearButtonMode = [[self.preferences objectForKey:kKayokoPreferenceKeyClearButtonMode] unsignedIntegerValue];
    if (self.clearButtonMode != kKayokoClearButtonModeOff &&
        self.clearButtonMode != kKayokoClearButtonModeHistoryOnly &&
        self.clearButtonMode != kKayokoClearButtonModeAlways) {
        self.clearButtonMode = kKayokoPreferenceKeyClearButtonModeDefaultValue;
    }
    self.dismissOnOutsideTouch = [[self.preferences objectForKey:kKayokoPreferenceKeyDismissOnOutsideTouch] boolValue];
    self.playHapticFeedback = [[self.preferences objectForKey:kKayokoPreferenceKeyPlayHapticFeedback] boolValue];
    self.itemDetailsMode = [[self.preferences objectForKey:kKayokoPreferenceKeyItemDetailsMode] unsignedIntegerValue];
    if (self.itemDetailsMode != kKayokoItemDetailsModeOff && self.itemDetailsMode != kKayokoItemDetailsModeImagesOnly &&
        self.itemDetailsMode != kKayokoItemDetailsModeAll) {
        self.itemDetailsMode = kKayokoPreferenceKeyItemDetailsModeDefaultValue;
    }
    self.heightInPoints = [[self.preferences objectForKey:kKayokoPreferenceKeyHeightInPoints] doubleValue];
    self.overlayWindowLevelMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyOverlayWindowLevelMode] unsignedIntegerValue];
    if (self.overlayWindowLevelMode != kKayokoOverlayWindowLevelModeCustom &&
        self.overlayWindowLevelMode != kKayokoOverlayWindowLevelModeMaximum) {
        self.overlayWindowLevelMode = kKayokoPreferenceKeyOverlayWindowLevelModeDefaultValue;
    }

    CGFloat customOverlayWindowLevel =
        [[self.preferences objectForKey:kKayokoPreferenceKeyOverlayWindowLevel] doubleValue];
    if (!isfinite(customOverlayWindowLevel) ||
        customOverlayWindowLevel < kKayokoPreferenceKeyOverlayWindowLevelMinimumValue ||
        customOverlayWindowLevel > kKayokoPreferenceKeyOverlayWindowLevelMaximumValue) {
        customOverlayWindowLevel = kKayokoPreferenceKeyOverlayWindowLevelDefaultValue;
    }
    self.customOverlayWindowLevel = round(customOverlayWindowLevel);

    KayokoPasteboardManager *pasteboardManager = [KayokoPasteboardManager sharedInstance];
    if ([pasteboardManager maximumHistoryAmount] != self.maximumHistoryAmount) {
        [pasteboardManager setMaximumHistoryAmount:self.maximumHistoryAmount];
    }
    if ([pasteboardManager saveText] != self.saveText) {
        [pasteboardManager setSaveText:self.saveText];
    }
    if ([pasteboardManager saveImages] != self.saveImages) {
        [pasteboardManager setSaveImages:self.saveImages];
    }
    if ([pasteboardManager automaticallyPaste] != self.automaticallyPaste) {
        [pasteboardManager setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([pasteboardManager automaticPasteMode] != self.automaticPasteMode) {
        [pasteboardManager setAutomaticPasteMode:self.automaticPasteMode];
    }
    if ([pasteboardManager automaticPromotionMode] != self.automaticPromotionMode) {
        [pasteboardManager setAutomaticPromotionMode:self.automaticPromotionMode];
    }
    [self applyPreferencesToView];
}

- (void)loadHeightPreference {
    NSUserDefaults *heightPreferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [heightPreferences registerDefaults:@{
        kKayokoPreferenceKeyHeightInPoints : @(kKayokoPreferenceKeyHeightInPointsDefaultValue),
    }];
    self.heightInPoints = [[heightPreferences objectForKey:kKayokoPreferenceKeyHeightInPoints] doubleValue];
    if (self.pendingHeightPreferenceApply) {
        return;
    }

    self.pendingHeightPreferenceApply = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.pendingHeightPreferenceApply = NO;
      [self applyHeightPreferenceToViewApplyingWhenHidden:NO];
    });
}

#pragma mark - Device State

- (BOOL)readUILocked:(BOOL *)locked {
    Class<KayokoSBLockScreenManagerClass> managerClass =
        (Class<KayokoSBLockScreenManagerClass>)NSClassFromString(@"SBLockScreenManager");
    if (![managerClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }

    SBLockScreenManager *manager = [managerClass sharedInstance];
    if (![manager respondsToSelector:@selector(isUILocked)]) {
        return NO;
    }

    if (locked) {
        *locked = [manager isUILocked];
    }
    return YES;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromSceneSettings:(UIApplicationSceneSettings *)settings {
    if (![settings respondsToSelector:@selector(userInterfaceStyle)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    NSInteger style = (NSInteger)[settings userInterfaceStyle];
    if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
        return (UIUserInterfaceStyle)style;
    }
    return UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearance:(NSInteger)keyboardAppearance {
    switch ((UIKeyboardAppearance)keyboardAppearance) {
    case UIKeyboardAppearanceDark:
        return UIUserInterfaceStyleDark;
    case UIKeyboardAppearanceLight:
        return UIUserInterfaceStyleLight;
    default:
        return UIUserInterfaceStyleUnspecified;
    }
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearanceProvider:
    (NSObject<KayokoKeyboardAppearanceProviding> *)provider {
    if (![provider respondsToSelector:@selector(keyboardAppearance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    return [self userInterfaceStyleFromKeyboardAppearance:[provider keyboardAppearance]];
}

- (UIUserInterfaceStyle)currentSpringBoardKeyboardUserInterfaceStyle {
    Class<KayokoUIKeyboardImplClass> keyboardImplClass =
        (Class<KayokoUIKeyboardImplClass>)NSClassFromString(@"UIKeyboardImpl");
    if (![keyboardImplClass respondsToSelector:@selector(activeInstance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    UIKeyboardImpl *keyboardImpl = [keyboardImplClass activeInstance];
    if ([keyboardImpl respondsToSelector:@selector(textInputTraits)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl textInputTraits]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([keyboardImpl respondsToSelector:@selector(inputDelegate)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl inputDelegate]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    return [keyboardImpl respondsToSelector:@selector(delegate)]
               ? [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl delegate]]
               : UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)currentKeyboardHostUserInterfaceStyle {
    KayokoKeyboardHostResolver *resolver = [KayokoKeyboardHostResolver sharedResolver];
    FBScene *hostScene = [resolver currentKeyboardHostScene];
    if ([resolver sceneIsHostedBySpringBoard:hostScene]) {
        UIUserInterfaceStyle style = [self currentSpringBoardKeyboardUserInterfaceStyle];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([resolver sceneIsSpotlightScene:hostScene]) {
        return UIUserInterfaceStyleDark;
    }

    return [self userInterfaceStyleFromSceneSettings:[resolver settingsForScene:hostScene]];
}

- (void)applyKeyboardHostUserInterfaceStyle:(UIUserInterfaceStyle)style {
    if (!self.mainViewController || (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark)) {
        return;
    }

    [self.mainViewController applyUserInterfaceStyle:style];
}

- (void)applyCurrentKeyboardHostUserInterfaceStyle {
    [self applyKeyboardHostUserInterfaceStyle:[self currentKeyboardHostUserInterfaceStyle]];
}

- (BOOL)sceneIsCurrentKeyboardHostScene:(FBScene *)scene {
    return [[KayokoKeyboardHostResolver sharedResolver] sceneIsCurrentKeyboardHostScene:scene];
}

- (void)handleScene:(FBScene *)scene didUpdateSettings:(UIApplicationSceneSettings *)settings {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleScene:scene didUpdateSettings:settings];
        });
        return;
    }

    if (![self panelVisible] || ![self sceneIsCurrentKeyboardHostScene:scene]) {
        return;
    }

    KayokoKeyboardHostResolver *resolver = [KayokoKeyboardHostResolver sharedResolver];
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    if ([resolver sceneIsHostedBySpringBoard:scene]) {
        style = [self currentSpringBoardKeyboardUserInterfaceStyle];
    }
    if (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark) {
        style = [resolver sceneIsSpotlightScene:scene] ? UIUserInterfaceStyleDark
                                                       : [self userInterfaceStyleFromSceneSettings:settings];
    }
    [self applyKeyboardHostUserInterfaceStyle:style];
}

- (BOOL)frontmostAppIsLandscape {
    return UIInterfaceOrientationIsLandscape([self frontmostAppInterfaceOrientation]);
}

- (BOOL)deviceUsesCompactLandscapePresentation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone && [self frontmostAppIsLandscape];
}

- (KayokoPanelPresentationMode)currentPresentationMode {
    return [self deviceUsesCompactLandscapePresentation] ? KayokoPanelPresentationModeCompactLandscapeFullscreen
                                                         : KayokoPanelPresentationModePortraitDrawer;
}


- (void)startLockStateObserver {
    if (self.lockStateToken != 0) {
        return;
    }

    int status = notify_register_dispatch("com.apple.springboard.lockstate", &_lockStateToken,
                                          dispatch_get_main_queue(), ^(int token) {
                                            (void)token;
                                            [self handleLockStateNotification];
                                          });
    if (status != NOTIFY_STATUS_OK) {
        HBLogDebug(@"Kayoko: Unable to observe SpringBoard lock state: %d", status);
        self.lockStateToken = 0;
    }
}

- (void)startMemoryWarningObserver {
    if (self.observingMemoryWarnings) {
        return;
    }

    self.observingMemoryWarnings = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
}

- (void)handleMemoryWarning:(NSNotification *)notification {
    (void)notification;
    if (self.mainViewController) {
        [[KayokoPasteboardManager sharedInstance] resetThumbnailMemoryCache];
    }
    if ([self panelVisible] || (self.overlayWindow && ![self.overlayWindow isHidden])) {
        return;
    }

    [self tearDownOverlayWindowHost];
    [self.portraitOutsideDismissOverlayView removeFromSuperview];
    self.portraitOutsideDismissOverlayView = nil;
    [self.mainViewController setDelegate:nil];
    self.mainViewController = nil;
    self.overlayWindow = nil;
}

- (void)handleLockStateNotification {
    BOOL locked = NO;
    if (![self readUILocked:&locked] || !locked) {
        return;
    }

    [self hideWordSelectionPrompt];
    [self hideImmediately];
}

#pragma mark - Feedback

- (void)playSuccessHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)playFailureHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1521);
    }
}

- (void)playPasteFeedback {
    NSTimeInterval now = CACurrentMediaTime();
    if (fabs(now - self.lastPasteFeedbackOccurred) < kKayokoMinimumFeedbackInterval) {
        return;
    }
    self.lastPasteFeedbackOccurred = now;
    [self playSuccessHapticFeedbackIfNeeded];
}

#pragma mark - Pasteboard

- (void)hideWordSelectionPrompt {
    if (self.wordSelectionPromptHideBlock) {
        dispatch_block_cancel(self.wordSelectionPromptHideBlock);
        self.wordSelectionPromptHideBlock = nil;
    }
    [self.wordSelectionPromptWindow setHidden:YES];
    self.wordSelectionPromptWindow = nil;
    self.wordSelectionPromptItem = nil;
}

- (void)handleWordSelectionPromptPressed {
    KayokoPasteboardItem *item = self.wordSelectionPromptItem;
    [self hideWordSelectionPrompt];
    if (!item) {
        return;
    }
    [self createMainViewControllerIfNeeded];
    [self.mainViewController presentWordSelectionForItemWhenShown:item];
    [self show];
}

- (void)showWordSelectionPromptForItem:(KayokoPasteboardItem *)item {
    if (!item || [[item imageName] length] > 0 || ![[item content] length] || [self panelVisible]) {
        return;
    }
    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        return;
    }
    UIWindowScene *scene = [self.statusBarWindow windowScene];
    if (!scene) {
        return;
    }
    [self hideWordSelectionPrompt];
    KayokoWordSelectionPromptWindow *window = [[KayokoWordSelectionPromptWindow alloc] initWithWindowScene:scene];
    [window setFrame:[[UIScreen mainScreen] bounds]];
    [window setWindowLevel:[self overlayWindowLevel] + 1];
    [window setBackgroundColor:[UIColor clearColor]];
    UIViewController *controller = [[UIViewController alloc] init];
    [controller.view setBackgroundColor:[UIColor clearColor]];
    [window setRootViewController:controller];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"✨ 分词" forState:UIControlStateNormal];
    [button.titleLabel setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setBackgroundColor:[UIColor systemIndigoColor]];
    [button.layer setCornerRadius:22];
    [button addTarget:self action:@selector(handleWordSelectionPromptPressed) forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:button];
    [button setTranslatesAutoresizingMaskIntoConstraints:NO];
    [NSLayoutConstraint activateConstraints:@[
        [[button trailingAnchor] constraintEqualToAnchor:[controller.view safeAreaLayoutGuide].trailingAnchor constant:-16],
        [[button centerYAnchor] constraintEqualToAnchor:[controller.view centerYAnchor]],
        [[button widthAnchor] constraintEqualToConstant:92],
        [[button heightAnchor] constraintEqualToConstant:44],
    ]];
    window.interactiveView = button;
    self.wordSelectionPromptWindow = window;
    self.wordSelectionPromptItem = item;
    [window setHidden:NO];

    __weak typeof(self) weakSelf = self;
    dispatch_block_t hideBlock = dispatch_block_create(0, ^{ [weakSelf hideWordSelectionPrompt]; });
    self.wordSelectionPromptHideBlock = hideBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), hideBlock);
}

- (void)markPasteWillStart {
    [self.pasteSuppressionState beginWithExpirationDelay:kKayokoPasteSuppressionExpirationDelay];
}

- (void)capturePasteboardChange {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self capturePasteboardChangeNow];
    });
}

- (void)capturePasteboardChangeNow {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] pullPasteboardChangesWithCompletion:^(BOOL didSaveAnyItem) {
      if ([self.pasteSuppressionState consumeIfActive]) {
          return;
      }
      if (!didSaveAnyItem) {
          return;
      }

      [self showWordSelectionPromptForItem:[[KayokoPasteboardManager sharedInstance] getLatestHistoryItem]];

      NSTimeInterval now = CACurrentMediaTime();
      if (fabs(now - self.lastCopyFeedbackOccurred) < kKayokoMinimumFeedbackInterval) {
          return;
      }
      self.lastCopyFeedbackOccurred = now;
      [self playSuccessHapticFeedbackIfNeeded];
    }];
}

#pragma mark - Visibility

- (void)show {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [self hideWordSelectionPrompt];

    [self createMainViewControllerIfNeeded];
    if (!self.mainViewController || ![self.mainViewController isHidden]) {
        return;
    }

    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    KayokoPanelPresentationMode presentationMode = [self currentPresentationMode];
    if (![self preparePanelHostForPresentationMode:presentationMode]) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }


    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
    [self.mainViewController applyUserInterfaceStyle:UIUserInterfaceStyleUnspecified];
    [self applyCurrentKeyboardHostUserInterfaceStyle];

    [self.mainViewController show];

}

- (void)hideWithAnimationStyle:(KayokoPanelHideAnimationStyle)animationStyle {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithAnimationStyle:animationStyle completion:nil];
    }
}

- (void)hideForExternalRequest {
    if (!self.mainViewController || [self.mainViewController isHidden]) {
        return;
    }

    [self.mainViewController hideForExternalRequestWithAnimationStyle:KayokoPanelHideAnimationStyleDefault
                                                           completion:nil];
}

- (void)hide {
    [self hideWithAnimationStyle:KayokoPanelHideAnimationStyleDefault];
}

- (void)hideWithStandardDismissAnimation {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithStandardDismissAnimation];
    }
}

- (void)hideForRotation {
    [self hideWithAnimationStyle:KayokoPanelHideAnimationStyleFade];
}

- (void)hideImmediately {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideImmediately];
    }
}

- (void)reloadHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleHistoryChanged];
        });
    }
}

- (void)handleApplicationMetadataChanged {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleApplicationMetadataChanged];
        });
    }
}

- (void)checkpointHistoryDatabase {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] checkpointHistoryDatabase];
}

- (void)prepareForPackageMaintenance {
    [self setPackageMaintenanceMode:YES];
    [self hideWordSelectionPrompt];
    [[KayokoPasteboardManager sharedInstance] enterMaintenanceModeUntilProcessExit];
    [self hideImmediately];
}

- (void)resetThumbnailMemoryCache {
    [[KayokoPasteboardManager sharedInstance] resetThumbnailMemoryCache];
}

- (void)clearFavorites {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kKayokoHistoryKeyFavorites
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

- (void)clearHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kKayokoHistoryKeyHistory
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

@end
