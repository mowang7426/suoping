#import "LSGCNotificationsAppBarView.h"

static UIImage *LetterIcon(NSString *app) {
    NSString *name=[app componentsSeparatedByString:@"."].lastObject ?: app;
    if (!name.length) name=@"?";
    NSString *letter=[[name substringWithRange:[name rangeOfComposedCharacterSequenceAtIndex:0]] uppercaseString];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28,28)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        [[UIColor.systemBlueColor colorWithAlphaComponent:0.8] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,28,28) cornerRadius:7] fill];
        NSDictionary *attributes=@{NSFontAttributeName:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor};
        CGSize size=[letter sizeWithAttributes:attributes];
        [letter drawAtPoint:CGPointMake((28-size.width)/2,(28-size.height)/2) withAttributes:attributes];
    }];
}

@interface LSGCNotificationsAppBarView ()
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,copy) NSArray<NSDictionary *> *rows;
@end

@implementation LSGCNotificationsAppBarView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints=NO;
        self.accessibilityIdentifier=@"LSGCNotificationsAppBar";
        _scroll=[UIScrollView new];
        _scroll.translatesAutoresizingMaskIntoConstraints=NO;
        _scroll.alwaysBounceHorizontal=YES;
        _scroll.showsHorizontalScrollIndicator=NO;
        _scroll.directionalLockEnabled=YES;
        _stack=[UIStackView new];
        _stack.translatesAutoresizingMaskIntoConstraints=NO;
        _stack.axis=UILayoutConstraintAxisHorizontal;
        _stack.alignment=UIStackViewAlignmentFill;
        _stack.spacing=8;
        [self addSubview:_scroll]; [_scroll addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor constant:4],
            [_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor constant:-4],
            [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:4],
            [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-4],
            [_stack.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor constant:-8]
        ]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentSizeChanged:)
            name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)contentSizeChanged:(NSNotification *)notification {
    (void)notification;
    [self invalidateIntrinsicContentSize];
}
- (CGSize)intrinsicContentSize {
    // Font metrics, not screen coordinates. The host must reject insufficient space.
    CGFloat height=MAX(44,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleCaption1].lineHeight*2+16));
    return CGSizeMake(UIViewNoIntrinsicMetric,height);
}
- (void)renderRows:(NSArray<NSDictionary *> *)rows selected:(NSString *)identifier {
    NSAssert(NSThread.isMainThread,@"App bar UI must be updated on main");
    if (rows.count>129) return;
    self.rows=[rows copy];
    for (UIView *view in self.stack.arrangedSubviews.copy) {
        [self.stack removeArrangedSubview:view]; [view removeFromSuperview];
    }
    NSUInteger index=0;
    for (NSDictionary *row in self.rows) {
        NSString *app=[row[@"identifier"] isKindOfClass:NSString.class]?row[@"identifier"]:nil;
        NSString *name=[row[@"name"] isKindOfClass:NSString.class]?row[@"name"]:app;
        NSNumber *count=[row[@"count"] isKindOfClass:NSNumber.class]?row[@"count"]:nil;
        if (!app || !count) { ++index; continue; }
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        button.tag=(NSInteger)index++;
        UIButtonConfiguration *configuration=UIButtonConfiguration.tintedButtonConfiguration;
        configuration.image=app.length?LetterIcon(app):[UIImage systemImageNamed:@"square.grid.2x2.fill"];
        configuration.imagePlacement=NSDirectionalRectEdgeLeading;
        configuration.imagePadding=5;
        configuration.title=app.length?count.stringValue:[NSString stringWithFormat:@"全部 %@",count];
        configuration.baseForegroundColor=UIColor.labelColor;
        configuration.baseBackgroundColor=[app isEqualToString:identifier?:@""]?
            [UIColor.systemBlueColor colorWithAlphaComponent:0.25]:[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.8];
        configuration.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
        button.configuration=configuration;
        button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        button.titleLabel.adjustsFontForContentSizeCategory=YES;
        button.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",app.length?(name.length?name:app):@"全部",count];
        button.accessibilityTraits|=[app isEqualToString:identifier?:@""]?UIAccessibilityTraitSelected:0;
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
        [button addTarget:self action:@selector(chosen:) forControlEvents:UIControlEventTouchUpInside];
        [self.stack addArrangedSubview:button];
    }
    [self invalidateIntrinsicContentSize];
}
- (void)chosen:(UIButton *)button {
    if (button.tag<0 || (NSUInteger)button.tag>=self.rows.count) return;
    NSString *app=self.rows[(NSUInteger)button.tag][@"identifier"];
    // A request is not an applied filter. Caller must first commit native adapter.
    if ([app isKindOfClass:NSString.class] && self.selectionRequested) self.selectionRequested(app);
}
@end
