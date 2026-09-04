#import "KayokoColorPickerCell.h"

#import <Preferences/PSSpecifier.h>
#import <math.h>

static UIColor *KayokoColorFromHex(NSString *hex) {
    unsigned int rgb = 0;
    NSString *value = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if ([value length] != 6 || ![[NSScanner scannerWithString:value] scanHexInt:&rgb]) {
        return UIColor.systemIndigoColor;
    }
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation KayokoColorPickerCell {
    UIColorWell *_colorWell;
    UILabel *_titleLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.textLabel.hidden = YES;
        self.detailTextLabel.hidden = YES;
        _colorWell = [[UIColorWell alloc] initWithFrame:CGRectZero];
        _colorWell.translatesAutoresizingMaskIntoConstraints = NO;
        _colorWell.supportsAlpha = NO;
        NSString *hex = [specifier performGetter] ?: [specifier propertyForKey:@"default"];
        _colorWell.selectedColor = KayokoColorFromHex(hex);
        [_colorWell addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_colorWell];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.text = [specifier name];
        [self.contentView addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_colorWell.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_colorWell.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_colorWell.widthAnchor constraintEqualToConstant:36],
            [_colorWell.heightAnchor constraintEqualToConstant:36],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_colorWell.trailingAnchor constant:16],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
        ]];
    }
    return self;
}

- (void)colorChanged:(UIColorWell *)sender {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![sender.selectedColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return;
    }
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(red * 255),
                                               (int)lround(green * 255), (int)lround(blue * 255)];
    [[self specifier] performSetterWithValue:hex];
}

@end
