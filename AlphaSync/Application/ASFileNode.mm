/** @file   ASFileNode.mm
 *  @brief  Node used to construct a tree representation of the contents of a device.
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
#import "ASFileNode.h"
#import "AQFileUtilities.h"
#include <limits.h>
#import "ASFileAttributes.h"
#import "ASFile.h"
#import "ASGenericFile.h"
#import "ASAlphaWordFile.h"
#import "ASUserDictionaryFile.h"
#import "ASAppletID.h"
#import "ASDeviceAccessProtocol.h"

using namespace ts;

static NSString* ASFileWriteMessage(const ASFileWriteError& error)
{
    switch (error.failure)
    {
        case ASFileWriteFailure::LimitsUnavailable:
            return @"AlphaSync couldn’t read the Neo’s maximum file size.  Disconnect and reconnect the Neo, then try again.  No files on the Neo have been changed.";
        case ASFileWriteFailure::FileTooLarge:
            return [NSString stringWithFormat:@"This file needs %@ on the Neo.  The maximum file size is %@.  Shorten the text or split it into smaller files, then try again.  No files on the Neo have been changed.",
                    aq_FormattedByteCount(error.required), aq_FormattedByteCount(error.maximum)];
        case ASFileWriteFailure::MemoryUnavailable:
            return @"AlphaSync couldn’t check the Neo’s available memory.  Disconnect and reconnect the Neo, then try again.  No files on the Neo have been changed.";
        case ASFileWriteFailure::FileUnavailable:
            return @"AlphaSync couldn’t check the existing file’s size on the Neo.  Disconnect and reconnect the Neo, then try again.  No files on the Neo have been changed.";
        case ASFileWriteFailure::InsufficientMemory:
            return [NSString stringWithFormat:@"There isn’t enough free memory on the Neo.  This file needs %@ after conversion; up to %@ is available for this import.  Free some space on the Neo, then try again.  No files on the Neo have been changed.",
                    aq_FormattedByteCount(error.required), aq_FormattedByteCount(error.available)];
        default:
            return @"The file could not be written to the Neo.  Check the connection and try again.";
    }
}

static NSString* ASReadTextFile(NSString* path, NSString** error)
{
    if (error) *error = nil;
    NSError* readError = nil;
    NSStringEncoding encoding;
    NSString* text = [NSString stringWithContentsOfFile:path usedEncoding:&encoding error:&readError];
    if (!text) text = [NSString stringWithContentsOfFile:path encoding:NSMacOSRomanStringEncoding error:&readError];
    if (!text && error) *error = [NSString stringWithFormat:@"The text file could not be read: %@", [readError localizedDescription]];
    return text;
}

static BOOL ASImportFileText(ASFile* file, BOOL plainText, NSString* text, NSString** error)
{
    NSData* unicodeData = [text dataUsingEncoding:NSUnicodeStringEncoding allowLossyConversion:NO];
    if (!file || !unicodeData || [unicodeData length] > UINT_MAX)
    {
        if (error) *error = @"Unable to read file contents.";
        return NO;
    }
    if (plainText && !file->canRepresentText((const uint16_t*)[unicodeData bytes], static_cast<unsigned>([unicodeData length])))
    {
        if (error) *error = @"The Neo cannot store one or more characters in this text.  Remove unsupported characters, such as emoji, and try again.  No files on the Neo have been changed.";
        return NO;
    }
    if (!file->importText((const uint16_t*)[unicodeData bytes], static_cast<unsigned>([unicodeData length])))
    {
        if (error) *error = @"The file could not be converted into the Neo’s format.  No files on the Neo have been changed.";
        return NO;
    }
    return YES;
}


@implementation ASFileNode


static NSImage* iconFileTxt = nil;              /**< Icon to use for text files. */
static NSImage* iconFileBin = nil;              /**< Icon to use for binary files. */



/** Class method used to create a new file on the device.
 *
 *  @param  devicePointer       The device that owns this node.
 *  @param  applet              The applet.
 *  @param  filename            The new node filename.
 *  @param  data                A pointer to the data to load to the device.
 *  @param  size                The number of bytes of data.
 *  @return                     A pointer to the created node. The node will be auto-released.
 */
+ (ASFileNode*)createFileNodeOnDevice:(ts::ASDevice*)device applet:(const ts::ASApplet*)applet filename:(NSString*)filename data:(const void*)data size:(unsigned)size error:(NSString**)error
{
    if (error) *error = nil;
    // Extract from the supplied path a filename to use on the device
    char deviceFilename[kASFileAttributesFileNameMaxSize + 1];
    const char* pathName = [filename cStringUsingEncoding:NSWindowsCP1252StringEncoding];
    if (!pathName) pathName = "Untitled";
    strncpy(deviceFilename, pathName, kASFileAttributesFileNameMaxSize);
    deviceFilename[kASFileAttributesFileNameMaxSize] = 0;


    // Ensure that the filename is unique by adding a suffix if necessary
    int uniqueID = 0;
    while (true)
    {
        bool isUnique = true;
        int fileIndexNumber = 0;
        ASFileAttributes attr;
        while (device->getFileAttributes(&attr, applet, fileIndexNumber++))
        {
            if (0 == strcasecmp(deviceFilename, attr.fileName()))
            {
                isUnique = false;
                break;
            }
        }

        if (isUnique) break;
        if (++ uniqueID > 999)
        {
            if (error) *error = @"A unique filename could not be chosen on the Neo.";
            return nil;
        }

        char buffer[8];
        snprintf(buffer, sizeof buffer, "-%d", uniqueID);

        strncpy(deviceFilename, pathName, kASFileAttributesFileNameMaxSize - strlen(buffer));
        deviceFilename[kASFileAttributesFileNameMaxSize - strlen(buffer)] = 0;
        strcat(deviceFilename, buffer);
    }


    // Create the file
    ASFileNode* node = nil;
    int fileIndexNumber;
    ASFileWriteError failure;
    if (device->createFile(deviceFilename, "write", data, size, applet, &fileIndexNumber, true, &failure))
    {
        ASFileAttributes attr;
        device->getFileAttributes(&attr, applet, fileIndexNumber);
        node = [[[ASFileNode alloc] initWithDevice:device applet:applet fileIndex:fileIndexNumber fileAttributes:&attr] autorelease];
    }
    else if (error) *error = ASFileWriteMessage(failure);
    return node;
}


/** Class method used to create a new file on the device.
 *
 *  @param  devicePointer       The device that owns this node.
 *  @param  applet              The applet.
 *  @param  path                The path of a file to be loaded.
 *  @return                     A pointer to the created node.
 */
+ (ASFileNode*)createFileNodeOnDevice:(ts::ASDevice*)device applet:(const ASApplet*)applet path:(NSString*)path error:(NSString**)error
{
    ASFileNode* fileNode = nil;
    ASFile* file = 0;
    NSString* contentsOfPath = ASReadTextFile(path, error);
    if (contentsOfPath)
    {
        switch (applet->appletID())
        {
            case kASAppletID_AlphaWord:             file = new ASAlphaWordFile;         break;
            case kASAppletID_Dictionary:            file = new ASUserDictionaryFile;    break;
            default:                                file = new ASGenericFile;           break;
        }
        BOOL plain = applet->appletID() == kASAppletID_AlphaWord || applet->appletID() == kASAppletID_Dictionary;
        if (ASImportFileText(file, plain, contentsOfPath, error))
        {
            NSString* deviceFilename = [[path lastPathComponent] stringByDeletingPathExtension];
            fileNode = [ASFileNode createFileNodeOnDevice:device applet:applet filename:deviceFilename
                                   data:file->fileData() size:file->fileSize() error:error];
        }
        delete file;
    }

    return fileNode;
}


/** Raise an error if the default constructor is used.
 */
- (id)init
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}


/** Designated initialiser. This will automatically try to enumerate the applets contained in the device.
 *
 *  @param  dev                 The device that owns this node.
 *  @param  app                 The applet.
 *  @param  fin                 The file index.
 *  @param  attr                The file attributes.
 *  @return                     A pointer to self.
 */
- (id)initWithDevice:(ts::ASDevice*)devicePtr applet:(const ts::ASApplet*)app fileIndex:(int)fin fileAttributes:(const ts::ASFileAttributes*)attr
{
    if ((self = [super init]))
    {
        if (!iconFileTxt)
        {
            NSBundle* bundle = [NSBundle mainBundle];
            iconFileTxt = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"icon-file-txt" ofType:@"pdf"]];
        }

        if (!iconFileBin)
        {
            NSBundle* bundle = [NSBundle mainBundle];
            iconFileBin = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"icon-file-bin" ofType:@"pdf"]];
        }

        fileIndex = fin;
        device = devicePtr;
        applet = new ASApplet(*app);
        fileAttributes = new ASFileAttributes(*attr);

        isFirstRefresh = YES;
        [self reload];
    }
    return self;
}


- (void)copyDisplayFieldsTo:(ASNode*)value
{
    ASFileNode* snapshot = (ASFileNode*)value;
    // Cache plain text while still on the device queue.  Inspectors and pasteboards then need no USB access.
    if (fileIsPlainText) [self fileData];
    snapshot->device = device;
    snapshot->applet = new ASApplet(*applet);
    snapshot->fileAttributes = new ASFileAttributes(*fileAttributes);
    snapshot->fileIndex = fileIndex;
    snapshot->fileExtension = fileExtension;
    snapshot->fileIsPlainText = fileIsPlainText;
    snapshot->filePreview = [filePreview copy];
}

- (void)dealloc
{
    [filePreview release];
    delete fileData;
    delete fileAttributes;
    delete applet;
    [super dealloc];
}


/** Refresh the tree.
 */
- (void)refresh
{
    // On the first call we already have valid attributes, so avoid the reload overhead
    if (isFirstRefresh || device->getFileAttributes(fileAttributes, applet, fileIndex))
    {
        isFirstRefresh = NO;

        NSImage* fileIcon;
        delete fileData;
        fileData = nullptr;
        fileIsSynchronised = NO;

        switch (applet->appletID())
        {
            case kASAppletID_AlphaWord:
                fileData = new ASAlphaWordFile;
                fileExtension = @"txt";
                fileIcon = iconFileTxt;
                fileIsPlainText = YES;
                break;

            case kASAppletID_Dictionary:
                fileData = new ASUserDictionaryFile;
                fileExtension = @"txt";
                fileIcon = iconFileTxt;
                fileIsPlainText = YES;
                break;

            default:
                fileData = new ASGenericFile;
                fileExtension = @"xml";
                fileIcon = iconFileBin;
                fileIsPlainText = NO;
                break;
        }

        fileData->setAppletInfo(applet->appletID(), applet->appletVersionMajor(), applet->appletVersionMinor());

        NSString* fileName = [NSString stringWithCString:fileAttributes->fileName() encoding:NSWindowsCP1252StringEncoding];

        [self setIcon:fileIcon];
        [self setDisplayName:fileName];
        [self setDisplayKind:[NSString stringWithFormat:@"File"]];
        [self setDisplaySize:aq_FormattedFileSize(fileAttributes->allocSize())];
        [self setFileSize:(int)fileAttributes->allocSize()];
        [self setFileSpace:(int)fileAttributes->fileSpace()];

        if (!fileIsSynchronised)
        {
            [filePreview release];
            filePreview = nil;

            if (fileIsPlainText && fileData->minimumLoadSize() != 0 && fileData->minimumLoadSize() <= 128)
            {
                if (fileData->load(device, applet, fileIndex, 128))
                {
                    const uint16_t* unicodeData;
                    unsigned unicodeSize;
                    if (!fileData->exportText(&unicodeData, &unicodeSize))
                    {
                        NSLog(@"Error translating text data from file %d for applet ID %04x", fileIndex, applet->appletID());
                    }
                    else
                    {
                        if (unicodeSize > 0) filePreview = [[NSString stringWithCharacters:unicodeData length:unicodeSize/2] retain];
                        else filePreview = @"";
                    }
                }
            }
        }
    }
    else
    {
        [self setIcon:nil];
        [self setDisplayName:@""];
        [self setDisplayKind:@"Dead"];
        [self setDisplaySize:@""];
        [self setFileSize:0];
        [self setFileSpace:0];
        [filePreview release];
        filePreview = nil;
    }

    [[self parent] refresh];
}


/** Reload only reloads the file attributes. Any existing cached file data is discarded.
 */
- (void)reload
{
    // Don't immediately reload the file data here, as this can take a (very) long time. The data will
    // be loaded on demand from the fileData method.
    fileIsSynchronised = FALSE;
    [self refresh];
}


- (BOOL)fileIsPlainText
{
    return fileIsPlainText;
}

- (const ts::ASFileAttributes*)fileAttributes
{
    return fileAttributes;
}


/** Return the parent applet node.
 */
- (ASAppletNode*)appletNode
{
    return (ASAppletNode*) [self parent];
}


/** Return the file index.
 */
- (int)fileIndex
{
    return fileIndex;
}


/** Return the file password.
 */
- (NSString*)password
{
    return [NSString stringWithCString:fileAttributes->password() encoding:NSWindowsCP1252StringEncoding];
}



/** Try to set a new filename.
 *
 *  @param  newName     The new name to try to use.
 *  @return             The actual name used (which may be completely different if the input made little sense).
 */
- (NSString*)setFileName:(NSString*)newName
{
    const char* newCName = [newName cStringUsingEncoding:NSWindowsCP1252StringEncoding];
    if (newCName && strlen(newCName) > 0)
    {
        fileAttributes->setFileName(newCName);
        device->setFileAttributes(applet, fileIndex, fileAttributes);   // Set the values
        device->getFileAttributes(fileAttributes, applet, fileIndex);   // Re-read them in case the device changes something
    }

    [self refresh];

    return [self displayName];
}


/** Find the basename and extension that would be used when saving the file to disk.
 *
 *  @param  basename    Returns the basename (filename without extension).
 *  @param  extension   Returns the file extension.
 */
- (void)getFileNameBase:(NSString**)basename extension:(NSString**)extension
{
    *basename = @"";
    *extension = fileExtension;

    // parse the device file name to remove any potentially problematic prefix characters
    char buffer[256];
    strncpy(buffer, fileAttributes->fileName(), sizeof buffer);
    buffer[255] = 0;
    char* deviceName = buffer;
    while (*deviceName != 0 && (*deviceName == '.' || *deviceName == '/' || *deviceName == ':'))
    {
        deviceName ++;
    }

    *basename = [NSString stringWithCString:deviceName encoding:NSWindowsCP1252StringEncoding];
    if (!*basename) *basename = @"";
    *basename = [*basename stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

    // If the device filename already has an appropriate extension remove it (to prevent a double extension).
    if (NSOrderedSame == [*extension caseInsensitiveCompare:[*basename pathExtension]])
    {
        *basename = [*basename stringByDeletingPathExtension];
    }
}


/** Return the file preview string, or nil if no preview text is available.
 */
- (NSString*)filePreview
{
    return filePreview;
}


/** Read the file, returning it as a string object.
 *
 *  @return                 The file data as a string, or zero if failed.
 */
- (NSString*)fileData
{
    if (displayOnly) return filePreview;
    NSString* result = nil;

    if (!fileIsSynchronised)
    {
        fileIsSynchronised = fileData->load(device, applet, fileIndex);
    }

    if (fileIsSynchronised)
    {
        const uint16_t* unicodeData;
        unsigned unicodeSize;
        if (!fileData->exportText(&unicodeData, &unicodeSize))
        {
            NSLog(@"Error translating text data from file %d for applet ID %04x", fileIndex, applet->appletID());
        }
        else
        {
            if (unicodeSize > 0) result = [NSString stringWithCharacters:unicodeData length:unicodeSize/2];
            else result = @"";
        }

        [filePreview release];
        if (fileIsPlainText) filePreview = [result retain];
        else filePreview = nil;
    }

    return result;
}


/** Set the file data, writing it to the device.
 *
 *  @param  data    The new file data.
 *  @param  error   Returns an error string if a problem occurs, or nil if successful. Pass NULL if not interested.
 *  @return         Logical true if the request succeeded.
 */
- (BOOL)setFileData:(NSString*)data error:(NSString**)error
{
    BOOL result = FALSE;
    NSString* message = nil;
    fileIsSynchronised = FALSE;
    if (ASImportFileText(fileData, fileIsPlainText, data, &message))
    {
        ASFileWriteError failure;
        result = fileData->save(device, applet, fileIndex, &failure);
        if (!result) message = ASFileWriteMessage(failure);
    }
    if (error) *error = message;
    [self setOperationError:message];
    [self reload];
    return result;
}




#pragma mark    --------  ASSaveProtocol  --------


- (BOOL)saveWillBeEmpty
{
    return [self fileSize] == 0;
}


- (void)saveFileCount:(unsigned*)fileCount totalBytes:(unsigned*)totalBytes
{
    *fileCount = 1;
    *totalBytes = fileAttributes->allocSize();
}

- (NSString*)saveUnderPath:(NSString*)path
{
    return [self saveUnderPath:path error:NULL];
}

- (NSString*)saveUnderPath:(NSString*)path error:(NSString**)errorMessage
{
    if (errorMessage) *errorMessage = nil;
    if (![path isAbsolutePath])
    {
        if (errorMessage) *errorMessage = @"The destination path is not absolute.";
        return nil;
    }
    id accessDelegate = [self delegate];
    BOOL hasDelegate = [accessDelegate conformsToProtocol:@protocol(ASDeviceAccessProtocol)];
    if (hasDelegate && ![accessDelegate deviceWillSave:self to:path sender:self]) return nil;

    NSString* error = nil;
    NSString* result = nil;
    NSString* text = [self fileData];
    NSData* data = nil;
    if (!text) error = @"Unable to read the file data from the device.";
    else
    {
        data = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
        if (!data) error = @"Unable to encode the file as UTF-8.";
    }

    if (data)
    {
        NSString* basename;
        NSString* extension;
        [self getFileNameBase:&basename extension:&extension];
        if (![basename length]) basename = @"unspecified";
        NSError* writeError = nil;
        result = aq_WriteUniqueFile(path, basename, extension, data, &writeError);
        if (!result)
        {
            error = [writeError localizedDescription];
            if (!error) error = @"Unable to finish writing the file.";
        }
    }
    if (errorMessage) *errorMessage = error;
    if (hasDelegate) [accessDelegate deviceDidSave:self error:error sender:self];
    return result;
}


#pragma mark    --------  ASLoadProtocol  --------


- (BOOL)loadPermittedFromPath:(NSString*)path
{
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return FALSE;

    switch (applet->appletID())
    {
        case kASAppletID_AlphaWord:
        case kASAppletID_Dictionary:
            if (!filePathConformsToUTI(path, @"public.plain-text")) return FALSE;
            break;

        default:
            if (!filePathConformsToUTI(path, @"public.xml")) return FALSE;
            break;
    }

    return TRUE;
}


/** Try to load the specified file.
 *
 *  @param  path        The path of the file to load.
 *  @return             Logical true if the file was loaded.
 */
- (BOOL)loadFromPath:(NSString*)path
{
    BOOL result = FALSE;

    NSString* readError = nil;
    NSString* contentsOfPath = ASReadTextFile(path, &readError);
    if (!contentsOfPath) [self setOperationError:readError];
    if (contentsOfPath)
    {
        BOOL shouldProceed = TRUE;

        id accessDelegate = [self delegate];
        if ([accessDelegate conformsToProtocol:@protocol(ASDeviceAccessProtocol)])
        {
            shouldProceed = [accessDelegate deviceWillReplace:self with:path sender:self];
        }

        if (shouldProceed)
        {
            NSString* error;
            result = [self setFileData:contentsOfPath error:&error];

            if ([accessDelegate conformsToProtocol:@protocol(ASDeviceAccessProtocol)])
            {
                [accessDelegate deviceDidReplace:self error:error sender:self];
            }
        }
    }

    return result;
}


- (BOOL)loadPermittedFromPaths:(NSArray*)paths
{
    if ([paths count] != 1) return FALSE;
    else return [self loadPermittedFromPath:[paths objectAtIndex:0]];
}


- (unsigned)loadFromPaths:(NSArray*)paths
{
    if ([paths count] != 1) return 0;
    else return [self loadFromPath:[paths objectAtIndex:0]] ? 1 : 0;
}




#pragma mark    --------  ASDeleteProtocol  --------

/** Return TRUE if the instance of the node can accept delete operations.
 */
- (BOOL)deletePermitted
{
    // Only permit delete for files if the applet allows it.
    ASAppletNode* appletNode = [self ancestorOfClass:[ASAppletNode class]];
    return [appletNode deletePermitted];
}


/** REVIEW: this was intended to remove the entire file. However, it is not clear if this is even
 *          possible with current Neo firmware, so it simply clears the content.
 */
- (BOOL)deleteSelf
{
    BOOL shouldProceed = TRUE;
    BOOL didDeleteFile = FALSE;

    id accessDelegate = [self delegate];
    if ([accessDelegate conformsToProtocol:@protocol(ASDeviceAccessProtocol)])
    {
        shouldProceed = [accessDelegate deviceWillDelete:self sender:self];
    }

    if (shouldProceed)
    {
        NSString* error = nil;
        didDeleteFile = [self setFileData:@"" error:&error];
        [self reload];

        if ([accessDelegate conformsToProtocol:@protocol(ASDeviceAccessProtocol)])
        {
            [accessDelegate deviceDidDelete:self error:error sender:self];
        }
    }

    return didDeleteFile;
}



@end
