#import <objc/runtime.h>
static inline void MSHookMessageEx(Class cls,SEL selector,IMP replacement,IMP *original) {
    (void)replacement; if (original) *original=class_getMethodImplementation(cls,selector);
}
