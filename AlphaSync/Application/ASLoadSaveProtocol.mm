/** @file   ASLoadSaveProtocol.mm
 *  @brief  Protocol used for objects that can save themselves to local disk. This is used
 *          by ASNode derivatives to write themselves and their children to disk.
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
#import "ASLoadSaveProtocol.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define kMaxUniqueRetry (999)       /**< Try this many times to create a unique name, before giving up. */


/** Helper function used to construct directory paths. This may be useful to classes
 *  that implement ASSaveProtocol. The path is created on disk and its name is returned.
 *
 *  @bug    Needs to clean up any partially created directories if a late failure occurs. In practise this
 *          is very unlikely (eg: it would need the disk to become full partway through creating the path).
 *
 *  @param  rootPath        The base path. This must be an absolute path name and must exist for this
 *                          function to complete successfully.
 *  @param  extendedPath    The path extension. This is appended to the root path. If the requested
 *                          components already exist, their names will be modified to ensure that a
 *                          new unique path component results. Can pass nil if no extendedPath is required.
 *  @return                 The actual path that resulted (autorelease string), or nil if failed.
 */
NSString* makeFilesystemPath(NSString* rootPath, NSString* extendedPath)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDir;

    if (![rootPath isAbsolutePath]) return nil;                                     // root path must be absolute
    if (extendedPath && [extendedPath isAbsolutePath]) return nil;                  // extended path must not be absolute
    if (![fm fileExistsAtPath:rootPath isDirectory:&isDir] || !isDir) return nil;   // root path does not exist or is a file

	NSString* path = rootPath;

	NSArray* extendedPathComponents = [extendedPath pathComponents];
    NSEnumerator* enumerator = [extendedPathComponents objectEnumerator];
    NSString* component;
    while ((component = [enumerator nextObject]))
    {
        int uniqueID = 1;
        if ([component isEqualToString:@"."] || [component isEqualToString:@".."]) return nil;
        NSString* parentPath = path;
        path = [parentPath stringByAppendingPathComponent:component];

        while ([fm fileExistsAtPath:path] || ![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil])
        {
            if (uniqueID > kMaxUniqueRetry) return nil;             // bailing out - unable to make a unique name?
            NSString* uniqueSuffix = [NSString stringWithFormat:@"%@ (%d)", component, uniqueID];
            path = [parentPath stringByAppendingPathComponent:uniqueSuffix];
            uniqueID ++;
        }
    }

    return path;
}



/** Given a file path, obtain its UTI description.
 *
 *  @param  filePath    The file to query.
 *  @return             The UTI string. Returns an empty string if the filePath could not be queried.
 */
NSString* utiFromFilePath(NSString* filePath)
{
    NSURL* url = [NSURL fileURLWithPath:filePath];
    UTType* contentType = nil;
    if (![url getResourceValue:&contentType forKey:NSURLContentTypeKey error:nil]) return @"";
    NSString* identifier = [contentType identifier];
    return identifier ? identifier : @"";
}


/** Return logical true if a given file path confirms to a UTI.
 *
 *  @param  filePath    The path.
 *  @param  uti         The type to check.
 *  @return             Logical true if the file conforms.
 */
BOOL filePathConformsToUTI(NSString* filePath, NSString* uti)
{
    UTType* contentType = [UTType typeWithIdentifier:utiFromFilePath(filePath)];
    UTType* requestedType = [UTType typeWithIdentifier:uti];
    return contentType && requestedType && [contentType conformsToType:requestedType];
}

