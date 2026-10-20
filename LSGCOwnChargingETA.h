#import <Foundation/Foundation.h>
// All entry points main-only; UIDevice read only there. UI receives copied strings.
void LSGCOwnETAConfigure(BOOL enabled);
void LSGCOwnETAObserve(void);
BOOL LSGCOwnETAConnected(void);
NSString *LSGCOwnETAText(void);
NSString *LSGCOwnETADiagnostic(void);
