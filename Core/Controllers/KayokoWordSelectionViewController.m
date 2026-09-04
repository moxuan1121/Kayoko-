//
//  KayokoWordSelectionViewController.m
//  Kayoko
//

#import "KayokoWordSelectionViewController.h"

#import "KayokoHeaderButtonStyle.h"
#import "KayokoHeaderView.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoSystemTranslationPresenter.h"
#import "KayokoWordSelectionView.h"

// Word selection creates one button per token; CJK text can approach one token per character.
static NSUInteger const kKayokoWordSelectionMaximumTextLength = 5000;

static NSString *kayokoWordSelectionTextByTrimmingBoundaryNewlines(NSString *text) {
    return [(text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NS_ASSUME_NONNULL_BEGIN

@interface KayokoWordSelectionViewController ()
#pragma mark - Views

@property(nonatomic, strong, readwrite) KayokoWordSelectionView *wordSelectionView;

#pragma mark - State

@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, nullable, readwrite) NSString *sourceHistoryKey;
@property(nonatomic, strong, nullable, readwrite) KayokoPasteboardItem *sourceItem;
@property(nonatomic, strong) KayokoSystemTranslationPresenter *systemTranslationPresenter;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries;
- (void)openSearchEntry:(nullable NSDictionary<NSString *, NSString *> *)entry;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoWordSelectionViewController

#pragma mark - Lifecycle

- (instancetype)initWithName:(NSString *)name {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _name = [name copy];
        _wordSelectionView = [[KayokoWordSelectionView alloc] init];
        [[_wordSelectionView headerView] setTitleText:name];
        [_wordSelectionView setHidden:YES];
        _systemTranslationPresenter = [[KayokoSystemTranslationPresenter alloc] init];
        [[[_wordSelectionView headerView] selectionActionButton]
                   addTarget:self
                      action:@selector(handleSelectionActionButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] translationButton]
                   addTarget:self
                      action:@selector(handleTranslationButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] searchButton]
                   addTarget:self
                      action:@selector(handleSearchButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *searchLongPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleSearchButtonLongPress:)];
        [[[_wordSelectionView headerView] searchButton] addGestureRecognizer:searchLongPress];
        [self setView:_wordSelectionView];

        __weak typeof(self) weakSelf = self;
        [_wordSelectionView setSelectionChangedHandler:^{
          [weakSelf updateActionButtonState];
          [weakSelf updateSelectionActionButtonStates];
          [weakSelf updateTranslationButtonState];
          [weakSelf updateSearchButtonState];
          if ([weakSelf selectionChangedHandler]) {
              [weakSelf selectionChangedHandler]();
          }
        }];
    }
    return self;
}

#pragma mark - Public State

- (NSString *)selectedText {
    return [[self wordSelectionView] selectedText];
}

- (BOOL)isShowingWordSelection {
    return ![[self wordSelectionView] isHidden];
}

- (BOOL)hasSelectedText {
    return [[self wordSelectionView] hasSelectedText];
}

- (BOOL)canShowText:(NSString *)text {
    return [text length] <= kKayokoWordSelectionMaximumTextLength;
}

- (void)scrollToTopAnimated:(BOOL)animated {
    [[self wordSelectionView] scrollToTopAnimated:animated];
}

#pragma mark - Presentation

- (void)showWordSelectionWithItem:(KayokoPasteboardItem *)item
                 sourceHistoryKey:(NSString *)sourceHistoryKey
               automaticallyPaste:(BOOL)automaticallyPaste {
    [self setSourceItem:item];
    [self setSourceHistoryKey:sourceHistoryKey];

    NSString *text = kayokoWordSelectionTextByTrimmingBoundaryNewlines([item content]);
    [[self wordSelectionView] setText:text];
    [[self wordSelectionView] setHidden:NO];

    KayokoHeaderView *headerView = [[self wordSelectionView] headerView];
    [headerView setHidden:NO];
    // This transient screen shows a title + back button; the clipboard/favorites switcher is
    // meaningless here.
    [headerView setHistorySwitcherVisible:NO animated:NO];
    [headerView setTitleText:[self name]];
    [headerView updateStyleForButton:[headerView leadingButton]
                       withImageName:@"arrowshape.turn.up.backward"
                           imageSize:kKayokoFavoritesButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView trailingButton]
                       withImageName:(automaticallyPaste ? @"doc.on.clipboard" : @"doc.on.doc.fill")imageSize
                                    :kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView selectionActionButton] setHidden:NO];
    NSString *translationImageName = [UIImage systemImageNamed:@"character.book.closed"] ? @"character.book.closed" : @"globe";
    [headerView updateStyleForButton:[headerView translationButton]
                       withImageName:translationImageName
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    NSArray *searchEntries = [self searchEntries];
    [headerView updateStyleForButton:[headerView searchButton]
                       withImageName:@"magnifyingglass"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView searchButton] setHidden:[searchEntries count] == 0];
    [[headerView searchButton] setAccessibilityLabel:@"搜索"];
    [[headerView leadingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Back"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [[headerView trailingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle]
                                  localizedStringForKey:(automaticallyPaste ? @"Paste" : @"Copy")
                                                  value:nil
                                                  table:@"Tweak"]];
    [self updateActionButtonState];
    [self updateSelectionActionButtonStates];
    [self updateTranslationButtonState];
    [self updateSearchButtonState];
}

#pragma mark - Dismissal

- (void)hideWordSelection {
    [self resetWordSelectionState];
}

#pragma mark - Actions

- (void)handleActionButtonWithAutomaticallyPaste:(BOOL)automaticallyPaste {
    KayokoPasteboardItem *sourceItem = [self sourceItem];
    if (!sourceItem || ![self isShowingWordSelection] || ![self hasSelectedText]) {
        return;
    }

    NSString *text = [self selectedText];
    KayokoPasteboardItem *selectedItem =
        [[KayokoPasteboardItem alloc] initWithBundleIdentifier:[sourceItem bundleIdentifier]
                                                    andContent:text
                                                withImageNamed:@""];
    NSString *historyKey = [self sourceHistoryKey] ?: kKayokoHistoryKeyHistory;
    if (automaticallyPaste) {
        [[KayokoPasteboardManager sharedInstance] writePasteboardItem:selectedItem
                                                    sourceHistoryItem:sourceItem
                                                   fromHistoryWithKey:historyKey
                                                 allowsAutomaticPaste:YES];
    } else {
        KayokoPasteboardManager *pasteboardManager = [KayokoPasteboardManager sharedInstance];
        if ([pasteboardManager copyPasteboardItemToPasteboard:selectedItem]) {
            [pasteboardManager addPasteboardItem:selectedItem toHistoryWithKey:kKayokoHistoryKeyHistory];
        }
    }

    [[self delegate] wordSelectionViewController:self didRequestHideContainerAfterDirectPaste:automaticallyPaste];
    [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)handleSelectionActionButtonPressed {
    KayokoWordSelectionView *wordSelectionView = [self wordSelectionView];
    BOOL didChange = [wordSelectionView hasAllTokensSelected] ? [wordSelectionView clearSelectedTokens]
                                                               : [wordSelectionView selectAllTokens];
    if (didChange) {
        [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    }
}

- (void)handleTranslationButtonPressed {
    if (![self hasSelectedText]) {
        return;
    }

    if ([[self systemTranslationPresenter] presentTranslationForText:[self selectedText] fromController:self]) {
        [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [preferences synchronize];
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSDictionary *storedEntry in [preferences arrayForKey:kKayokoPreferenceKeySearchEngines]) {
        NSString *name = [storedEntry[@"name"] isKindOfClass:[NSString class]] ? storedEntry[@"name"] : nil;
        NSString *engine = [storedEntry[@"engine"] isKindOfClass:[NSString class]] ? storedEntry[@"engine"] : nil;
        if ([name length] && [engine length]) {
            [entries addObject:@{ @"name" : name, @"url" : engine }];
        }
    }
    return entries;
}

- (void)openSearchEntry:(nullable NSDictionary<NSString *, NSString *> *)entry {
    NSString *text = [self selectedText];
    if (![text length] || !entry) {
        return;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encodedText = [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    NSString *urlString = [entry[@"url"] stringByReplacingOccurrencesOfString:@"%@" withString:encodedText];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        [[self delegate] wordSelectionViewController:self didRequestHideContainerAfterDirectPaste:NO];
    }
}

- (void)handleSearchButtonPressed {
    [self openSearchEntry:[[self searchEntries] firstObject]];
}

- (void)handleSearchButtonLongPress:(UILongPressGestureRecognizer *)gesture {
    if ([gesture state] != UIGestureRecognizerStateBegan || ![self hasSelectedText]) {
        return;
    }
    NSArray<NSDictionary<NSString *, NSString *> *> *entries = [self searchEntries];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"搜索"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    for (NSDictionary<NSString *, NSString *> *entry in entries) {
        [sheet addAction:[UIAlertAction actionWithTitle:entry[@"name"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
          [self openSearchEntry:entry];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - State

- (void)resetWordSelectionState {
    [[self systemTranslationPresenter] dismissTranslationAnimated:NO];
    [[[[self wordSelectionView] headerView] translationButton] setHidden:YES];
    [[[[self wordSelectionView] headerView] searchButton] setHidden:YES];
    [[self wordSelectionView] setHidden:YES];
    [[self wordSelectionView] reset];
    [self setSourceItem:nil];
    [self setSourceHistoryKey:nil];
}

#pragma mark - Header

- (void)updateActionButtonState {
    BOOL enabled = [self hasSelectedText];
    UIButton *actionButton = [[[self wordSelectionView] headerView] trailingButton];
    [actionButton setEnabled:enabled];
    [actionButton setAlpha:enabled ? 1.0 : 0.35];
}

- (void)updateSearchButtonState {
    UIButton *button = [[[self wordSelectionView] headerView] searchButton];
    BOOL enabled = [self hasSelectedText];
    [button setEnabled:enabled];
    [button setAlpha:enabled ? 1.0 : 0.35];
}

- (void)updateSelectionActionButtonStates {
    KayokoWordSelectionView *wordSelectionView = [self wordSelectionView];
    UIButton *selectionActionButton = [[wordSelectionView headerView] selectionActionButton];
    BOOL hasAllTokensSelected = [wordSelectionView hasAllTokensSelected];
    BOOL enabled = [wordSelectionView hasTokens];
    NSString *imageName = hasAllTokensSelected ? @"xmark.circle" : @"checkmark.circle";
    NSString *accessibilityKey = hasAllTokensSelected ? @"Clear Selection" : @"Select All";

    [[wordSelectionView headerView] updateStyleForButton:selectionActionButton
                                             withImageName:imageName
                                                 imageSize:kKayokoBackButtonImageSize
                                                 tintColor:[UIColor labelColor]];
    [selectionActionButton setEnabled:enabled];
    [selectionActionButton setAlpha:enabled ? 1.0 : 0.35];
    [selectionActionButton
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:accessibilityKey
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
}

- (void)updateTranslationButtonState {
    UIButton *translationButton = [[[self wordSelectionView] headerView] translationButton];
    BOOL available = [[self systemTranslationPresenter] isAvailable];
    [translationButton setHidden:!available];
    if (!available) {
        return;
    }

    BOOL enabled = [self hasSelectedText];
    [translationButton setEnabled:enabled];
    [translationButton setAlpha:enabled ? 1.0 : 0.35];
    [translationButton
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Translate"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
}

@end
