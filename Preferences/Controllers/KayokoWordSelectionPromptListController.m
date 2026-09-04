#import "KayokoWordSelectionPromptListController.h"

@implementation KayokoWordSelectionPromptListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"WordSelectionPrompt" target:self];
    }
    return _specifiers;
}

@end
