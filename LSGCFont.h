#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

// Both processes register locally. User/session scope is not reliable on iOS.
static UIFont *LSGCFontAtURL(NSURL *url, NSString *requested, CGFloat size,
                            NSString **postscript, NSString **family) {
    if (!url.isFileURL) return nil;
    NSArray *descriptors=CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
    if (!descriptors.count) return nil;
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,NULL);
    for (id item in descriptors) {
        CTFontDescriptorRef descriptor=(__bridge CTFontDescriptorRef)item;
        NSString *name=CFBridgingRelease(CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute));
        if (requested.length && ![requested isEqualToString:name]) continue;
        CTFontRef ct=CTFontCreateWithFontDescriptor(descriptor,size,NULL);
        if (!ct) continue;
        NSString *actual=CFBridgingRelease(CTFontCopyPostScriptName(ct));
        NSString *group=CFBridgingRelease(CTFontCopyFamilyName(ct));
        CFRelease(ct);
        UIFont *font=[UIFont fontWithName:name size:size];
        if (!font || ![font.fontName isEqualToString:actual]) continue;
        if (postscript) *postscript=actual;
        if (family) *family=group;
        return font;
    }
    return nil;
}
