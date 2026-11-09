/** @file       AQFileUtilities.m
 *  @brief      General file support.
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
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include "AQFileUtilities.h"

/** Create a directory tree, with intermediate directories.
 *
 *  @param  directoryPath       The path to create.
 *  @return                     Logical true if the path was created.
 */
BOOL aq_FileUtilitiesCreateDirectoriesForPath(NSString* directoryPath)
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    return [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
}

NSString* aq_FormattedFileSize(unsigned long long byteCount)
{
    NSByteCountFormatter* formatter = [[[NSByteCountFormatter alloc] init] autorelease];
    [formatter setCountStyle:NSByteCountFormatterCountStyleFile];
    [formatter setAllowedUnits:NSByteCountFormatterUseBytes | NSByteCountFormatterUseKB];
    [formatter setAllowsNonnumericFormatting:NO];
    return [formatter stringFromByteCount:(long long)byteCount];
}

NSString* aq_SafePathComponent(NSString* name)
{
    NSString* safe = [[(name ?: @"") stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];
    safe = [[safe componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@"_"];
    return [safe length] ? safe : @"Untitled";
}

BOOL aq_RenameItemExclusively(NSString* source, NSString* destination, NSError** error)
{
    if (error) *error = nil;
    if (renamex_np([source fileSystemRepresentation], [destination fileSystemRepresentation], RENAME_EXCL) == 0) return YES;
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return NO;
}

BOOL aq_CreatePrivateDirectory(NSString* path, NSError** error)
{
    if (error) *error = nil;
    if (mkdir([path fileSystemRepresentation], 0700) == 0) return YES;
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return NO;
}

NSString* aq_FormattedByteCount(unsigned long long byteCount)
{
    NSNumberFormatter* formatter = [[[NSNumberFormatter alloc] init] autorelease];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setUsesGroupingSeparator:YES];
    [formatter setMaximumFractionDigits:0];
    NSString* count = [formatter stringFromNumber:[NSNumber numberWithUnsignedLongLong:byteCount]];
    return [NSString stringWithFormat:byteCount == 1 ? @"%@ byte" : @"%@ bytes", count];
}

NSString* aq_WriteUniqueFile(NSString* directory, NSString* basename, NSString* extension,
                            NSData* data, NSError** error)
{
    if (error) *error = nil;
    if (![directory isAbsolutePath] || ![basename length] || [basename containsString:@"/"] ||
        [extension containsString:@"/"] || !data)
    {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:nil];
        return nil;
    }

    // Stage in the destination directory so publication stays on the same volume.
    // A crash during the write can leave a hidden temporary file, never a completed-looking export.
    NSString* temporary = [directory stringByAppendingPathComponent:@".alphasync-XXXXXX"];
    char* temporaryPath = strdup([temporary fileSystemRepresentation]);
    if (!temporaryPath)
    {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
        return nil;
    }
    int descriptor = mkstemp(temporaryPath);
    if (descriptor < 0)
    {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        free(temporaryPath);
        return nil;
    }
    NSFileHandle* handle = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
    NSError* writeError = nil;
    BOOL written = [handle writeData:data error:&writeError] && [handle synchronizeAndReturnError:&writeError];
    NSError* closeError = nil;
    BOOL closed = [handle closeAndReturnError:&closeError];
    [handle release];
    NSString* result = nil;
    if (written && closed)
    {
        for (unsigned index = 0; index <= 999; ++index)
        {
            NSString* suffix = index ? [NSString stringWithFormat:@" (%u)", index] : @"";
            NSString* filename = [[basename stringByAppendingString:suffix] stringByAppendingPathExtension:extension];
            NSString* destination = [directory stringByAppendingPathComponent:filename];
            // Exclusive rename publishes the complete file in one step without a check-then-write race.
            if (renamex_np(temporaryPath, [destination fileSystemRepresentation], RENAME_EXCL) == 0)
            {
                result = filename;
                break;
            }
            if (errno != EEXIST || index == 999)
            {
                writeError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                break;
            }
        }
    }
    unlink(temporaryPath);
    free(temporaryPath);
    if (!result && error) *error = writeError ? writeError : closeError;
    return result;
}
