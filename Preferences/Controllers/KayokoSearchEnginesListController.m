#import "KayokoPreferenceKeys.h"

#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>

@interface KayokoSearchEnginesListController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary<NSString *, NSString *> *> *engines;
@property(nonatomic, strong) UITableView *tableView;
@end

@implementation KayokoSearchEnginesListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[NSBundle bundleForClass:self.class] localizedStringForKey:@"Search Engines" value:nil table:@"Root"];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    NSArray *stored = [[[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier]
        arrayForKey:kKayokoPreferenceKeySearchEngines];
    self.engines = [[NSMutableArray alloc] init];
    for (NSDictionary *entry in stored) {
        NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : nil;
        NSString *engine = [entry[@"engine"] isKindOfClass:[NSString class]] ? entry[@"engine"] : nil;
        if ([name length] && [engine length]) {
            [self.engines addObject:[@{ @"name" : name, @"engine" : engine } mutableCopy]];
        }
    }
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                              target:self
                                                                              action:@selector(addEngine)];
    self.navigationItem.rightBarButtonItems = @[ addButton, self.editButtonItem ];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)saveEngines {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [defaults setObject:self.engines forKey:kKayokoPreferenceKeySearchEngines];
    [defaults synchronize];
}

- (void)addEngine {
    [self editEngineAtIndex:NSNotFound];
}

- (void)editEngineAtIndex:(NSUInteger)index {
    NSDictionary *existing = index < self.engines.count ? self.engines[index] : nil;
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        [bundle localizedStringForKey:(existing ? @"Edit Search Engine" : @"Add Search Engine") value:nil table:@"Root"]
                                                                   message:[bundle localizedStringForKey:@"Use %@ in the engine URL for the selected text." value:nil table:@"Root"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
      field.placeholder = [bundle localizedStringForKey:@"Name" value:nil table:@"Root"];
      field.text = existing[@"name"];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
      field.placeholder = [bundle localizedStringForKey:@"Search Engine URL" value:nil table:@"Root"];
      field.text = existing[@"engine"];
      field.keyboardType = UIKeyboardTypeURL;
      field.autocapitalizationType = UITextAutocapitalizationTypeNone;
      field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel" value:nil table:@"Root"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Save" value:nil table:@"Root"]
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
      NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      NSString *engine = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (![name length] || ![engine length]) {
          return;
      }
      NSMutableDictionary *entry = [@{ @"name" : name, @"engine" : engine } mutableCopy];
      if (index < weakSelf.engines.count) {
          weakSelf.engines[index] = entry;
      } else {
          [weakSelf.engines addObject:entry];
      }
      [weakSelf saveEngines];
      [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.engines.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"SearchEngine";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary *entry = self.engines[indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.detailTextLabel.text = entry[@"engine"];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editEngineAtIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableDictionary *entry = self.engines[sourceIndexPath.row];
    [self.engines removeObjectAtIndex:sourceIndexPath.row];
    [self.engines insertObject:entry atIndex:destinationIndexPath.row];
    [self saveEngines];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    [self.engines removeObjectAtIndex:indexPath.row];
    [self saveEngines];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
