/** @file   ASBackupController.h
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
#import <Cocoa/Cocoa.h>
#import "ASNode.h"
#import "ASBackupReport.h"

@class ASDeviceController;

@interface ASBackupController : NSWindowController
{
    IBOutlet NSTextField* outletBackupItem;
    IBOutlet NSTextField* outletFilesRemaining;
    IBOutlet NSProgressIndicator* outletProgressIndicator;
    IBOutlet NSButton* outletStopDoneButton;
    NSStackView* backupLocationsView;
    NSTextField* backupHintField;
    NSButton* openBackupButton;

    NSString* currentSessionPath;
    NSString* currentSessionFinalPath;
    NSUInteger sessionFailedFiles;
    NSMutableArray* backupSessionPaths;
    NSMutableArray* backupItems;
    ASBackupReport* backupReport;
    BOOL saveBackupLogs;
    NSUInteger reportStartIndex;
    NSUInteger nextBackupItem;
    uint64_t bytesToBackup;
    uint64_t bytesSoFar;
    NSUInteger failedFiles;
    NSUInteger backupDeviceCount;
    ASDeviceController* deviceController;
    BOOL backupInFlight;
    NSString* pendingStopMessage;
    NSString* pendingStopStatus;
}

- (void)runBackupFor:(ASNode*)root controller:(ASDeviceController*)controller modalForWindow:(NSWindow*)window;
- (void)requestStopForTermination;

- (IBAction)actionStopDone:(id)sender;
- (IBAction)actionOpenBackupFolders:(id)sender;

@end
