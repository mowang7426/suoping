#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "LSGCChargingCapsuleGeometry.h"
#import "LSGCChargingCapsuleText.h"
// Only our own capsule view; no global setters/draw hooks or animation sources.
@interface LSGCChargingCapsule : UIView
@property(nonatomic,strong) UILabel *primary;
@property(nonatomic,strong) UILabel *secondary;
@property(nonatomic,strong) UIView *separator;
@property(nonatomic,strong) UIImageView *bolt;
@property(nonatomic,strong) CAShapeLayer *track;
@property(nonatomic,strong) CAShapeLayer *ring;
@property(nonatomic,copy) NSString *renderKey;
- (void)renderText:(NSString *)text level:(float)level;
@end
@implementation LSGCChargingCapsule
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:.44];
        self.layer.cornerRadius=frame.size.height/2; self.userInteractionEnabled=NO;
        self.isAccessibilityElement=YES;
        _track=[CAShapeLayer layer]; _ring=[CAShapeLayer layer];
        for (CAShapeLayer *s in @[_track,_ring]) { s.fillColor=UIColor.clearColor.CGColor; s.lineWidth=3; s.lineCap=kCALineCapRound; [self.layer addSublayer:s]; }
        _track.strokeColor=[UIColor colorWithRed:.22 green:.9 blue:.39 alpha:.20].CGColor;
        _ring.strokeColor=[UIColor colorWithRed:.22 green:.95 blue:.39 alpha:1].CGColor;
        _bolt=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]];
        _bolt.tintColor=[UIColor colorWithRed:.22 green:.95 blue:.39 alpha:1]; _bolt.contentMode=UIViewContentModeScaleAspectFit; [self addSubview:_bolt];
        _separator=[UIView new]; _separator.backgroundColor=[UIColor colorWithWhite:1 alpha:.23]; [self addSubview:_separator];
        _primary=[UILabel new]; _secondary=[UILabel new];
        for (UILabel *l in @[_primary,_secondary]) { l.textColor=UIColor.whiteColor; l.textAlignment=NSTextAlignmentCenter; l.numberOfLines=1; l.adjustsFontSizeToFitWidth=YES; l.minimumScaleFactor=.65; [self addSubview:l]; }
        _primary.font=[UIFont systemFontOfSize:25 weight:UIFontWeightSemibold];
        _secondary.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _secondary.textColor=[UIColor colorWithWhite:1 alpha:.82];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height,mid=h/2;
    self.layer.cornerRadius=h/2;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    UIBezierPath *p=[UIBezierPath bezierPathWithArcCenter:CGPointMake(28,mid) radius:17 startAngle:-M_PI_2 endAngle:3*M_PI_2 clockwise:YES];
    _track.path=p.CGPath; _ring.path=p.CGPath;
    [CATransaction commit];
    _bolt.frame=CGRectMake(20,mid-12,16,24);
    _separator.frame=CGRectMake(53,mid-17,1,34);
    _primary.frame=CGRectMake(62,mid-24,w-70,29);
    _secondary.frame=CGRectMake(62,mid+6,w-70,17);
}
- (void)renderText:(NSString *)text level:(float)level {
    NSInteger percent=LSGCBatteryPercent(level);
    NSString *key=[NSString stringWithFormat:@"%@|%ld",text,(long)percent];
    if (!LSGCCapsuleNeedsRender(_renderKey,key,_primary.text,_secondary.text,text)) return;
    _renderKey=key;
    NSArray *lines=[text componentsSeparatedByString:@"\n"];
    _primary.text=lines.firstObject; _secondary.text=lines.count>1 ? lines[1] : @"";
    self.accessibilityLabel=[text stringByReplacingOccurrencesOfString:@"\n" withString:@"，"];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _ring.strokeEnd=percent<0 ? 0 : percent/100.0; // Real battery, never ETA progress.
    [CATransaction commit];
}
@end
