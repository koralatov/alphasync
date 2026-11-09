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
#include <errno.h>


using namespace ts;


#define kDeviceBackupMaxBackupsInOneDay (999)       /**< Don't allow more than this many backups in one day. */

static NSString* ASBackupFileCount(NSUInteger count)
{
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)count, count == 1 ? @"file" : @"files"];
}

static NSTextField* ASBackupLabel(NSString* text)
{
    NSTextField* field = [NSTextField wrappingLabelWithString:text];
    [field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [field setTextColor:[NSColor labelColor]];
    [field setPreferredMaxLayoutWidth:460];
    return field;
}

@interface ASBackupController ()
- (void)buildWindow;
- (void)fitWindowToContent;
- (void)showBackupProgress;
@end


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
    if ((self = [super initWithWindow:nil]))
    {
        backupSessionPaths = [[NSMutableArray alloc] init];
        [self buildWindow];
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
    [currentSessionFinalPath release];
    [backupSessionPaths release];
    [super dealloc];
}

- (void)buildWindow
{
    NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 240)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    [window setTitle:@"Backup"];
    [window setReleasedWhenClosed:NO];
    [window setAutorecalculatesKeyViewLoop:YES];
    [self setWindow:window];

    outletFilesRemaining = ASBackupLabel(@"");
    [outletFilesRemaining setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    outletBackupItem = ASBackupLabel(@"");
    outletProgressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSZeroRect] autorelease];
    [outletProgressIndicator setStyle:NSProgressIndicatorStyleBar];
    [outletProgressIndicator setIndeterminate:NO];
    [outletProgressIndicator setMinValue:0];
    [outletProgressIndicator setMaxValue:100];
    [outletProgressIndicator setAccessibilityLabel:@"Backup progress"];

    backupLocationsView = [NSStackView stackViewWithViews:@[]];
    [backupLocationsView setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [backupLocationsView setAlignment:NSLayoutAttributeLeading];
    [backupLocationsView setSpacing:8];
    backupHintField = ASBackupLabel(@"");
    openBackupButton = [NSButton buttonWithTitle:@"Open Backup Folder" target:self action:@selector(actionOpenBackupFolders:)];
    outletStopDoneButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(actionStopDone:)];
    NSView* spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSStackView* buttons = [NSStackView stackViewWithViews:@[spacer, openBackupButton, outletStopDoneButton]];
    [buttons setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [buttons setDistribution:NSStackViewDistributionFill];
    [buttons setAlignment:NSLayoutAttributeCenterY];
    [buttons setSpacing:12];
    [buttons setDetachesHiddenViews:YES];
    for (NSButton* button in @[openBackupButton, outletStopDoneButton])
    {
        [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }

    NSArray* rows = @[outletFilesRemaining, outletBackupItem, outletProgressIndicator, backupLocationsView, backupHintField, buttons];
    NSStackView* content = [NSStackView stackViewWithViews:rows];
    [content setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [content setAlignment:NSLayoutAttributeLeading];
    [content setSpacing:16];
    [content setDetachesHiddenViews:YES];
    [content setTranslatesAutoresizingMaskIntoConstraints:NO];
    for (NSView* row in rows)
        [[row widthAnchor] constraintEqualToAnchor:[content widthAnchor]].active = YES;
    NSView* container = [window contentView];
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [[content widthAnchor] constraintEqualToConstant:460],
        [[content leadingAnchor] constraintEqualToAnchor:[container leadingAnchor] constant:30],
        [[content trailingAnchor] constraintEqualToAnchor:[container trailingAnchor] constant:-30],
        [[content topAnchor] constraintEqualToAnchor:[container topAnchor] constant:24],
        [[content bottomAnchor] constraintEqualToAnchor:[container bottomAnchor] constant:-24]
    ]];
    [window setInitialFirstResponder:outletStopDoneButton];
    [self showBackupProgress];
    [window center];
}

- (void)fitWindowToContent
{
    NSWindow* window = [self window];
    NSRect oldFrame = [window frame];
    [window setContentSize:[[window contentView] fittingSize]];
    NSRect frame = [window frame];
    frame.origin.y = NSMaxY(oldFrame) - NSHeight(frame);
    [window setFrameOrigin:frame.origin];
}

- (void)showBackupProgress
{
    [outletFilesRemaining setStringValue:@"Backing up your files…"];
    [outletBackupItem setStringValue:@""];
    [outletProgressIndicator setHidden:NO];
    [outletProgressIndicator setDoubleValue:0];
    [backupLocationsView setHidden:YES];
    [backupHintField setHidden:YES];
    [openBackupButton setHidden:YES];
    [outletStopDoneButton setTitle:@"Stop"];
    [outletStopDoneButton setKeyEquivalent:@"\033"];
    [outletStopDoneButton setEnabled:YES];
    [self fitWindowToContent];
}

- (void)deviceDisconnected:(NSNotification*)notification
{
    (void)notification;
    // The driver frees the device after this notification.  Stop before the next timer tick.
    if (backupItems) [self stopBackup:@"Backup stopped because a Neo was disconnected." status:@"disconnected"];
}

/** Make a new device session path and create the necessary directories.
 *
 *  @param  deviceName  The device name, or nil to omit this from the backup path.
 *  @return             Logical TRUE if succeeded.
 */
- (BOOL)makeNewDeviceSessionPath:(NSString*)deviceName
{
    [currentSessionPath release]; currentSessionPath = nil;
    [currentSessionFinalPath release]; currentSessionFinalPath = nil;
    sessionFailedFiles = 0;
    NSString* rootPath = [[NSUserDefaults standardUserDefaults] stringForKey:kASPreferenceKeyBackupFolder];
    if (![rootPath isAbsolutePath]) return NO;
    if (deviceName) rootPath = [rootPath stringByAppendingPathComponent:aq_SafePathComponent(deviceName)];
    NSDateFormatter* formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setCalendar:[[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]];
    [formatter setDateFormat:@"yyyy-MM-dd"];
    NSString* dateName = [formatter stringFromDate:[NSDate date]];
    NSFileManager* manager = [NSFileManager defaultManager];
    NSDictionary* permissions = @{NSFilePosixPermissions: @0700};
    if (![manager createDirectoryAtPath:rootPath withIntermediateDirectories:YES attributes:permissions error:nil]) return NO;
    for (int index = 0; index <= kDeviceBackupMaxBackupsInOneDay; ++index)
    {
        NSString* name = index ? [NSString stringWithFormat:@"%@ (%d)", dateName, index] : dateName;
        NSString* final = [rootPath stringByAppendingPathComponent:name];
        NSString* path = [final stringByAppendingString:@" (Incomplete)"];
        if ([manager fileExistsAtPath:final] || [manager fileExistsAtPath:path]) continue;
        NSError* error = nil;
        if (!aq_CreatePrivateDirectory(path, &error))
        {
            if ([[error domain] isEqual:NSPOSIXErrorDomain] && [error code] == EEXIST) continue;
            return NO;
        }
        currentSessionPath = [path copy];
        currentSessionFinalPath = [final copy];
        [backupSessionPaths addObject:path];
        return YES;
    }
    return NO;
}


/** Initialise a backup.
 */
- (BOOL)initBackup:(ASNode*)root
{
    assert(!backupItems);

    backupItems = [[NSMutableArray arrayWithCapacity:32] retain];
    nextBackupItem = 0;
    failedFiles = 0;
    backupDeviceCount = 0;
    // Snapshot the option for this backup, even if Preferences changes during a transfer.
    saveBackupLogs = [[NSUserDefaults standardUserDefaults] boolForKey:kASPreferenceKeySaveBackupLogs];
    bytesToBackup = 0;
    bytesSoFar = 0;
    [currentSessionPath release]; currentSessionPath = nil;
    [backupSessionPaths removeAllObjects];
    [self showBackupProgress];

    if (![root listingIsComplete])
    {
        [self stopBackup:@"AlphaSync could not read the complete list of applets and files on your Neo. No files were copied. Reconnect your Neo and try again." status:@"failed"];
        return NO;
    }

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
                if (newDevice) ++backupDeviceCount;
                newDevice = FALSE;
                bytesToBackup += static_cast<uint64_t>(MAX([fileNode fileSize], 0));
            }
        }
    }

    [outletFilesRemaining setStringValue:[NSString stringWithFormat:@"Backing up %@", ASBackupFileCount([backupItems count])]];
    [outletBackupItem setStringValue:@""];
    [outletProgressIndicator setDoubleValue:0.0];
    [outletProgressIndicator startAnimation:self];
    [outletStopDoneButton setTitle:@"Stop"];
    [outletStopDoneButton setKeyEquivalent:@"\033"];  // use escape to stop
    [self fitWindowToContent];
    return YES;
}


/** Stop the backup running.
 */
- (void)stopBackup:(NSString*)message status:(NSString*)status
{
    if (backupInFlight)
    {
        // Finish and record the current transfer before closing the report.  Stopping
        // between files avoids interrupting a Neo command halfway through its protocol.
        [pendingStopMessage release];
        [pendingStopStatus release];
        pendingStopMessage = [message copy];
        pendingStopStatus = [status copy];
        [outletFilesRemaining setStringValue:@"Stopping after the current file…"];
        [outletStopDoneButton setEnabled:NO];
        [self fitWindowToContent];
        return;
    }
    [pendingStopMessage release]; pendingStopMessage = nil;
    [pendingStopStatus release]; pendingStopStatus = nil;
    NSUInteger total = [backupItems count];
    NSUInteger saved = nextBackupItem - failedFiles;
    NSUInteger pending = total - nextBackupItem;
    BOOL completed = [status isEqualToString:@"complete"];
    BOOL successful = completed && !failedFiles && !pending;
    NSString* title = completed ? @"Backup incomplete" : @"Backup stopped";
    if ([status isEqualToString:@"failed"]) title = @"Backup incomplete";
    NSString* summary = nil;
    if (successful && total)
    {
        title = @"Backup complete";
        NSString* source = backupDeviceCount > 1 ? [NSString stringWithFormat:@"%lu Neos", (unsigned long)backupDeviceCount] : @"your Neo";
        summary = [NSString stringWithFormat:@"AlphaSync has saved %@ of %@ from %@. The original files on your %@ have not been changed.",
                   saved == 1 ? @"a copy" : @"copies", ASBackupFileCount(saved), source, backupDeviceCount > 1 ? @"Neos" : @"Neo"];
    }
    else if (successful)
    {
        title = @"No files to back up";
        summary = @"AlphaSync found no files to back up. No backup files were created.";
    }
    else
    {
        summary = [NSString stringWithFormat:@"AlphaSync saved %lu of %@.", (unsigned long)saved, ASBackupFileCount(total)];
        if (failedFiles) summary = [summary stringByAppendingFormat:@" %@ could not be backed up.", ASBackupFileCount(failedFiles)];
        if (pending) summary = [summary stringByAppendingFormat:@" %@ %@ not copied.", ASBackupFileCount(pending), pending == 1 ? @"was" : @"were"];
        if (!completed && ![message isEqualToString:@"Cancelled"]) summary = [summary stringByAppendingFormat:@" %@", message];
        summary = [summary stringByAppendingFormat:@" The original files on your %@ have not been changed.", backupDeviceCount > 1 ? @"Neos" : @"Neo"];
    }
    NSError* reportError = nil;
    if (backupReport && ![backupReport finishWithStatus:status message:summary error:&reportError])
    {
        title = @"Backup incomplete";
        summary = [summary stringByAppendingFormat:@"  The backup log could not be saved: %@", [reportError localizedDescription]];
    }
    [backupReport release];
    backupReport = nil;
    [backupItems release];
    backupItems = nil;
    nextBackupItem = 0;
    bytesToBackup = 0;
    bytesSoFar = 0;

    [outletFilesRemaining setStringValue:title];
    [outletBackupItem setStringValue:summary];
    [outletProgressIndicator stopAnimation:self];
    [outletProgressIndicator setHidden:YES];
    for (NSView* view in [[[backupLocationsView arrangedSubviews] copy] autorelease])
    {
        [backupLocationsView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    BOOL hasFolders = [backupSessionPaths count] > 0;
    if (hasFolders)
    {
        NSTextField* label = ASBackupLabel(saved ? @"Saved to:" : @"Backup folder:");
        [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [backupLocationsView addArrangedSubview:label];
        for (NSString* path in backupSessionPaths)
        {
            NSTextField* location = ASBackupLabel([path stringByAbbreviatingWithTildeInPath]);
            [location setSelectable:YES];
            [[location cell] setLineBreakMode:NSLineBreakByCharWrapping];
            [location setToolTip:path];
            [location setIdentifier:@"backup-location"];
            [backupLocationsView addArrangedSubview:location];
        }
        for (NSView* view in [backupLocationsView arrangedSubviews])
            [[view widthAnchor] constraintEqualToAnchor:[backupLocationsView widthAnchor]].active = YES;
    }
    [backupLocationsView setHidden:!hasFolders];
    [backupHintField setStringValue:[backupSessionPaths count] > 1 ? @"Open the backup folders to view your saved files in Finder." :
                                                                  @"Open the backup folder to view your saved files in Finder."];
    [backupHintField setHidden:!hasFolders || !saved];
    [openBackupButton setTitle:[backupSessionPaths count] > 1 ? @"Open Backup Folders" : @"Open Backup Folder"];
    [openBackupButton setHidden:!hasFolders];
    [outletStopDoneButton setTitle:@"Done"];
    [outletStopDoneButton setKeyEquivalent:@"\r"];  // use return to dismiss
    [outletStopDoneButton setEnabled:YES];
    [self fitWindowToContent];
}

- (IBAction)actionOpenBackupFolders:(id)sender
{
    (void)sender;
    for (NSString* path in backupSessionPaths)
        if (![[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path isDirectory:YES]])
        {
            NSAlert* alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"The backup folder could not be opened."];
            [alert setInformativeText:[NSString stringWithFormat:@"Check that the folder is still available at:\n%@", path]];
            [alert beginSheetModalForWindow:[self window] completionHandler:nil];
            break;
        }
}


/** Backup one item.
 */
- (void)backupOneItem
{
    if (!backupItems || backupInFlight) return;
    if (nextBackupItem >= [backupItems count])
    {
        [outletProgressIndicator setDoubleValue:100.0];
        [self stopBackup:@"Backup complete" status:@"complete"];
        return;
    }
    ASBackupItem* item = backupItems[nextBackupItem];
    ASFileNode* file = [item fileNode];
    NSMutableArray* entries = nil;
    if ([item newDevice] && saveBackupLogs)
    {
        reportStartIndex = nextBackupItem;
        entries = [NSMutableArray array];
        for (NSUInteger index = nextBackupItem; index < [backupItems count]; ++index)
        {
            ASBackupItem* next = backupItems[index];
            if (index != nextBackupItem && [next newDevice]) break;
            [entries addObject:@{@"device": [next deviceName] ?: @"", @"applet": [next appletName] ?: @"",
                                 @"file": [[next fileNode] displayName] ?: @""}];
        }
    }
    [outletFilesRemaining setStringValue:[NSString stringWithFormat:@"Backing up %@", ASBackupFileCount([backupItems count] - nextBackupItem)]];
    [outletBackupItem setStringValue:[NSString stringWithFormat:@"%@: %@: %@", [item deviceName], [item appletName], [file displayName]]];
    [self fitWindowToContent];
    backupInFlight = YES;
    [deviceController performTaskForNode:file refresh:NO task:^id(ASNode* working) {
        NSString* savedPath = nil;
        NSString* failure = nil;
        if ([item newDevice])
        {
            if ([self makeNewDeviceSessionPath:[item deviceName]] && saveBackupLogs)
            {
                NSError* error = nil;
                backupReport = [[ASBackupReport alloc] initWithFolder:currentSessionPath files:entries error:&error];
                if (!backupReport) return @{@"logError": [error localizedDescription] ?: @"The backup log could not be created."};
            }
        }
        if (!currentSessionPath) failure = @"Unable to create the backup folder.";
        else
        {
            NSString* path = [currentSessionPath stringByAppendingPathComponent:aq_SafePathComponent([item appletName])];
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
        if (result[@"logError"])
        {
            [self stopBackup:[NSString stringWithFormat:@"Backup stopped because its log could not be created: %@", result[@"logError"]] status:@"failed"];
            return;
        }
        NSString* path = [result[@"path"] length] ? result[@"path"] : nil;
        NSString* failure = taskError ?: ([result[@"error"] length] ? result[@"error"] : nil);
        if (!path)
        {
            ++failedFiles;
            ++sessionFailedFiles;
            failure = failure ?: @"The file could not be exported.";
        }
        NSError* reportError = nil;
        // The transfer has finished even if saving its optional log now fails.
        NSUInteger finishedItem = nextBackupItem++;
        if (backupReport && ![backupReport recordFileAtIndex:finishedItem - reportStartIndex savedPath:path error:failure saveError:&reportError])
        {
            [self stopBackup:[NSString stringWithFormat:@"Backup stopped because its log could not be saved: %@", [reportError localizedDescription]] status:@"failed"];
            return;
        }
        BOOL deviceFinished = nextBackupItem == [backupItems count] || [backupItems[nextBackupItem] newDevice];
        if (deviceFinished)
        {
            if (backupReport && ![backupReport finishWithStatus:@"complete" message:@"Backup finished for this Neo." error:&reportError])
            {
                [self stopBackup:[NSString stringWithFormat:@"Backup stopped because its log could not be saved: %@", [reportError localizedDescription]] status:@"failed"];
                return;
            }
            [backupReport release];
            backupReport = nil;
            if (!sessionFailedFiles && !pendingStopMessage)
            {
                NSError* error = nil;
                if (!aq_RenameItemExclusively(currentSessionPath, currentSessionFinalPath, &error))
                {
                    [self stopBackup:[NSString stringWithFormat:@"The files were copied, but the folder could not be marked complete: %@", [error localizedDescription]] status:@"failed"];
                    return;
                }
                NSUInteger index = [backupSessionPaths indexOfObject:currentSessionPath];
                if (index != NSNotFound) [backupSessionPaths replaceObjectAtIndex:index withObject:currentSessionFinalPath];
                [currentSessionPath release]; currentSessionPath = [currentSessionFinalPath copy];
            }
        }
        bytesSoFar += static_cast<uint64_t>(MAX([file fileSize], 0));
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
    NSWindow* sheet = [self window];
    [outletProgressIndicator setUsesThreadedAnimation:YES];
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
