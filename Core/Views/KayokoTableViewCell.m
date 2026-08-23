//
//  KayokoTableViewCell.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoTableViewCell.h"
#import "KayokoTableViewCellContent.h"
static CGFloat const kKayokoTableViewCellContentImageWidth = 70;
static CGFloat const kKayokoTableViewCellContentImageHeight = 40;

@interface KayokoTableViewCellPreviewLabel : UILabel
@end

@implementation KayokoTableViewCellPreviewLabel

- (void)drawTextInRect:(CGRect)rect {
    CGRect textRect = [self textRectForBounds:rect limitedToNumberOfLines:[self numberOfLines]];
    textRect.origin = rect.origin;
    textRect.size.width = rect.size.width;
    [super drawTextInRect:textRect];
}

@end

@interface KayokoTableViewCell ()
@property(nonatomic, copy, nullable) NSString *representedImageName;
@end

@implementation KayokoTableViewCell

+ (NSString *)reuseIdentifierForContent:(KayokoTableViewCellContent *)content {
    BOOL hasContentImageSlot = [content contentImage] || [[content thumbnailImageName] length] > 0;
    BOOL hasContentText = [[content contentText] length] > 0;
    return [NSString stringWithFormat:@"KayokoTableViewCell-%d-%d-%d", hasContentImageSlot, hasContentText,
                                      [content showsDetail]];
}

+ (CGSize)contentImageThumbnailSize {
    CGFloat sideLength = MAX(kKayokoTableViewCellContentImageWidth, kKayokoTableViewCellContentImageHeight);
    return CGSizeMake(sideLength, sideLength);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
                      content:(KayokoTableViewCellContent *)content
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];

    if (self) {
        CGSize contentImageViewSize = CGSizeMake(kKayokoTableViewCellContentImageWidth,
                                                 kKayokoTableViewCellContentImageHeight);
        BOOL hasContentText = [[content contentText] length] > 0;
        BOOL showsDetail = [content showsDetail];
        [self setBackgroundColor:[UIColor clearColor]];
        UIView *selectedBackgroundView = [[UIView alloc] init];
        UIColor *selectedBackgroundColor =
            [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
              if ([traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark) {
                  return [UIColor colorWithWhite:1 alpha:0.08];
              }

              return [UIColor colorWithWhite:0 alpha:0.055];
            }];
        [selectedBackgroundView setBackgroundColor:selectedBackgroundColor];
        [self setSelectedBackgroundView:selectedBackgroundView];

        [self setIconImageView:[[UIImageView alloc] init]];
        [[self iconImageView] setContentMode:UIViewContentModeScaleAspectFit];
        [[self iconImageView] setClipsToBounds:YES];
        [[[self iconImageView] layer] setCornerRadius:10];
        [self addSubview:[self iconImageView]];

        [[self iconImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self iconImageView] widthAnchor] constraintEqualToConstant:40],
            [[[self iconImageView] heightAnchor] constraintEqualToConstant:40],
            [[[self iconImageView] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
            [[[self iconImageView] leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:24]
        ]];

        UIImage *contentImage = [content contentImage];
        NSString *thumbnailImageName = [content thumbnailImageName];
        BOOL hasContentImageSlot = contentImage || [thumbnailImageName length] > 0;
        [self setRepresentedImageName:thumbnailImageName];
        if (hasContentImageSlot) {
            [self setContentImageView:[[UIImageView alloc] init]];
            [[self contentImageView] setImage:contentImage];

            [[self contentImageView] setContentMode:UIViewContentModeScaleAspectFill];
            [[self contentImageView] setClipsToBounds:YES];
            [[self contentImageView]
                setBackgroundColor:contentImage ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
            [[[self contentImageView] layer] setCornerRadius:4];
            [self addSubview:[self contentImageView]];

            [[self contentImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self contentImageView] widthAnchor] constraintEqualToConstant:contentImageViewSize.width],
                [[[self contentImageView] heightAnchor] constraintEqualToConstant:contentImageViewSize.height],
                [[[self contentImageView] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
                [[[self contentImageView] trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-24]
            ]];
        }

        [self setHeaderLabel:[[UILabel alloc] init]];
        [[self headerLabel] setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightMedium]];
        [[self headerLabel] setTextColor:[UIColor labelColor]];
        [[self headerLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
        [[self headerLabel] setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                              forAxis:UILayoutConstraintAxisHorizontal];
        [[self headerLabel] setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                            forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:[self headerLabel]];

        [[self headerLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] leadingAnchor]
                                                    constraintEqualToAnchor:[[self iconImageView] trailingAnchor]
                                                                   constant:16] ]];

        NSLayoutXAxisAnchor *textTrailingAnchor =
            [self contentImageView] ? [[self contentImageView] leadingAnchor] : [self trailingAnchor];
        CGFloat textTrailingConstant = [self contentImageView] ? -16 : -24;

        [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] trailingAnchor]
                                                    constraintEqualToAnchor:textTrailingAnchor
                                                                   constant:textTrailingConstant] ]];

        if (hasContentText) {
            [self setContentLabel:[[KayokoTableViewCellPreviewLabel alloc] init]];
            [[self contentLabel] setFont:[UIFont systemFontOfSize:14]];
            [[self contentLabel] setTextColor:[[UIColor labelColor] colorWithAlphaComponent:0.8]];
            [[self contentLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
            [[self contentLabel] setNumberOfLines:1];
            [self addSubview:[self contentLabel]];
            [[self contentLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            CGFloat previewLabelHeight = ceil([[[self contentLabel] font] lineHeight]);
            [NSLayoutConstraint activateConstraints:@[
                [[[self contentLabel] topAnchor] constraintEqualToAnchor:[[self headerLabel] bottomAnchor] constant:2],
                [[[self contentLabel] leadingAnchor] constraintEqualToAnchor:[[self headerLabel] leadingAnchor]],
                [[[self contentLabel] trailingAnchor] constraintEqualToAnchor:textTrailingAnchor
                                                                     constant:textTrailingConstant],
                [[[self contentLabel] heightAnchor] constraintEqualToConstant:previewLabelHeight]
            ]];
        }

        if (showsDetail) {
            [self setDetailLabel:[[UILabel alloc] init]];
            [[self detailLabel] setFont:[UIFont systemFontOfSize:12]];
            [[self detailLabel] setTextColor:[UIColor secondaryLabelColor]];
            [[self detailLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
            [self addSubview:[self detailLabel]];
            [[self detailLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self detailLabel] leadingAnchor] constraintEqualToAnchor:[[self headerLabel] leadingAnchor]],
                [[[self detailLabel] trailingAnchor] constraintEqualToAnchor:textTrailingAnchor
                                                                    constant:textTrailingConstant]
            ]];
        }

        if (hasContentText) {
            [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] topAnchor]
                                                        constraintEqualToAnchor:[self topAnchor]
                                                                       constant:3] ]];
            if (showsDetail) {
                [NSLayoutConstraint activateConstraints:@[
                    [[[self detailLabel] topAnchor] constraintEqualToAnchor:[[self contentLabel] bottomAnchor]
                                                                   constant:2],
                    [[[self detailLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[self bottomAnchor]
                                                                                constant:-3]
                ]];
            } else {
                [NSLayoutConstraint activateConstraints:@[ [[[self contentLabel] bottomAnchor]
                                                            constraintLessThanOrEqualToAnchor:[self bottomAnchor]
                                                                                     constant:-3] ]];
            }
        } else if (showsDetail) {
            [NSLayoutConstraint activateConstraints:@[
                [[[self headerLabel] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor] constant:-8],
                [[[self headerLabel] topAnchor] constraintGreaterThanOrEqualToAnchor:[self topAnchor] constant:8],
                [[[self detailLabel] topAnchor] constraintEqualToAnchor:[[self headerLabel] bottomAnchor] constant:1],
                [[[self detailLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[self bottomAnchor] constant:-8]
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] centerYAnchor]
                                                        constraintEqualToAnchor:[self centerYAnchor]] ]];
        }

        [self applyContent:content];
    }

    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self setHidden:NO];
    [self setRepresentedImageName:nil];
    [[self iconImageView] setImage:nil];
    [[self headerLabel] setAttributedText:nil];
    [[self headerLabel] setText:nil];
    [[self contentLabel] setAttributedText:nil];
    [[self contentLabel] setText:nil];
    [[self detailLabel] setAttributedText:nil];
    [[self detailLabel] setText:nil];
    [[self contentImageView] setImage:nil];
    [[self contentImageView] setBackgroundColor:[UIColor tertiarySystemFillColor]];
}

- (void)applyDetailContent:(KayokoTableViewCellContent *)content {
    NSAttributedString *attributedDetailText = [content attributedDetailText];
    if (!attributedDetailText) {
        [[self detailLabel] setAttributedText:nil];
        [[self detailLabel] setText:nil];
        return;
    }

    NSMutableAttributedString *styledDetailText = [attributedDetailText mutableCopy];
    [styledDetailText addAttribute:NSFontAttributeName
                             value:[[self detailLabel] font]
                             range:NSMakeRange(0, [styledDetailText length])];
    [[self detailLabel] setAttributedText:styledDetailText];
}

- (void)applyContent:(KayokoTableViewCellContent *)content {
    [[self iconImageView] setImage:[content icon]];

    if ([content attributedDisplayName]) {
        NSMutableAttributedString *attributedDisplayName = [[content attributedDisplayName] mutableCopy];
        NSRange fullRange = NSMakeRange(0, [attributedDisplayName length]);
        [attributedDisplayName addAttribute:NSFontAttributeName value:[[self headerLabel] font] range:fullRange];
        [attributedDisplayName addAttribute:NSForegroundColorAttributeName
                                      value:[[self headerLabel] textColor]
                                      range:fullRange];
        [[self headerLabel] setAttributedText:attributedDisplayName];
    } else {
        [[self headerLabel] setAttributedText:nil];
        [[self headerLabel] setText:[content displayName]];
    }

    [[self contentLabel] setNumberOfLines:1];
    if ([content attributedContentText]) {
        NSMutableAttributedString *attributedText = [[content attributedContentText] mutableCopy];
        NSRange fullRange = NSMakeRange(0, [attributedText length]);
        [attributedText addAttribute:NSFontAttributeName value:[[self contentLabel] font] range:fullRange];
        [attributedText addAttribute:NSForegroundColorAttributeName
                               value:[[self contentLabel] textColor]
                               range:fullRange];
        [[self contentLabel] setAttributedText:attributedText];
    } else {
        [[self contentLabel] setAttributedText:nil];
        [[self contentLabel] setText:[content contentText] ?: @""];
    }
    [self applyDetailContent:content];

    UIImage *contentImage = [content contentImage];
    [self setRepresentedImageName:[content thumbnailImageName]];
    [[self contentImageView] setImage:contentImage];
    [[self contentImageView]
        setBackgroundColor:contentImage ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
}

- (void)setContentImage:(UIImage *)image forImageName:(NSString *)imageName {
    if ([[self representedImageName] length] == 0 || ![[self representedImageName] isEqualToString:imageName]) {
        return;
    }

    if (![self contentImageView]) {
        return;
    }

    [[self contentImageView] setImage:image];
    [[self contentImageView] setBackgroundColor:image ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
}

@end
