//
//  KayokoSearchController.m
//  Kayoko
//

#import "KayokoSearchController.h"

#import "KayokoHistoryListView.h"
#import "KayokoHistoryListViewController.h"
#import "KayokoPasteboardManager.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoSearchBar.h"
#import "KayokoSearchCriteria.h"
#import "KayokoSearchPresentationController.h"

static NSTimeInterval const kKayokoSearchInputDebounceInterval = 0.15;

NS_ASSUME_NONNULL_BEGIN

@interface KayokoSearchController () <UISearchBarDelegate, KayokoSearchPresentationControllerDelegate>
#pragma mark - Presentation

@property(nonatomic, strong) KayokoSearchPresentationController *presentationController;
@property(nonatomic, weak) KayokoHistoryListViewController *historyListViewController;
@property(nonatomic, weak) KayokoHistoryListViewController *favoritesListViewController;
@property(nonatomic, strong) UISearchBar *historySearchBar;
@property(nonatomic, strong) UISearchBar *favoritesSearchBar;
#pragma mark - State

@property(nonatomic, assign, getter=isSearchActive) BOOL searchActive;
@property(nonatomic, assign) BOOL isResettingSearch;
@property(nonatomic, assign) BOOL isEndingSearchTransition;
@property(nonatomic, assign) NSUInteger searchRequestIdentifier;
@property(nonatomic, copy, nullable) dispatch_block_t pendingTextSearchBlock;
@property(nonatomic, strong, nullable) KayokoSearchCriteria *pendingTextSearchCriteria;
@property(nonatomic, weak, nullable) UISearchBar *pendingTextSearchBar;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoSearchController

#pragma mark - Lifecycle

- (instancetype)initWithContainerView:(UIView *)containerView
                           headerView:(KayokoHeaderView *)headerView
            historyListViewController:(KayokoHistoryListViewController *)historyListViewController
          favoritesListViewController:(KayokoHistoryListViewController *)favoritesListViewController
                 panGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer {
    self = [super init];
    if (self) {
        _historyListViewController = historyListViewController;
        _favoritesListViewController = favoritesListViewController;
        _historySearchBar = [self newSearchBar];
        _favoritesSearchBar = [self newSearchBar];
        _presentationController =
            [[KayokoSearchPresentationController alloc] initWithContainerView:containerView
                                                                   headerView:headerView
                                                             historySearchBar:_historySearchBar
                                                           favoritesSearchBar:_favoritesSearchBar
                                                             historyTableView:[historyListViewController tableView]
                                                           favoritesTableView:[favoritesListViewController tableView]
                                                         panGestureRecognizer:panGestureRecognizer];
        [_presentationController setDelegate:self];

        [self attachToListViewController:historyListViewController hidesSearchBar:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleHistoryDidChangeNotification:)
                                                     name:kKayokoPasteboardManagerHistoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (UISearchBar *)newSearchBar {
    UISearchBar *searchBar = [[KayokoSearchBar alloc] initWithFrame:CGRectZero];
    [searchBar setPlaceholder:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Search"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [searchBar setSearchBarStyle:UISearchBarStyleMinimal];
    [searchBar setBackgroundImage:[[UIImage alloc] init]];
    [searchBar setTintColor:[UIColor labelColor]];
    [searchBar setDelegate:self];
    [[searchBar searchTextField] addTarget:self
                                    action:@selector(handleSearchTextFieldEditingChanged:)
                          forControlEvents:UIControlEventEditingChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSearchTextFieldTextDidChangeNotification:)
                                                 name:UITextFieldTextDidChangeNotification
                                               object:[searchBar searchTextField]];
    return searchBar;
}

- (void)dealloc {
    [self cancelPendingTextSearch];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)handleHistoryDidChangeNotification:(NSNotification *)notification {
    (void)notification;
}

- (void)handleApplicationMetadataChanged {
}

#pragma mark - View Lookup

- (void)setPresentationMode:(KayokoPanelPresentationMode)presentationMode {
    _presentationMode = presentationMode;
    [[self presentationController] setPresentationMode:presentationMode];
}

- (KayokoHistoryListViewController *)activeListViewController {
    return [[self delegate] activeListViewControllerForSearchController:self];
}

- (KayokoHistoryListView *)activeTableView {
    return [[self activeListViewController] tableView];
}

- (CGFloat)searchHeaderHeight {
    return [[self presentationController] searchHeaderHeight];
}

- (CGFloat)keyboardBottomInset {
    return [[self presentationController] keyboardBottomInset];
}

- (UISearchBar *)searchBarForTableView:(KayokoHistoryListView *)tableView {
    return tableView == [[self favoritesListViewController] tableView] ? [self favoritesSearchBar]
                                                                       : [self historySearchBar];
}

- (KayokoHistoryListViewController *)listViewControllerForSearchBar:(UISearchBar *)searchBar {
    return searchBar == [self favoritesSearchBar] ? [self favoritesListViewController]
                                                  : [self historyListViewController];
}

- (UISearchBar *)activeSearchBar {
    return [self searchBarForTableView:[self activeTableView]];
}

- (KayokoSearchCriteria *)criteriaFromSearchBar:(UISearchBar *)searchBar
                             listViewController:(KayokoHistoryListViewController *)listViewController {
    (void)listViewController;
    return [KayokoSearchCriteria criteriaWithSearchText:[searchBar text]
                                          categoryValue:nil
                                    appBundleIdentifier:nil
                                                tagUUID:nil];
}

#pragma mark - Layout

- (void)layout {
    [[self presentationController] layout];
}

- (void)attachToListViewController:(KayokoHistoryListViewController *)listViewController
                    hidesSearchBar:(BOOL)hidesSearchBar {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    if ([self pendingTextSearchBar] && [self pendingTextSearchBar] != searchBar) {
        [self cancelPendingTextSearch];
    }
    [[self presentationController] attachToTableView:[listViewController tableView] hidesSearchBar:hidesSearchBar];
}

- (BOOL)listViewControllerIsFavorites:(KayokoHistoryListViewController *)listViewController {
    return listViewController == [self favoritesListViewController] ||
           [[listViewController historyKey] isEqualToString:kKayokoHistoryKeyFavorites];
}

- (void)resetSearchSessionState {
}


#pragma mark - Search Application

- (void)cancelPendingTextSearch {
    dispatch_block_t block = [self pendingTextSearchBlock];
    if (block) {
        dispatch_block_cancel(block);
    }
    [self setPendingTextSearchBlock:nil];
    [self setPendingTextSearchCriteria:nil];
    [self setPendingTextSearchBar:nil];
}

- (void)invalidatePendingSearchRequests {
    [self cancelPendingTextSearch];
    [self setSearchRequestIdentifier:[self searchRequestIdentifier] + 1];
}

// Whether the favorites search bar is hidden right now (search inactive). Captured before a filter
// reload so we can keep it hidden afterwards without ever disturbing a bar the user pulled down.
- (BOOL)favoritesSearchBarHiddenBeforeReload:(KayokoHistoryListViewController *)listViewController {
    if ([self isSearchActive] || ![self listViewControllerIsFavorites:listViewController]) {
        return NO;
    }
    return [[listViewController tableView] isSearchBarHiddenAtCurrentContentOffset];
}

// After a favorites filter reload, restore the search bar to the hidden position — but only if it
// was hidden before the reload (wasHidden). Selecting a filter must never reveal it just because
// the filtered list is short; a bar the user deliberately pulled down is left alone.
- (void)keepFavoritesSearchBarHidden:(BOOL)wasHidden
                forListViewController:(KayokoHistoryListViewController *)listViewController {
    if (!wasHidden || [self isSearchActive] || ![self listViewControllerIsFavorites:listViewController]) {
        return;
    }
    [[listViewController tableView] keepSearchBarHiddenAfterReload];
}

- (void)applySearchCriteria:(KayokoSearchCriteria *)criteria
       toListViewController:(KayokoHistoryListViewController *)listViewController {
    [self cancelPendingTextSearch];
    // Capture the search bar's hidden state before any reload so a short filtered list can't reveal
    // it. Selecting a filter only reloads list data — the search bar is a separate surface.
    BOOL searchBarWasHidden = [self favoritesSearchBarHiddenBeforeReload:listViewController];
    // Favorites filter chips can apply filters even when the search field is inactive.
    if (![self isSearchActive] && ![criteria hasActiveFilters]) {
        [self invalidatePendingSearchRequests];
        if ([listViewController hasActiveSearch]) {
            [listViewController clearSearch];
        }
        [self keepFavoritesSearchBarHidden:searchBarWasHidden forListViewController:listViewController];
        return;
    }

    if (![criteria hasActiveFilters]) {
        [self invalidatePendingSearchRequests];
        [listViewController showSearchTokensWithFullListForCriteria:criteria];
        return;
    }

    NSUInteger requestIdentifier = [self searchRequestIdentifier] + 1;
    [self setSearchRequestIdentifier:requestIdentifier];
    [listViewController beginApplyingSearchCriteria:criteria];
    __weak typeof(self) weakSelf = self;
    [[KayokoPasteboardManager sharedInstance]
        getItemsFromHistoryWithKey:[listViewController historyKey]
                    searchCriteria:criteria
                        completion:^(NSMutableArray<NSDictionary<NSString *, id> *> *items, NSError *error) {
                          __strong typeof(weakSelf) strongSelf = weakSelf;
                          if (!strongSelf || [strongSelf searchRequestIdentifier] != requestIdentifier) {
                              return;
                          }
                          if (error) {
                              [[strongSelf delegate] searchController:strongSelf didFailLoadingSearchWithError:error];
                              return;
                          }
                          [listViewController applySearchCriteria:criteria filteredItems:items];
                          [strongSelf keepFavoritesSearchBarHidden:searchBarWasHidden
                                             forListViewController:listViewController];
                        }];
}

- (void)applySearchFromSearchBar:(UISearchBar *)searchBar {
    KayokoHistoryListViewController *listViewController = [self listViewControllerForSearchBar:searchBar];
    KayokoSearchCriteria *criteria = [self criteriaFromSearchBar:searchBar listViewController:listViewController];
    [self applySearchCriteria:criteria toListViewController:listViewController];
}

- (void)scheduleTextSearchFromSearchBar:(UISearchBar *)searchBar {
    if ([self isResettingSearch] ||
        [self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }

    if ([[searchBar searchTextField] markedTextRange]) {
        [self cancelPendingTextSearch];
        return;
    }

    KayokoHistoryListViewController *listViewController = [self listViewControllerForSearchBar:searchBar];
    KayokoSearchCriteria *criteria = [self criteriaFromSearchBar:searchBar listViewController:listViewController];

    if ([criteria isEqualToCriteria:[listViewController searchCriteria]]) {
        [self cancelPendingTextSearch];
        return;
    }
    if ([self pendingTextSearchBar] == searchBar && [[self pendingTextSearchCriteria] isEqualToCriteria:criteria]) {
        return;
    }
    if ([[criteria searchText] length] == 0) {
        [self applySearchCriteria:criteria toListViewController:listViewController];
        return;
    }

    [self cancelPendingTextSearch];
    [self setPendingTextSearchCriteria:criteria];
    [self setPendingTextSearchBar:searchBar];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || [strongSelf pendingTextSearchCriteria] != criteria ||
          [strongSelf pendingTextSearchBar] != searchBar) {
          return;
      }

      [strongSelf setPendingTextSearchBlock:nil];
      [strongSelf setPendingTextSearchCriteria:nil];
      [strongSelf setPendingTextSearchBar:nil];
      [strongSelf applySearchCriteria:criteria toListViewController:listViewController];
    });
    [self setPendingTextSearchBlock:block];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kKayokoSearchInputDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)applySearchToActiveTableView {
    [self applySearchFromSearchBar:[self activeSearchBar]];
}

- (void)syncSearchBarForListViewController:(KayokoHistoryListViewController *)listViewController {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    KayokoSearchCriteria *criteria = [self pendingTextSearchBar] == searchBar ? [self pendingTextSearchCriteria]
                                                                              : [listViewController searchCriteria];
    BOOL wasResettingSearch = [self isResettingSearch];
    [self setIsResettingSearch:YES];
    [searchBar setText:[criteria searchText]];
    [self setIsResettingSearch:wasResettingSearch];
}

- (void)restoreContentOffset:(CGPoint)contentOffset
       forListViewController:(KayokoHistoryListViewController *)listViewController {
    [[listViewController tableView] setContentOffset:contentOffset animated:NO];
}

- (void)refreshForListViewController:(KayokoHistoryListViewController *)listViewController {
    [self attachToListViewController:listViewController hidesSearchBar:![self isSearchActive]];
    [self syncSearchBarForListViewController:listViewController];
    [self applySearchFromSearchBar:[self searchBarForTableView:[listViewController tableView]]];
    if ([self isSearchActive] && listViewController == [self activeListViewController]) {
        [[self historySearchBar] setShowsCancelButton:NO animated:NO];
        [[self favoritesSearchBar] setShowsCancelButton:NO animated:NO];
        [[self activeSearchBar] setShowsCancelButton:YES animated:NO];
        // Restoring focus on the next runloop lets the search bar settle after its text/tokens
        // were just reset above; a synchronous becomeFirstResponder here races that reset and the
        // system silently drops the cursor (e.g. after switching the clipboard/favorites tab).
        UISearchBar *searchBarToFocus = [self activeSearchBar];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf || ![strongSelf isSearchActive] ||
              [strongSelf activeSearchBar] != searchBarToFocus) {
              return;
          }
          if (![searchBarToFocus isFirstResponder] && ![[searchBarToFocus searchTextField] isFirstResponder]) {
              [searchBarToFocus becomeFirstResponder];
          }
        });
    }
}

- (void)refreshAfterTransientContentForListViewController:(KayokoHistoryListViewController *)listViewController
                                   restoresFirstResponder:(BOOL)restoresFirstResponder
                                      targetContentOffset:(CGPoint)targetContentOffset {
    CGPoint currentContentOffset = [[listViewController tableView] contentOffset];
    [[self presentationController] layout];
    [self syncSearchBarForListViewController:listViewController];
    [self restoreContentOffset:currentContentOffset forListViewController:listViewController];
    if ([self isSearchActive] && listViewController == [self activeListViewController]) {
        [[self historySearchBar] setShowsCancelButton:NO animated:NO];
        [[self favoritesSearchBar] setShowsCancelButton:NO animated:NO];
        [[self activeSearchBar] setShowsCancelButton:YES animated:NO];
        if (restoresFirstResponder) {
            [[listViewController tableView] beginTransientContentOffsetPreservationAtContentOffset:targetContentOffset];
            [[self activeSearchBar] becomeFirstResponder];
        }
    }
}

#pragma mark - Search Session

- (void)setSearchBarsShowCancelButton:(BOOL)showsCancelButton animated:(BOOL)animated {
    [[self historySearchBar] setShowsCancelButton:NO animated:animated];
    [[self favoritesSearchBar] setShowsCancelButton:NO animated:animated];
    if (showsCancelButton) {
        [[self activeSearchBar] setShowsCancelButton:YES animated:animated];
    }
}

- (void)resignSearchFirstResponder {
    [[self activeSearchBar] resignFirstResponder];
}

- (BOOL)isActiveSearchFirstResponder {
    UISearchBar *searchBar = [self activeSearchBar];
    UITextField *searchTextField = [searchBar searchTextField];
    return [searchBar isFirstResponder] || [searchTextField isFirstResponder];
}

- (void)beginSearchIfNeeded {
    if ([self isSearchActive]) {
        return;
    }

    [self setSearchActive:YES];
    [self applySearchFromSearchBar:[self activeSearchBar]];
    [self setSearchBarsShowCancelButton:YES animated:NO];
    [[self delegate] searchControllerWillAnimateSearchState:self];
    __weak typeof(self) weakSelf = self;
    [[self presentationController]
        beginSearchWithActiveTableView:[[self activeListViewController] tableView]
                            completion:^{
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }
                              [[strongSelf delegate] searchControllerDidFinishAnimatingSearchState:strongSelf];
                            }];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     animations:(void (^)(void))animations
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame
                     clearsSearch:clearsSearch
                       animations:animations
                     panVelocityY:0
                       completion:completion];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     animations:(void (^)(void))animations
                   panVelocityY:(CGFloat)panVelocityY
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame
                         clearsSearch:clearsSearch
                           animations:animations
                         panVelocityY:panVelocityY
        coordinatesVisibleSearchReset:NO
                           completion:completion];
}

- (void)finishDeferredVisibleSearchResetClearingSearch:(BOOL)clearsSearch {
    [self setSearchActive:NO];
    [self setSearchBarsShowCancelButton:NO animated:NO];
    if (clearsSearch) {
        [self clearSearchForListViewController:[self historyListViewController]];
        [self clearSearchForListViewController:[self favoritesListViewController]];
    }
    [self applySearchToActiveTableView];
    [[self presentationController] hideSearchBarInTableView:[self activeTableView] animated:NO];
    [self setIsResettingSearch:NO];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                     clearsSearch:(BOOL)clearsSearch
                       animations:(void (^)(void))animations
                     panVelocityY:(CGFloat)panVelocityY
    coordinatesVisibleSearchReset:(BOOL)coordinatesVisibleSearchReset
                       completion:(void (^)(void))completion {
    [self cancelPendingTextSearch];
    if (![self isSearchActive] && !clearsSearch) {
        if (animations) {
            animations();
        }
        [self resetSearchSessionState];
        if (completion) {
            completion();
        }
        return;
    }

    BOOL defersVisibleSearchReset = coordinatesVisibleSearchReset && clearsSearch &&
                                    [self presentationMode] == KayokoPanelPresentationModeCompactLandscapeFullscreen;
    [self setIsResettingSearch:YES];
    // Suppress the favorites filter panel for the whole exit transition so it does not flash
    // while the card animates back from the search position.
    [self setIsEndingSearchTransition:YES];
    UISearchBar *activeSearchBar = [self activeSearchBar];
    if (!defersVisibleSearchReset) {
        [self setSearchActive:NO];
    }
    [activeSearchBar resignFirstResponder];
    if (!defersVisibleSearchReset) {
        [self setSearchBarsShowCancelButton:NO animated:YES];
    }
    if (clearsSearch && !defersVisibleSearchReset) {
        [self clearSearchForListViewController:[self historyListViewController]];
        [self clearSearchForListViewController:[self favoritesListViewController]];
    }
    [[self presentationController] resetKeyboardInsets];
    if (!defersVisibleSearchReset) {
        [self applySearchToActiveTableView];
        [self setIsResettingSearch:NO];
    }

    [[self delegate] searchControllerWillAnimateSearchState:self];
    [[self presentationController]
        endSearchRestoringFrame:restoresFrame
                activeTableView:[[self activeListViewController] tableView]
                     animations:animations
                   panVelocityY:panVelocityY
                     completion:^{
                       if (defersVisibleSearchReset) {
                           [self finishDeferredVisibleSearchResetClearingSearch:clearsSearch];
                       }
                       [self resetSearchSessionState];
                       [self setIsEndingSearchTransition:NO];
                       [[self delegate] searchControllerDidFinishAnimatingSearchState:self];
                       if (completion) {
                           completion();
                       }
                     }];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame clearsSearch:clearsSearch animations:nil completion:completion];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame clearsSearch:(BOOL)clearsSearch {
    [self endSearchRestoringFrame:restoresFrame clearsSearch:clearsSearch completion:nil];
}

- (void)cancelSearchWithCompletion:(void (^)(void))completion {
    [self endSearchRestoringFrame:YES clearsSearch:YES completion:completion];
}

- (void)cancelSearchWithAnimations:(void (^)(void))animations completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:YES clearsSearch:YES animations:animations completion:completion];
}

- (void)collapseSearchFromFullscreenPanWithVelocity:(CGFloat)velocityY {
    [self endSearchRestoringFrame:YES clearsSearch:YES animations:nil panVelocityY:velocityY completion:nil];
}

- (void)handleFullscreenPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                                  headerView:(nullable KayokoHeaderView *)headerView {
    [[self presentationController] handleFullscreenPanGestureRecognizer:recognizer
                                                        activeTableView:[self activeTableView]
                                                             headerView:headerView];
}

- (CGRect)resetSearchStateRestoringContainerFrame:(BOOL)restoresContainerFrame {
    [self cancelPendingTextSearch];
    BOOL hasSearch =
        [[self historyListViewController] hasActiveSearch] || [[self favoritesListViewController] hasActiveSearch];
    if (![self isSearchActive] && !hasSearch) {
        [self resetSearchSessionState];
        return CGRectZero;
    }

    [self setIsResettingSearch:YES];
    [self setSearchActive:NO];
    [[self historySearchBar] resignFirstResponder];
    [[self favoritesSearchBar] resignFirstResponder];
    [self setSearchBarsShowCancelButton:NO animated:NO];
    [self clearSearchForListViewController:[self historyListViewController]];
    [self clearSearchForListViewController:[self favoritesListViewController]];
    [self applySearchToActiveTableView];
    CGRect normalFrame =
        [[self presentationController] resetAfterSearchStateClearedWithActiveTableView:[self activeTableView]
                                                                restoresContainerFrame:restoresContainerFrame];
    [self resetSearchSessionState];
    [self setIsResettingSearch:NO];
    return normalFrame;
}

- (void)resetSearchState {
    [self resetSearchStateRestoringContainerFrame:YES];
}

- (CGRect)resetSearchStatePreservingContainerFrame {
    return [self resetSearchStateRestoringContainerFrame:NO];
}

#pragma mark - Clearing

- (void)clearSearchForListViewController:(KayokoHistoryListViewController *)listViewController {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    BOOL wasResettingSearch = [self isResettingSearch];
    [self setIsResettingSearch:YES];
    [searchBar setText:@""];
    [self invalidatePendingSearchRequests];
    [listViewController clearSearch];
    [self setIsResettingSearch:wasResettingSearch];
}

#pragma mark - KayokoSearchPresentationControllerDelegate

- (void)searchPresentationController:(KayokoSearchPresentationController *)controller
        didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    [[self delegate] searchController:self didUpdateKeyboardBottomInset:keyboardBottomInset];
}

- (void)searchPresentationController:(KayokoSearchPresentationController *)controller
    didRequestCollapseFromFullscreenPanWithVelocity:(CGFloat)velocityY {
    [self collapseSearchFromFullscreenPanWithVelocity:velocityY];
}
#pragma mark - Search Text Events

- (void)handleSearchTextFieldEditingChanged:(UITextField *)textField {
    UISearchBar *searchBar =
        textField == [[self favoritesSearchBar] searchTextField] ? [self favoritesSearchBar] : [self historySearchBar];
    [self scheduleTextSearchFromSearchBar:searchBar];
}

- (void)handleSearchTextFieldTextDidChangeNotification:(NSNotification *)notification {
    UITextField *textField = [notification object];
    UISearchBar *searchBar =
        textField == [[self favoritesSearchBar] searchTextField] ? [self favoritesSearchBar] : [self historySearchBar];
    [self scheduleTextSearchFromSearchBar:searchBar];
}

#pragma mark - UISearchBarDelegate

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] == [self activeListViewController]) {
        [[self delegate] searchControllerWillBeginSearchInputTransition:self];
    }
    return YES;
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }
    [self beginSearchIfNeeded];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchText;
    [self scheduleTextSearchFromSearchBar:searchBar];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }
    [self endSearchRestoringFrame:YES
                         clearsSearch:YES
                           animations:nil
                         panVelocityY:0
        coordinatesVisibleSearchReset:YES
                           completion:nil];
}

@end
