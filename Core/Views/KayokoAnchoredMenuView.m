#import "KayokoAnchoredMenuView.h"

static NSInteger const kKayokoAnchoredMenuTag = 0x4B4D4E55;
static CGFloat const kKayokoAnchoredMenuWidth = 250.0;
static CGFloat const kKayokoAnchoredMenuRowHeight = 44.0;
static CGFloat const kKayokoAnchoredMenuMargin = 8.0;

@interface KayokoAnchoredMenuView ()
@property(nonatomic, strong) UIStackView *stackView;
@property(nonatomic, strong) NSMutableArray<dispatch_block_t> *handlers;
@end

@implementation KayokoAnchoredMenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.tag = kKayokoAnchoredMenuTag;
        self.backgroundColor = UIColor.clearColor;
        [self addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

        _handlers = [NSMutableArray array];
        _stackView = [[UIStackView alloc] init];
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.distribution = UIStackViewDistributionFillEqually;
        _stackView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _stackView.layer.cornerRadius = 14.0;
        _stackView.layer.cornerCurve = kCACornerCurveContinuous;
        _stackView.clipsToBounds = YES;
        _stackView.layer.shadowColor = UIColor.blackColor.CGColor;
        _stackView.layer.shadowOpacity = 0.18;
        _stackView.layer.shadowRadius = 12.0;
        _stackView.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:_stackView];
    }
    return self;
}

- (void)addItemWithTitle:(NSString *)title
                   image:(UIImage *)image
             destructive:(BOOL)destructive
                 handler:(dispatch_block_t)handler {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = self.handlers.count;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(0, 18, 0, 18);
    configuration.imagePadding = 12;
    configuration.baseForegroundColor = destructive ? UIColor.systemRedColor : UIColor.labelColor;
    button.configuration = configuration;
    button.titleLabel.font = [UIFont systemFontOfSize:17.0];
    [button setTitle:title forState:UIControlStateNormal];
    if (image) {
        [button setImage:image forState:UIControlStateNormal];
    }
    [button addTarget:self action:@selector(handleItem:) forControlEvents:UIControlEventTouchUpInside];
    [self.handlers addObject:[handler copy]];
    [self.stackView addArrangedSubview:button];
}

- (void)presentFromView:(UIView *)sourceView inView:(UIView *)hostView {
    [[hostView viewWithTag:kKayokoAnchoredMenuTag] removeFromSuperview];
    self.frame = hostView.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [hostView addSubview:self];

    CGRect sourceFrame = [sourceView convertRect:sourceView.bounds toView:hostView];
    CGFloat height = self.handlers.count * kKayokoAnchoredMenuRowHeight;
    CGFloat width = MIN(kKayokoAnchoredMenuWidth, CGRectGetWidth(hostView.bounds) - kKayokoAnchoredMenuMargin * 2.0);
    CGFloat x = MIN(MAX(CGRectGetMidX(sourceFrame) - width / 2.0, kKayokoAnchoredMenuMargin),
                    CGRectGetWidth(hostView.bounds) - width - kKayokoAnchoredMenuMargin);
    CGFloat y = CGRectGetMaxY(sourceFrame) + 6.0;
    if (y + height > CGRectGetHeight(hostView.bounds) - kKayokoAnchoredMenuMargin) {
        y = MAX(CGRectGetMinY(sourceFrame) - height - 6.0, kKayokoAnchoredMenuMargin);
    }
    self.stackView.frame = CGRectMake(x, y, width, height);
}

- (void)handleItem:(UIButton *)sender {
    dispatch_block_t handler = sender.tag < self.handlers.count ? self.handlers[sender.tag] : nil;
    [self dismiss];
    if (handler) {
        handler();
    }
}

- (void)dismiss {
    [self removeFromSuperview];
}

@end
