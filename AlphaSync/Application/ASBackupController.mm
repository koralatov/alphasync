/** @file   ASBackupController.mm
 *  @brief  Manage backups
 *
 *
 *  Copyright (c) 2008-2013, tSoniq. http://tsoniq.com
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *
 *  	*	Redistributions of source code must retain the above copyright notice, this list of
 *  	    conditions and the following disclaimer.
 *  	*	Redistributions in binary form must reproduce the above copyright notice, this list
 *  	    of conditions and the following disclaimer in the documentation and/or other materials
 *  	    provided with the distribution.
 *  	*	Neither the name of tSoniq nor the names of its contributors may be used to endorse
 *  	    or promote products derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 *  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "ASBackupController.h"
#import "ASDeviceNode.h"
#import "ASAppletNode.h"
#import "ASFileNode.h"
#import "ASDeviceController.h"
#import "ASPreferenceController.h"
#import "AQFileUtilities.h"


using namespace ts;


#define kDeviceBackupMaxBackupsInOneDay (999)       /**< Don't allow more than this many backups in one day. */


#pragma mark    ----------  ASBackupItem  -----------


/** Class used to describe a backup action.
 */
@interface ASBackupItem : NSObject
{
    BOOL newDevice;         /**< Logical true if this is the first file for a new device. */
    ASFileNode* fileNode;
    NSString* appletName;
    NSString* deviceName;
}
- (id)initWithNewDevice:(BOOL)nd fileNode:(ASFileNode*)fn appletName:(NSString*)an deviceName:(NSString*)dn;
- (BOOL)newDevice;
- (ASFileNode*)fileNode;
- (NSString*)appletName;
- (NSString*)deviceName;
@end

@implementation ASBackupItem
- (id)initWithNewDevice:(BOOL)nd fileNode:(ASFileNode*)fn appletName:(NSString*)an deviceName:(NSString*)dn
{
    if ((self = [super init]))
    {
        newDevice = nd;
        fileNode = [fn retain];
        appletName = [an retain];
        deviceName = [dn retain];
    }
    return self;
}
- (void)dealloc
{
    [fileNode release];
    [appletName release];
    [deviceName release];
    [super dealloc];
}
- (BOOL)newDevice { return newDevice; }
- (ASFileNode*)fileNode { return fileNode; }
- (NSString*)appletName { return appletName; }
- (NSString*)deviceName { return deviceName; }

@end



#pragma mark    ----------  ASBackupController  -----------

@implementation ASBackupController


- (id)init
{
    if ((self = [super initWithWindowNibName:@"Backup"]))
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceDisconnected:)
                                                    name:kASDeviceControllerDeviceDisconnected object:nil];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [deviceController release];
    [pendingStopMessage release];
    [pendingStopStatus release];
    [backupItems release];
    [backupReport release];
    [currentSessionPath release];
    [super dealloc];
}

- (void)deviceDisconnected:(NSNotification*)notification
{
    (void)notification;
    // The driver frees the device after this notification.  Stop before the next timer tick.
    if (backupItems) [self stopBackup:@"Backup stopped because a NEO was disconnected." status:@"disconnected"];
}

/** Make a new device session path and create the necessary directories.
 *
 *  @param  deviceName  The device name, or nil to omit this from the backup path.
 *  @return             Logical TRUE if succeeded.
 */
- (BOOL)makeNewDeviceSessionPath:(NSString*)deviceName
{
    [currentSessionPath release];
    currentSessionPath = nil;

    /* Find a unique path string, formed from <root-path>/<device-name>/<date> and optionally appending an index
     * number to make the path unique. The <root-path> is specified in the user preferences.
     */
    NSString* rootPath = [[NSUserDefaults standardUserDefaults] stringForKey:kASPreferenceKeyBackupFolder];
    if (!rootPath) return FALSE;

    NSDateFormatter* formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setCalendar:[[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]];
    [formatter setDateFormat:@"yyyy-MM-dd"];
    NSString* dateName = [formatter stringFromDate:[NSDate date]];


    if (deviceName) rootPath = [rootPath stringByAppendingPathComponent:[deviceName stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];

    NSString* path = [rootPath stringByAppendingPathComponent:dateName];

    NSFileManager* fileManager = [NSFileManager defaultManager];
    int uniqueID = 1;
    while ([fileManager fileExistsAtPath:path])
    {
        if (uniqueID > kDeviceBackupMaxBackupsInOneDay) return FALSE;
        NSString* uniqueSuffix = [NSString stringWithFormat:@"%@ (%d)", dateName, uniqueID];
        path = [rootPath stringByAppendingPathComponent:uniqueSuffix];
        uniqueID ++;
    }


    /* Create the path.
     */
    if (!aq_FileUtilitiesCreateDirectoriesForPath(path)) return FALSE;

    currentSessionPath = [path retain];
    return TRUE;
}


/** Initialise a backup.
 */
- (BOOL)initBackup:(ASNode*)root
{
    assert(!backupItems);

    backupItems = [[NSMutableArray arrayWithCapacity:32] retain];
    nextBackupItem = 0;
    failedFiles = 0;
    bytesToBackup = 0;
    bytesSoFar = 0;

    for (NSUInteger i = 0; i != [root numberOfChildren]; i++)
    {
        ASDeviceNode* deviceNode = (ASDeviceNode*)[root childAtIndex:i];
        BOOL newDevice = TRUE;
        for (NSUInteger j = 0; j != [deviceNode numberOfChildren]; j++)
        {
            ASAppletNode* appletNode = (ASAppletNode*)[deviceNode childAtIndex:j];
            for (NSUInteger k = 0; k != [appletNode numberOfChildren]; k++)
            {
                ASFileNode* fileNode = (ASFileNode*)[appletNode childAtIndex:k];
                ASBackupItem* backupItem = [[[ASBackupItem alloc] initWithNewDevice:newDevice
                                                                  fileNode:fileNode
                                                                  appletName:[appletNode displayName]
                                                                  deviceName:[deviceNode displayName]] autorelease];
                [backupItems addObject:backupItem];
                newDevice = FALSE;
                bytesToBackup += static_cast<uint64_t>(MAX([fileNode fileSize], 0));
            }
        }
    }

    NSMutableArray* entries = [NSMutableArray arrayWithCapacity:[backupItems count]];
    for (ASBackupItem* item in backupItems)
        [entries addObject:@{@"device": [item deviceName] ?: @"", @"applet": [item appletName] ?: @"",
                             @"file": [[item fileNode] displayName] ?: @""}];
    NSString* folder = [[NSUserDefaults standardUserDefaults] stringForKey:kASPreferenceKeyBackupFolder];
    NSError* error = nil;
    backupReport = [[ASBackupReport alloc] initWithFolder:folder files:entries error:&error];
    if (!backupReport)
    {
        [self stopBackup:[NSString stringWithFormat:@"Backup could not start: %@", [error localizedDescription]] status:@"failed"];
        return NO;
    }

    [outletFilesRemaining setStringValue:[NSString stringWithFormat:@"Backing up %ld items", (unsigned long)[backupItems count]]];
    [outletBackupItem setStringValue:@""];
    [outletProgressIndicator setDoubleValue:0.0];
    [outletProgressIndicator startAnimation:self];
    [outletStopDoneButton setTitle:@"Stop"];
    [outletStopDoneButton setKeyEquivalent:@"\033"];  // use escape to stop
    return YES;
}


/** Stop the backup running.
 */
- (void)stopBackup:(NSString*)message status:(NSString*)status
{
    if (backupInFlight)
    {
        // Finish and record the current transfer before closing the report.  Stopping
        // between files avoids interrupting a NEO command halfway through its protocol.
        [pendingStopMessage release];
        [pendingStopStatus release];
        pendingStopMessage = [message copy];
        pendingStopStatus = [status copy];
        [outletFilesRemaining setStringValue:@"Stopping after the current file…"];
        [outletStopDoneButton setEnabled:NO];
        return;
    }
    [pendingStopMessage release]; pendingStopMessage = nil;
    [pendingStopStatus release]; pendingStopStatus = nil;
    NSError* reportError = nil;
    if (backupReport && ![backupReport finishWithStatus:status message:message error:&reportError])
        message = [message stringByAppendingFormat:@"  The final report could not be saved: %@", [reportError localizedDescription]];
    [backupReport release];
    backupReport = nil;
    [backupItems release];
    backupItems = nil;
    nextBackupItem = 0;
    bytesToBackup = 0;
    bytesSoFar = 0;

    [outletFilesRemaining setStringValue:message];
    [outletBackupItem setStringValue:@""];
    [outletProgressIndicator stopAnimation:self];
    [outletStopDoneButton setTitle:@"OK"];
    [outletStopDoneButton setKeyEquivalent:@"\r"];  // use return to dismiss
    [outletStopDoneButton setEnabled:YES];
}


/** Backup one item.
 */
- (void)backupOneItem
{
    if (!backupItems || backupInFlight) return;
    if (nextBackupItem >= [backupItems count])
    {
        [outletProgressIndicator setDoubleValue:100.0];
        NSString* message = failedFiles ? [NSString stringWithFormat:@"Backup finished with %lu failed files.", (unsigned long)failedFiles] : @"Backup complete";
        [self stopBackup:message status:@"complete"];
        return;
    }
    ASBackupItem* item = backupItems[nextBackupItem];
    ASFileNode* file = [item fileNode];
    [outletFilesRemaining setStringValue:[NSString stringWithFormat:@"Backing up %lu items", (unsigned long)([backupItems count] - nextBackupItem)]];
    [outletBackupItem setStringValue:[NSString stringWithFormat:@"%@: %@: %@", [item deviceName], [item appletName], [file displayName]]];
    backupInFlight = YES;
    [deviceController performTaskForNode:file refresh:NO task:^id(ASNode* working) {
        NSString* savedPath = nil;
        NSString* failure = nil;
        if ([item newDevice]) [self makeNewDeviceSessionPath:[item deviceName]];
        if (!currentSessionPath) failure = @"Unable to create the backup folder.";
        else
        {
            NSString* path = [currentSessionPath stringByAppendingPathComponent:[[item appletName] stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
            if (aq_FileUtilitiesCreateDirectoriesForPath(path))
            {
                NSString* filename = [(ASFileNode*)working saveUnderPath:path error:&failure];
                if (filename) savedPath = [path stringByAppendingPathComponent:filename];
            }
            else failure = @"Unable to create the applet backup folder.";
        }
        return @{@"path": savedPath ?: @"", @"error": failure ?: @""};
    } completion:^(id result, NSString* taskError) {
        backupInFlight = NO;
        NSString* path = [result[@"path"] length] ? result[@"path"] : nil;
        NSString* failure = taskError ?: ([result[@"error"] length] ? result[@"error"] : nil);
        if (!path)
        {
            ++failedFiles;
            failure = failure ?: @"The file could not be exported.";
        }
        NSError* reportError = nil;
        if (![backupReport recordFileAtIndex:nextBackupItem savedPath:path error:failure saveError:&reportError])
        {
            [self stopBackup:[NSString stringWithFormat:@"Backup stopped because its report could not be saved: %@", [reportError localizedDescription]] status:@"failed"];
            return;
        }
        bytesSoFar += static_cast<uint64_t>(MAX([file fileSize], 0));
        ++nextBackupItem;
        double progress = bytesToBackup ? double(bytesSoFar) / double(bytesToBackup) : double(nextBackupItem) / double([backupItems count]);
        [outletProgressIndicator setDoubleValue:progress * 100.0];
        if (pendingStopMessage)
        {
            NSString* message = [[pendingStopMessage copy] autorelease];
            NSString* status = [[pendingStopStatus copy] autorelease];
            [pendingStopMessage release]; pendingStopMessage = nil;
            [pendingStopStatus release]; pendingStopStatus = nil;
            [self stopBackup:message status:status];
        }
        else dispatch_async(dispatch_get_main_queue(), ^{ [self backupOneItem]; });
    }];
}


- (IBAction)actionStopDone:(id)sender
{
    NSWindow* sheet = [self window];

    if (backupItems)
    {
        // Backup still running
        [self stopBackup:@"Cancelled" status:@"cancelled"];
    }
    else
    {
        // Backup stopped
        [sheet orderOut:sender];
        [[sheet sheetParent] endSheet:sheet returnCode:NSModalResponseOK];
    }
}


- (void)runBackupFor:(ASNode*)root controller:(ASDeviceController*)controller modalForWindow:(NSWindow*)window
{
    if (backupItems) return;
    [outletProgressIndicator setUsesThreadedAnimation:YES];

    NSWindow* sheet = [self window];
    [window beginSheet:sheet completionHandler:nil];

    [deviceController release];
    deviceController = [controller retain];
    if (![self initBackup:root]) return;
    [self backupOneItem];
}


- (void)requestStopForTermination
{
    if (backupItems) [self stopBackup:@"Backup stopped because AlphaSync is closing." status:@"cancelled"];
}

@end
