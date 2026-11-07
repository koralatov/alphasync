#import <Foundation/Foundation.h>

// The saved report stays marked as in progress until every final status is written.
// After a crash, that status and the pending entries identify an unfinished backup.
@interface ASBackupReport : NSObject
{
    NSURL* reportURL;
    NSMutableDictionary* contents;
    NSMutableArray* files;
}
- (id)initWithFolder:(NSString*)folder files:(NSArray*)entries error:(NSError**)error;
- (NSURL*)reportURL;
- (BOOL)recordFileAtIndex:(NSUInteger)index savedPath:(NSString*)path error:(NSString*)message saveError:(NSError**)error;
- (BOOL)finishWithStatus:(NSString*)status message:(NSString*)message error:(NSError**)error;
@end
