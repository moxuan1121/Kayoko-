#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KayokoAnchoredMenuView : UIControl

@property(nonatomic, assign) CGFloat menuWidth;
@property(nonatomic, assign) BOOL centersTitles;
@property(nonatomic, assign) BOOL presentsBelowSource;
@property(nonatomic, assign) BOOL animatesDismissal;

- (void)addItemWithTitle:(NSString *)title
                   image:(nullable UIImage *)image
             destructive:(BOOL)destructive
                 handler:(dispatch_block_t)handler;
- (void)useBackgroundEffect:(UIBlurEffect *)effect tintColor:(UIColor *)tintColor;
- (void)presentFromView:(UIView *)sourceView inView:(UIView *)hostView;
- (void)trackGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
