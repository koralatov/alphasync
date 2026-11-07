/** @file   ASNodeDataSource.mm
 *  @brief
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

#import "ASNodeDataSource.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ASNode.h"
#import "ASDeviceNode.h"
#import "ASAppletNode.h"
#import "ASFileNode.h"
#import "ASDevice.h"
#import "ASApplet.h"
#import "ASFileAttributes.h"
#import "ASFile.h"
#import "ASAlphaWordFile.h"
#import "ASUserDictionaryFile.h"


using namespace ts;


// A file promise keeps the selected node alive until Finder has finished receiving it.
@interface ASFilePromise : NSFilePromiseProvider <NSFilePromiseProviderDelegate>
{
    ASNode* node;
    ASDeviceNode* owner;
    ASDeviceController* controller;
    NSString* filename;
    NSString* plainText;
}
- (id)initWithNode:(ASNode*)item controller:(ASDeviceController*)deviceController;
@end

@implementation ASFilePromise
- (id)initWithNode:(ASNode*)item controller:(ASDeviceController*)deviceController
{
    BOOL isFile = [item isKindOfClass:[ASFileNode class]];
    NSString* type = isFile ? ([(ASFileNode*)item fileIsPlainText] ? UTTypePlainText.identifier : UTTypeXML.identifier) : UTTypeFolder.identifier;
    if ((self = [super initWithFileType:type delegate:nil]))
    {
        self.delegate = self;
        node = [item retain];
        controller = [deviceController retain];
        owner = [([item isKindOfClass:[ASDeviceNode class]] ? item :
                  [item ancestorOfClass:[ASDeviceNode class]]) retain];
        NSString* name = [item displayName];
        if (isFile)
        {
            NSString* extension;
            [(ASFileNode*)item getFileNameBase:&name extension:&extension];
            name = [name stringByAppendingPathExtension:extension];
            if ([(ASFileNode*)item fileIsPlainText]) plainText = [[(ASFileNode*)item fileData] copy];
        }
        name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        filename = [(([name length] && ![name isEqualToString:@"."] && ![name isEqualToString:@".."]) ? name : @"Untitled") copy];
    }
    return self;
}

- (void)dealloc
{
    [node release];
    [owner release];
    [controller release];
    [filename release];
    [plainText release];
    [super dealloc];
}

- (NSArray*)writableTypesForPasteboard:(NSPasteboard*)pasteboard
{
    NSArray* types = [super writableTypesForPasteboard:pasteboard];
    return plainText ? [types arrayByAddingObject:NSPasteboardTypeString] : types;
}

- (id)pasteboardPropertyListForType:(NSString*)type
{
    if ([type isEqualToString:NSPasteboardTypeString]) return plainText;
    return [super pasteboardPropertyListForType:type];
}

- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)provider fileNameForType:(NSString*)type
{
    (void)provider;
    (void)type;
    return filename;
}

- (NSOperationQueue*)operationQueueForFilePromiseProvider:(NSFilePromiseProvider*)provider
{
    (void)provider;
    // Device callbacks and transfers share the main thread.  Two USB requests must not overlap.
    return [NSOperationQueue mainQueue];
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)provider writePromiseToURL:(NSURL*)url
         completionHandler:(void (^)(NSError*))completionHandler
{
    (void)provider;
    if (![[[controller systemRoot] children] containsObject:owner])
    {
        completionHandler([NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                          userInfo:@{NSLocalizedDescriptionKey: @"The NEO has been disconnected."}]);
        return;
    }
    NSFileManager* manager = [NSFileManager defaultManager];
    NSError* error = nil;
    NSURL* staging = [manager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
                            appropriateForURL:url create:YES error:&error];
    if (staging)
    {
        // Stage the export first, so Finder receives the exact filename it was promised.
        NSString* saved = [node saveUnderPath:[staging path]];
        if (saved)
        {
            NSString* savedPath = [saved isAbsolutePath] ? saved : [[staging path] stringByAppendingPathComponent:saved];
            [manager moveItemAtURL:[NSURL fileURLWithPath:savedPath] toURL:url error:&error];
        }
        else error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
        [manager removeItemAtURL:staging error:nil];
    }
    completionHandler(error);
}
@end

static NSArray* filePathsFromPasteboard(NSPasteboard* pasteboard)
{
    NSArray* urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                             options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    return [urls valueForKey:@"path"];
}


@implementation ASNodeDataSource


- (id)init
{
    if ((self = [super init]))
    {
        deviceController = nil;
    }
    return self;
}


- (void)dealloc
{
    [deviceController release];
    [super dealloc];
}


- (void)reloadData:(NSOutlineView*)view
{
    [view reloadData];
    NSEnumerator* deviceEnumerator = [[deviceController systemRoot] childEnumerator];
    ASNode* item;
    while ((item = [deviceEnumerator nextObject]))
    {
        [view expandItem:item expandChildren:YES];
    }
}


- (void)setDeviceController:(ASDeviceController*)controller
{
    if (deviceController != controller)
    {
        [deviceController release];
        deviceController = [controller retain];
    }
}




#pragma mark -
#pragma mark Methods that cause changes to the nodes (and hence device data)


- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item
{
    (void)outlineView;
	ASNode* node = (item == nil) ? [deviceController systemRoot] : item;
	return (NSInteger)[node numberOfChildren];
}


- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item
{
    (void)outlineView;
	ASNode* node = (item == nil) ? [deviceController systemRoot] : item;
	return [node childAtIndex:(NSUInteger)index];
}


- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item
{
    (void)outlineView;
	return ([item numberOfChildren] > 0);
}


- (id)outlineView:(NSOutlineView*)outlineView objectValueForTableColumn:(NSTableColumn*)tableColumn byItem:(id)item
{
    (void)outlineView;
	id result;

	NSString* key = [tableColumn identifier];
    if (NSOrderedSame == [key compare:@"Name"]) result = [item displayName];
    else if (NSOrderedSame == [key compare:@"Size"]) result = [item displaySize];
    else if (NSOrderedSame == [key compare:@"Kind"]) result = [item displayKind];
    else { assert(0); result = @"?"; }  // unknown display column

	return result;
}


- (void)outlineView:(NSOutlineView*)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn*)tableColumn byItem:(id)item
{
    (void)outlineView;
    (void)tableColumn;
    if ([item isMemberOfClass:[ASFileNode class]])
    {
        ASFileNode* node = (ASFileNode*)item;
        [node setFileName:object];
        [outlineView reloadData];
    }
}


- (BOOL)outlineView:(NSOutlineView*)outlineView isGroupItem:(id)item
{
    (void)outlineView;
    (void) item;
	return NO;
}


- (id<NSPasteboardWriting>)outlineView:(NSOutlineView*)outlineView pasteboardWriterForItem:(id)item
{
    (void)outlineView;
    if (![item conformsToProtocol:@protocol(ASSaveProtocol)]) return nil;
    return [[[ASFilePromise alloc] initWithNode:item controller:deviceController] autorelease];
}

- (NSDragOperation)outlineView:(NSOutlineView*)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)childIndex
{
    (void)outlineView;
    (void)childIndex;

    NSDragOperation result = NSDragOperationNone;

    NSPasteboard* pasteboard = [info draggingPasteboard];
    NSArray* filePaths = filePathsFromPasteboard(pasteboard);
    if ([filePaths count])
    {
        if ([item conformsToProtocol:@protocol(ASLoadProtocol)] && [item loadPermittedFromPaths:filePaths])
        {
            result = NSDragOperationCopy;
        }
    }
    return result;
}


- (BOOL)outlineView:(NSOutlineView*)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)childIndex
{
    (void)childIndex;

    BOOL result = FALSE;

    NSPasteboard* pasteboard = [info draggingPasteboard];
    NSArray* filePaths = filePathsFromPasteboard(pasteboard);
    if ([filePaths count])
    {
        if ([item conformsToProtocol:@protocol(ASLoadProtocol)] && [item loadPermittedFromPaths:filePaths])
        {
            result = ([item loadFromPaths:filePaths] > 0);      // return success if at least one file was loaded successfully
            if (result)
            {
                [item reload];
                [outlineView reloadData];
            }
        }
    }

    return result;
}

@end



