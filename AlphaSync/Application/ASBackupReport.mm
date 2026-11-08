#import "ASBackupReport.h"
#import "AQFileUtilities.h"

@implementation ASBackupReport
- (id)initWithFolder:(NSString*)folder files:(NSArray*)entries error:(NSError**)error
{
    if ((self = [super init]))
    {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error])
        {
            [self release];
            return nil;
        }
        files = [[NSMutableArray alloc] initWithCapacity:[entries count]];
        for (NSDictionary* entry in entries)
        {
            NSMutableDictionary* file = [[entry mutableCopy] autorelease];
            file[@"status"] = @"pending";
            [files addObject:file];
        }
        contents = [@{@"formatVersion": @1, @"status": @"in progress", @"startedAt": [NSDate date], @"files": files} mutableCopy];
        NSData* data = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        NSString* name = data ? aq_WriteUniqueFile(folder, @"AlphaSync Backup Log", @"plist", data, error) : nil;
        if (!name)
        {
            [self release];
            return nil;
        }
        reportURL = [[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]] retain];
    }
    return self;
}

- (void)dealloc
{
    [reportURL release];
    [contents release];
    [files release];
    [super dealloc];
}

- (NSURL*)reportURL { return reportURL; }

- (BOOL)save:(NSError**)error
{
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    return data && [data writeToURL:reportURL options:NSDataWritingAtomic error:error];
}

- (BOOL)recordFileAtIndex:(NSUInteger)index savedPath:(NSString*)path error:(NSString*)message saveError:(NSError**)error
{
    if (index >= [files count]) return NO;
    NSMutableDictionary* file = files[index];
    file[@"status"] = path ? @"saved" : @"failed";
    if (path) file[@"path"] = path;
    if (message) file[@"error"] = message;
    return [self save:error];
}

- (BOOL)finishWithStatus:(NSString*)status message:(NSString*)message error:(NSError**)error
{
    // A caller cannot accidentally label a backup complete while any file is missing or failed.
    if ([status isEqualToString:@"complete"])
        for (NSDictionary* file in files)
            if (![file[@"status"] isEqualToString:@"saved"]) status = @"completed with failures";
    contents[@"status"] = status;
    contents[@"message"] = message;
    contents[@"finishedAt"] = [NSDate date];
    return [self save:error];
}
@end
