//
//  KayokoWordSelectionView.m
//  Kayoko
//

#import "KayokoWordSelectionView.h"
#import "KayokoEdgeFadingScrollView.h"
#import "KayokoHeaderView.h"
#import "KayokoMainView.h"
#import "KayokoWordSelectionTokenizer.h"
#import "KayokoWordTokenView.h"

static CGFloat const kKayokoWordSelectionHorizontalInset = 20;
static CGFloat const kKayokoWordSelectionVerticalFadeHeight = 20;
static CGFloat const kKayokoWordSelectionTopInset = 8;
static CGFloat const kKayokoWordSelectionTokenSpacing = 2;
static CGFloat const kKayokoWordSelectionLineSpacing = 9;
static CGFloat const kKayokoWordSelectionTokenHeight = 34;
static CGFloat const kKayokoWordSelectionTokenHorizontalInset = 3;
static CGFloat const kKayokoWordSelectionTokenCornerRadius = 4;
static CGFloat const kKayokoWordSelectionTokenBorderWidth = 0.5;

NS_ASSUME_NONNULL_BEGIN

@interface KayokoWordSelectionView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
#pragma mark - Views

@property(nonatomic, strong) KayokoEdgeFadingScrollView *scrollView;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong, readwrite) KayokoHeaderView *headerView;
@property(nonatomic, strong, readwrite) UIView *transitionContentView;

#pragma mark - Tokens

@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *tokens;
@property(nonatomic, strong) NSMutableArray<KayokoWordTokenView *> *tokenButtons;
@property(nonatomic, strong) NSMutableIndexSet *selectedTokenIndexes;
@property(nonatomic, strong) NSMutableIndexSet *selectionGestureOriginalIndexes;
@property(nonatomic, copy, nullable) NSString *originalText;

#pragma mark - Gestures

@property(nonatomic, weak) UIPanGestureRecognizer *selectionGestureRecognizer;

#pragma mark - State

@property(nonatomic, assign, readwrite) BOOL hasCustomSelection;
@property(nonatomic, assign) NSUInteger selectionAnchorIndex;
@property(nonatomic, assign) BOOL selectionGestureSelectsTokens;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoWordSelectionView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setClipsToBounds:YES];
        [self setTokens:[[NSMutableArray alloc] init]];
        [self setTokenButtons:[[NSMutableArray alloc] init]];
        [self setSelectedTokenIndexes:[[NSMutableIndexSet alloc] init]];
        [self setSelectionGestureOriginalIndexes:[[NSMutableIndexSet alloc] init]];
        [self setSelectionAnchorIndex:NSNotFound];

        [self setHeaderView:[[KayokoHeaderView alloc] initWithTitle:@""]];
        [self addSubview:[self headerView]];

        [[self headerView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[ [[[self headerView] heightAnchor]
                                                    constraintEqualToConstant:[KayokoHeaderView preferredHeight]] ]];

        [self setTransitionContentView:[[UIView alloc] init]];
        [self insertSubview:[self transitionContentView] belowSubview:[self headerView]];
        [[self transitionContentView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self transitionContentView] topAnchor] constraintEqualToAnchor:[self topAnchor]],
            [[[self transitionContentView] leadingAnchor] constraintEqualToAnchor:[self leadingAnchor]],
            [[[self transitionContentView] trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]],
            [[[self transitionContentView] bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]]
        ]];

        [self setScrollView:[[KayokoEdgeFadingScrollView alloc] init]];
        [[self scrollView] setEdgeFadeAxis:KayokoEdgeFadeAxisVertical];
        [[self scrollView] setEdgeFadeWidth:kKayokoWordSelectionVerticalFadeHeight];
        [[self scrollView] setEdgeFadeEnabled:YES];
        [[self scrollView] setAlwaysBounceVertical:NO];
        [[self scrollView] setAutomaticallyAdjustsScrollIndicatorInsets:NO];
        [[self scrollView] setBackgroundColor:[UIColor clearColor]];
        [[self scrollView] setDelegate:self];
        [[self transitionContentView] addSubview:[self scrollView]];

        [[self scrollView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self scrollView] topAnchor] constraintEqualToAnchor:[[self headerView] bottomAnchor]
                                                          constant:kKayokoHeaderContentSpacing],
            [[[self scrollView] leadingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] leadingAnchor]],
            [[[self scrollView] trailingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] trailingAnchor]],
            [[[self scrollView] bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]]
        ]];

        [self setContentView:[[UIView alloc] init]];
        [[self scrollView] addSubview:[self contentView]];

        UITapGestureRecognizer *tapGesture =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        [tapGesture setDelegate:self];
        [[self contentView] addGestureRecognizer:tapGesture];

        UIPanGestureRecognizer *selectionGesture =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSelectionGesture:)];
        [selectionGesture setDelegate:self];
        [self setSelectionGestureRecognizer:selectionGesture];
        [[self contentView] addGestureRecognizer:selectionGesture];

        UILongPressGestureRecognizer *refineGesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleRefineGesture:)];
        [refineGesture setDelegate:self];
        [[self contentView] addGestureRecognizer:refineGesture];

    }

    return self;
}

#pragma mark - Content

- (void)setText:(NSString *)text {
    [self reset];
    [self setOriginalText:[text copy]];

    NSArray<NSDictionary<NSString *, id> *> *tokens = [KayokoWordSelectionTokenizer tokensForText:text];
    [[self tokens] addObjectsFromArray:tokens];

    [self rebuildTokenButtons];

    [self updateButtonStyles];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
    [self setNeedsLayout];
}

- (void)rebuildTokenButtons {
    for (KayokoWordTokenView *button in [self tokenButtons]) {
        [button removeFromSuperview];
    }
    [[self tokenButtons] removeAllObjects];

    for (NSUInteger index = 0; index < [[self tokens] count]; index++) {
        KayokoWordTokenView *button = [[KayokoWordTokenView alloc] initWithFrame:CGRectZero];
        NSDictionary<NSString *, id> *token = [self tokens][index];
        [button setTag:index];
        [button setTitle:token[@"text"] forState:UIControlStateNormal];
        [[button titleLabel] setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
        [[button titleLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [button setKayokoContentInsets:UIEdgeInsetsMake(0, kKayokoWordSelectionTokenHorizontalInset, 0,
                                                        kKayokoWordSelectionTokenHorizontalInset)];
        [button setUserInteractionEnabled:NO];
        [[button layer] setCornerRadius:kKayokoWordSelectionTokenCornerRadius];
        [[button layer] setBorderWidth:kKayokoWordSelectionTokenBorderWidth];
        [[self contentView] addSubview:button];
        [[self tokenButtons] addObject:button];
    }
}

- (void)reset {
    for (KayokoWordTokenView *button in [self tokenButtons]) {
        [button removeFromSuperview];
    }

    [[self tokenButtons] removeAllObjects];
    [[self tokens] removeAllObjects];
    [[self selectedTokenIndexes] removeAllIndexes];
    [[self selectionGestureOriginalIndexes] removeAllIndexes];
    [self setOriginalText:nil];
    [self setHasCustomSelection:NO];
    [self setSelectionAnchorIndex:NSNotFound];
    [[self scrollView] setContentOffset:CGPointZero];
    [[self scrollView] setContentSize:CGSizeZero];
}

- (void)scrollToTopAnimated:(BOOL)animated {
    CGPoint contentOffset = [[self scrollView] contentOffset];
    contentOffset.y = -[[self scrollView] adjustedContentInset].top;
    [[self scrollView] setContentOffset:contentOffset animated:animated];
}

- (void)setKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    keyboardBottomInset = MAX(keyboardBottomInset, 0);
    if (_keyboardBottomInset == keyboardBottomInset) {
        return;
    }

    _keyboardBottomInset = keyboardBottomInset;
    [self updateScrollInsets];
    [self setNeedsLayout];
}

- (void)requireSelectionGestureRecognizerToFailGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer) {
        [[self selectionGestureRecognizer] requireGestureRecognizerToFail:gestureRecognizer];
    }
}

- (CGFloat)safeAreaBottomInsetForScrollContent {
    UIView *view = self;
    while (view) {
        if ([view isKindOfClass:[KayokoMainView class]]) {
            return [(KayokoMainView *)view safeAreaBottomInsetForContentView:self];
        }
        view = [view superview];
    }

    return MAX([self safeAreaInsets].bottom, 0);
}

- (CGFloat)scrollBottomInset {
    if ([self keyboardBottomInset] > 0) {
        return [self keyboardBottomInset];
    }
    return [self safeAreaBottomInsetForScrollContent];
}

- (void)updateScrollInsets {
    CGFloat bottomInset = [self scrollBottomInset];

    UIEdgeInsets contentInset = [[self scrollView] contentInset];
    contentInset.bottom = bottomInset;
    [[self scrollView] setContentInset:contentInset];

    UIEdgeInsets indicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    [[self scrollView] setVerticalScrollIndicatorInsets:indicatorInsets];
    [[self scrollView] setEdgeFadeInsets:UIEdgeInsetsMake(0, 0, [self keyboardBottomInset], 0)];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat scrollWidth = CGRectGetWidth([[self scrollView] bounds]);
    CGFloat scrollHeight = CGRectGetHeight([[self scrollView] bounds]);
    CGFloat availableWidth = MAX(scrollWidth - kKayokoWordSelectionHorizontalInset * 2, 1);
    CGFloat x = kKayokoWordSelectionHorizontalInset;
    CGFloat y = kKayokoWordSelectionTopInset;

    for (NSUInteger index = 0; index < [[self tokenButtons] count]; index++) {
        KayokoWordTokenView *button = [self tokenButtons][index];
        CGSize size = [button sizeThatFits:CGSizeMake(availableWidth, kKayokoWordSelectionTokenHeight)];
        CGFloat buttonWidth = MIN(MAX(ceil(size.width), kKayokoWordSelectionTokenHeight), availableWidth);

        if (x > kKayokoWordSelectionHorizontalInset &&
            x + buttonWidth > kKayokoWordSelectionHorizontalInset + availableWidth) {
            x = kKayokoWordSelectionHorizontalInset;
            y += kKayokoWordSelectionTokenHeight + kKayokoWordSelectionLineSpacing;
        }

        [button setFrame:CGRectMake(x, y, buttonWidth, kKayokoWordSelectionTokenHeight)];
        x += buttonWidth + kKayokoWordSelectionTokenSpacing;

        if ([self tokens][index][@"lineBreakAfter"] && index + 1 < [[self tokenButtons] count]) {
            x = kKayokoWordSelectionHorizontalInset;
            y += kKayokoWordSelectionTokenHeight + kKayokoWordSelectionLineSpacing;
        }
    }

    CGFloat contentHeight = [[self tokenButtons] count] > 0
                                ? y + kKayokoWordSelectionTokenHeight + kKayokoWordSelectionLineSpacing
                                : kKayokoWordSelectionTopInset;
    [[self contentView] setFrame:CGRectMake(0, 0, scrollWidth, contentHeight)];
    [[self scrollView] setContentSize:CGSizeMake(scrollWidth, contentHeight)];

    BOOL scrollable = contentHeight > scrollHeight + 0.5;
    [self updateScrollInsets];
    scrollable = contentHeight + [[self scrollView] contentInset].bottom > scrollHeight + 0.5;
    [[self scrollView] setBounces:scrollable];
    [[self scrollView] setAlwaysBounceVertical:scrollable];
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self updateScrollInsets];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateButtonStyles];
}

#pragma mark - Gestures

- (void)handleTapGesture:(UITapGestureRecognizer *)gesture {
    NSUInteger tokenIndex = [self tokenIndexAtPoint:[gesture locationInView:[self contentView]]];
    if (tokenIndex != NSNotFound) {
        [self toggleTokenAtIndex:tokenIndex];
    }
}

- (void)handleSelectionGesture:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:[self contentView]];
    NSUInteger tokenIndex = [self tokenIndexForSelectionLocation:location];

    if ([gesture state] == UIGestureRecognizerStateBegan) {
        if (tokenIndex == NSNotFound) {
            return;
        }

        [self setSelectionAnchorIndex:tokenIndex];
        [self setSelectionGestureSelectsTokens:![[self selectedTokenIndexes] containsIndex:tokenIndex]];
        [self setSelectionGestureOriginalIndexes:[[self selectedTokenIndexes] mutableCopy]];
        [self setHasCustomSelection:YES];
        [[self scrollView] setScrollEnabled:NO];
        return;
    }

    if ([gesture state] == UIGestureRecognizerStateChanged && tokenIndex != NSNotFound) {
        [self applySelectionGestureThroughIndex:tokenIndex];
    }

    if ([gesture state] == UIGestureRecognizerStateEnded || [gesture state] == UIGestureRecognizerStateCancelled ||
        [gesture state] == UIGestureRecognizerStateFailed) {
        [[self selectionGestureOriginalIndexes] removeAllIndexes];
        [self setSelectionAnchorIndex:NSNotFound];
        [[self scrollView] setScrollEnabled:YES];
    }
}

- (void)handleRefineGesture:(UILongPressGestureRecognizer *)gesture {
    if ([gesture state] != UIGestureRecognizerStateBegan) {
        return;
    }

    NSUInteger index = [self tokenIndexAtPoint:[gesture locationInView:[self contentView]]];
    if (![self canRefineTokenAtIndex:index]) {
        return;
    }

    NSDictionary<NSString *, id> *token = [self tokens][index];

    NSArray<NSDictionary<NSString *, id> *> *parts =
        [KayokoWordSelectionTokenizer characterTokensForText:[self originalText] inRange:[token[@"range"] rangeValue]];
    if ([parts count] < 2) {
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *replacement = [parts mutableCopy];
    if (token[@"lineBreakAfter"]) {
        NSMutableDictionary<NSString *, id> *last = [[replacement lastObject] mutableCopy];
        last[@"lineBreakAfter"] = token[@"lineBreakAfter"];
        replacement[[replacement count] - 1] = last;
    }

    BOOL wasSelected = [[self selectedTokenIndexes] containsIndex:index];
    NSUInteger addedCount = [replacement count] - 1;
    NSMutableIndexSet *selection = [[NSMutableIndexSet alloc] init];
    [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger selectedIndex, BOOL *stop) {
      if (selectedIndex < index) {
          [selection addIndex:selectedIndex];
      } else if (selectedIndex > index) {
          [selection addIndex:selectedIndex + addedCount];
      }
    }];
    if (wasSelected) {
        [selection addIndexesInRange:NSMakeRange(index, [replacement count])];
    }

    [[self tokens] replaceObjectsInRange:NSMakeRange(index, 1) withObjectsFromArray:replacement];
    [self rebuildTokenButtons];
    [self applySelectedTokenIndexes:selection];
    [self setHasCustomSelection:YES];
    [self updateButtonStyles];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
    [self setNeedsLayout];
}

- (BOOL)canRefineTokenAtIndex:(NSUInteger)index {
    if (index == NSNotFound || index >= [[self tokens] count]) {
        return NO;
    }
    NSString *text = [self tokens][index][@"text"];
    NSCharacterSet *asciiLettersAndNumbers =
        [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
    return [text length] > 1 && [text rangeOfCharacterFromSet:asciiLettersAndNumbers].location != NSNotFound;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint location = [gestureRecognizer locationInView:[self contentView]];

    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return [self tokenIndexAtPoint:location] != NSNotFound;
    }

    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return [self canRefineTokenAtIndex:[self tokenIndexAtPoint:location]];
    }

    if (![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }

    if ([self tokenIndexForSelectionLocation:location] == NSNotFound) {
        return NO;
    }

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
    if (fabs(velocity.y) > fabs(velocity.x) * 1.5) {
        return NO;
    }

    return YES;
}

#pragma mark - Token Selection

- (NSUInteger)tokenIndexAtPoint:(CGPoint)point {
    for (KayokoWordTokenView *button in [self tokenButtons]) {
        if (CGRectContainsPoint([button frame], point)) {
            return [button tag];
        }
    }

    return NSNotFound;
}

- (NSUInteger)tokenIndexForSelectionLocation:(CGPoint)point {
    for (KayokoWordTokenView *button in [self tokenButtons]) {
        CGRect frame =
            CGRectInset([button frame], -kKayokoWordSelectionTokenSpacing / 2, -kKayokoWordSelectionLineSpacing / 2);
        if (CGRectContainsPoint(frame, point)) {
            return [button tag];
        }
    }

    return NSNotFound;
}

- (void)toggleTokenAtIndex:(NSUInteger)index {
    [self setHasCustomSelection:YES];

    NSMutableIndexSet *updatedIndexes = [[self selectedTokenIndexes] mutableCopy];
    if ([[self selectedTokenIndexes] containsIndex:index]) {
        [updatedIndexes removeIndex:index];
    } else {
        [updatedIndexes addIndex:index];
    }

    [self applySelectedTokenIndexes:updatedIndexes];
    [self updateButtonStyles];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
}

- (BOOL)selectAllTokens {
    NSUInteger tokenCount = [[self tokens] count];
    if (tokenCount == 0) {
        return NO;
    }

    [self setHasCustomSelection:YES];
    NSIndexSet *allTokenIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tokenCount)];
    if (![self applySelectedTokenIndexes:allTokenIndexes]) {
        return NO;
    }

    [self updateButtonStyles];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
    return YES;
}

- (BOOL)clearSelectedTokens {
    if (![[self selectedTokenIndexes] count]) {
        return NO;
    }

    [self setHasCustomSelection:YES];
    if (![self applySelectedTokenIndexes:[NSIndexSet indexSet]]) {
        return NO;
    }

    [self updateButtonStyles];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
    return YES;
}

- (void)applySelectionGestureThroughIndex:(NSUInteger)index {
    if ([self selectionAnchorIndex] == NSNotFound) {
        return;
    }

    NSMutableIndexSet *updatedIndexes = [[self selectionGestureOriginalIndexes] mutableCopy];

    NSUInteger lowerBound = MIN([self selectionAnchorIndex], index);
    NSUInteger upperBound = MAX([self selectionAnchorIndex], index);
    NSRange range = NSMakeRange(lowerBound, upperBound - lowerBound + 1);

    if ([self selectionGestureSelectsTokens]) {
        [updatedIndexes addIndexesInRange:range];
    } else {
        [updatedIndexes removeIndexesInRange:range];
    }

    if (![self applySelectedTokenIndexes:updatedIndexes]) {
        return;
    }

    [self updateButtonStyles];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
}

- (BOOL)applySelectedTokenIndexes:(NSIndexSet *)updatedIndexes {
    if ([[self selectedTokenIndexes] isEqualToIndexSet:updatedIndexes]) {
        return NO;
    }

    [[self selectedTokenIndexes] removeAllIndexes];
    [[self selectedTokenIndexes] addIndexes:updatedIndexes];
    return YES;
}

#pragma mark - Styling

- (void)updateButtonStyles {
    UIColor *selectedTextColor = [KayokoWordSelectionView dynamicColorWithLightWhite:0
                                                                               alpha:0.88
                                                                           darkWhite:1
                                                                               alpha:0.92];
    UIColor *normalTextColor = [KayokoWordSelectionView dynamicColorWithLightWhite:0 alpha:0.58 darkWhite:1 alpha:0.62];
    UIColor *selectedBackgroundColor = [KayokoWordSelectionView dynamicColorWithLightWhite:0
                                                                                     alpha:0.08
                                                                                 darkWhite:1
                                                                                     alpha:0.12];
    UIColor *normalBackgroundColor = [KayokoWordSelectionView dynamicColorWithLightWhite:1
                                                                                   alpha:0.08
                                                                               darkWhite:1
                                                                                   alpha:0.035];
    UIColor *selectedBorderColor = [KayokoWordSelectionView dynamicColorWithLightWhite:0
                                                                                 alpha:0.20
                                                                             darkWhite:1
                                                                                 alpha:0.24];
    UIColor *normalBorderColor = [KayokoWordSelectionView dynamicColorWithLightWhite:0
                                                                               alpha:0.08
                                                                           darkWhite:1
                                                                               alpha:0.10];

    for (NSUInteger index = 0; index < [[self tokenButtons] count]; index++) {
        KayokoWordTokenView *button = [self tokenButtons][index];
        BOOL selected = [[self selectedTokenIndexes] containsIndex:index];
        [[button layer] setBorderWidth:kKayokoWordSelectionTokenBorderWidth];
        UIColor *textColor = selected ? selectedTextColor : normalTextColor;
        UIColor *backgroundColor = selected ? selectedBackgroundColor : normalBackgroundColor;
        [button setTitleColor:textColor forState:UIControlStateNormal];
        [button setBackgroundColor:backgroundColor];
        [[button layer] setBorderColor:(selected ? selectedBorderColor : normalBorderColor).CGColor];
    }
}

+ (UIColor *)dynamicColorWithLightWhite:(CGFloat)lightWhite
                                  alpha:(CGFloat)lightAlpha
                              darkWhite:(CGFloat)darkWhite
                                  alpha:(CGFloat)darkAlpha {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      BOOL dark = [traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark;
      return [UIColor colorWithWhite:(dark ? darkWhite : lightWhite) alpha:(dark ? darkAlpha : lightAlpha)];
    }];
}

- (BOOL)hasSelectedText {
    return [[self selectedTokenIndexes] count] > 0;
}

- (BOOL)hasTokens {
    return [[self tokens] count] > 0;
}

- (BOOL)hasAllTokensSelected {
    return [self hasTokens] && [[self selectedTokenIndexes] count] == [[self tokens] count];
}

- (NSString *)selectedText {
    NSMutableString *selectedText = [[NSMutableString alloc] init];
    __block NSUInteger previousTokenIndex = NSNotFound;
    __block NSRange previousRange = NSMakeRange(NSNotFound, 0);

    [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      NSDictionary<NSString *, id> *token = [self tokens][index];
      NSRange range = [token[@"range"] rangeValue];
      if ([selectedText length] > 0) {
          if (previousTokenIndex != NSNotFound && index == previousTokenIndex + 1 &&
              NSMaxRange(previousRange) <= range.location) {
              NSRange separatorRange = NSMakeRange(NSMaxRange(previousRange), range.location - NSMaxRange(previousRange));
              [selectedText appendString:[[self originalText] substringWithRange:separatorRange]];
          } else {
              [selectedText appendString:@" "];
          }
      }
      [selectedText appendString:token[@"text"]];
      previousTokenIndex = index;
      previousRange = range;
    }];
    return [selectedText copy];
}

@end
