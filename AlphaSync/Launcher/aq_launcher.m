/** @file       aq_launcher.m
 *  @brief      Launcher service library.
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
#include <CoreFoundation/CoreFoundation.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <assert.h>
#include "aq_launcher.h"
#include "aq_launcherconfig.h"
#include "aq_launcherprivate.h"


#pragma mark    ----------  Definitions  ----------


/* Debug log macros.
 */
#define LOG(...)        do { fprintf(stderr, "Launcher:: %s: ", __FUNCTION__); fprintf(stderr, __VA_ARGS__); } while (0)
#define LOG_ERROR(...)  do { fprintf(stderr, "Launcher:: FAIL:: %s: ", __FUNCTION__); fprintf(stderr, __VA_ARGS__); } while (0)


/** The session handle.
 */
struct AQLauncher
{
    CFStringRef m_path;                         /**< Application path for this session. */
    int m_flushNeeded;                          /**< Set non-zero if a call to flush is required before final close. */
    struct AQLaunchItem* m_items;               /**< List of launch items. */
    struct AQLaunchItem* m_nextToEnumerate;     /**< Next item in enumeration. */
    CFMessagePortRef m_controlPort;             /**< Mach message port used for client-server communication. */
};


/** Structure describing device matching criteria and an application to open on detection.
 */
struct AQLaunchItem
{
    struct AQLaunchItem* m_next;        /**< Next item in list. */
    CFStringRef m_applicationID;        /**< Application to launch. */
    SInt32 m_vendorID;                  /**< USB device's vendor ID, or -1 to match any vendor. */
    SInt32 m_productID;                 /**< USB device's product ID, or -1 to match any product. */
};



/* Forward declarations.
 */
static int aq_launcherServerConnect(AQLauncherRef lh);
static void aq_launcherServerDisconnect(AQLauncherRef lh);
static uint32_t aq_launcherServerGetVersion(AQLauncherRef lh);
static void aq_launcherServerLoadPreferences(AQLauncherRef lh);
static void aq_launcherServerQuit(AQLauncherRef lh);



#pragma mark    ----------  Server Control  ----------



/** Connect to the server application message port. On return the session handle's m_controlPort handle
 *  will have been initialised or set to zero if no client is running.
 *
 *  @param  lh      The session handle.
 *  @return         Logical true if a connection was established.
 */
static int aq_launcherServerConnect(AQLauncherRef lh)
{
    if (!lh->m_controlPort)
    {
        lh->m_controlPort = CFMessagePortCreateRemote(NULL, kAQLauncherControlPort);
        if (lh->m_controlPort)
        {
            uint32_t version = aq_launcherServerGetVersion(lh);
            if ((version & 0xff00) != (kAQLauncherVersion & 0xff00))
            {
                LOG_ERROR("Incompatible client-server versions: want %04x got %04x\n", kAQLauncherVersion, version);
                aq_launcherServerDisconnect(lh);
            }
            else
            {
                // connected
            }
        }
    }

    return (0 != lh->m_controlPort);
}


/** Disconnect from the server.
 *
 *  @param  lh      The session handle.
 */
static void aq_launcherServerDisconnect(AQLauncherRef lh)
{
    if (0 != lh->m_controlPort)
    {
        CFRelease(lh->m_controlPort);
        lh->m_controlPort = 0;
        // disconnected
    }
}



/** Get the server version number.
 *
 *  @param  lh      The session handle.
 *  @return         The server version, or zero if no server is available.
 */
static uint32_t aq_launcherServerGetVersion(AQLauncherRef lh)
{
    uint32_t version = 0;

    if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
    if (0 != lh->m_controlPort)
    {
        CFDataRef replyData = 0;
        SInt32 status = CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_Version, (CFDataRef)NULL, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
        if (kCFMessagePortSuccess == status)
        {
            assert(CFDataGetLength(replyData) == 4);
            if (CFDataGetLength(replyData) == 4) CFDataGetBytes(replyData, CFRangeMake(0, 4), (UInt8*)&version);
            CFRelease(replyData);
        }
    }
    return version;
}


/** Start the server.
 *
 *  @param  lh      The session handle.
 */
static void aq_launcherServerStart(AQLauncherRef lh)
{
    CFDataRef replyData = 0;
    if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
    if (0 != lh->m_controlPort) CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_Start, (CFDataRef)NULL, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
    if (replyData) CFRelease(replyData);
}


/** Stop the server.
 *
 *  @param  lh      The session handle.
 */
static void aq_launcherServerStop(AQLauncherRef lh)
{
    CFDataRef replyData = 0;
    if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
    if (0 != lh->m_controlPort) CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_Stop, (CFDataRef)NULL, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
    if (replyData) CFRelease(replyData);
}


/** Pause the server.
 *
 *  @param  lh      The session handle.
 *  @param  seconds The number of seconds to pause.
 */
static void aq_launcherServerPause(AQLauncherRef lh, float seconds)
{
    CFDataRef replyData = 0;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, (UInt8*)&seconds, sizeof seconds);
    assert(data);
    if (data)
    {
        if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
        if (0 != lh->m_controlPort) CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_PauseThenStart, data, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
        if (replyData) CFRelease(replyData);
        CFRelease(data);
    }
}


/** Quit the server.
 *
 *  @param  lh      The session handle.
 */
static void aq_launcherServerQuit(AQLauncherRef lh)
{
    CFDataRef replyData = 0;
    if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
    if (0 != lh->m_controlPort) CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_Quit, (CFDataRef)NULL, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
    if (replyData) CFRelease(replyData);
}


/** Ask the server to reload preference data.
 *
 *  @param  lh      The session handle.
 */
static void aq_launcherServerLoadPreferences(AQLauncherRef lh)
{
    CFDataRef replyData = 0;
    if (0 == lh->m_controlPort) aq_launcherServerConnect(lh);
    if (0 != lh->m_controlPort) CFMessagePortSendRequest(lh->m_controlPort, kAQLauncherControlMsgID_LoadPreferences, (CFDataRef)NULL, 1.0, 1.0, kCFRunLoopDefaultMode, &replyData);
    if (replyData) CFRelease(replyData);
}





#pragma mark    ----------  Local Functions  ----------


/** Find an existing item.
 *
 *  @param  app     The application bundle ID.
 *  @param  vendor  The USB vendor ID, or -1 for any vendor.
 *  @param  product The USB product ID, or -1 for any product.
 *  @return         The item reference or zero if not found.
 */
static struct AQLaunchItem* aq_launcherFindItem(AQLauncherRef lh, CFStringRef app, SInt32 vendor, SInt32 product)
{
    struct AQLaunchItem* item = lh->m_items;
    while (item)
    {
        if ((kCFCompareEqualTo == CFStringCompare(item->m_applicationID, app, 0)) &&
            (vendor == item->m_vendorID) &&
            (product == item->m_productID))
        {
            break;
        }
        item = item->m_next;
    }
    return item;
}


/** Create a new launch item.
 *
 *  @param  lh          The session handle.
 *  @param  app         The application bundle ID.
 *  @param  vendorID    The USB vendor ID.
 *  @param  productID   The USB product ID.
 *  @return             Non-zero if the list was changed.
 */
static int aq_launcherAddItem(AQLauncherRef lh, CFStringRef app, SInt32 vendorID, SInt32 productID)
{
    int changed = 0;
    struct AQLaunchItem* item = aq_launcherFindItem(lh, app, vendorID, productID);
    if (0 == item)
    {
        item = (struct AQLaunchItem*)malloc(sizeof (struct AQLaunchItem));
        if (item)
        {
            CFRetain(app);
            item->m_applicationID = app;
            item->m_vendorID = vendorID;
            item->m_productID = productID;
            item->m_next = 0;

            if (0 == lh->m_items)
            {
                lh->m_items = item;
            }
            else
            {
                struct AQLaunchItem* l = lh->m_items;
                while (l->m_next) l = l->m_next;
                l->m_next = item;
            }

            changed = 1;
        }
    }

    return changed;
}


/** Delete a specified item on the launch list.
 *
 *  @param  lh      The session handle.
 *  @param  item    The item to delete.
 *  @return         Non-zero if the list was changed.
 */
static int aq_launcherDeleteItem(AQLauncherRef lh, AQLaunchItemRef item)
{
    int changed = 0;

    struct AQLaunchItem* prev = 0;
    struct AQLaunchItem* search = lh->m_items;
    while (search && search != item)
    {
        prev = search;
        search = search->m_next;
    }

    if (search)
    {
        if (!prev) lh->m_items = search->m_next;
        else prev->m_next = search->m_next;

        if (lh->m_nextToEnumerate == search) lh->m_nextToEnumerate = search->m_next;

        CFRelease(search->m_applicationID);
        search->m_applicationID = 0;
        search->m_vendorID = 0;
        search->m_productID = 0;
        free(search);

        changed = 1;
    }

    return changed;
}


/** Delete all items on the launch list.
 *
 *  @param  lh      The session handle.
 *  @return         Non-zero if the list was changed.
 */
static int aq_launcherDeleteAllItems(AQLauncherRef lh)
{
    int changed = (0 != lh->m_items);

    struct AQLaunchItem* item = lh->m_items;
    while (item)
    {
        struct AQLaunchItem* next = item->m_next;
        CFRelease(item->m_applicationID);
        free(item);
        item = next;
    }

    lh->m_items = 0;
    lh->m_nextToEnumerate = 0;

    return changed;
}



/** Release the preference data. This only deletes the local copy - the information
 *  saved to disk is left unchanged.
 *
 *  @param  lh          The session handle.
 */
static void aq_launcherReleasePreferences(AQLauncherRef lh)
{
    struct AQLaunchItem* item = (struct AQLaunchItem*)aq_LauncherGetFirstLaunchItem(lh);
    while (item)
    {
        aq_LauncherDeleteLaunchItem(lh, item);
        item = (struct AQLaunchItem*)aq_LauncherGetNextLaunchItem(lh);
    }
}


/** Load the preference data.
 *
 *  @param  lh          The session handle.
 */
static void aq_launcherLoadPreferences(AQLauncherRef lh)
{
    aq_launcherReleasePreferences(lh);

    CFArrayRef launchList = CFPreferencesCopyAppValue(kPreferenceKeyLaunchList, kAQLauncherPreferenceID);
    if (0 != launchList && CFArrayGetTypeID() == CFGetTypeID(launchList))
    {
        int idx = 0;
        while (idx < CFArrayGetCount(launchList))
        {
            CFDictionaryRef dict = CFArrayGetValueAtIndex(launchList, idx);
            if (dict && CFDictionaryGetTypeID() == CFGetTypeID(dict))
            {
                CFStringRef app = CFDictionaryGetValue(dict, kPreferenceKeyAppID);
                CFNumberRef nvendor = CFDictionaryGetValue(dict, kPreferenceKeyUsbVendorID);
                CFNumberRef nproduct = CFDictionaryGetValue(dict, kPreferenceKeyUsbProductID);
                SInt32 vendor;
                SInt32 product;
                if (CFNumberGetValue(nvendor, kCFNumberSInt32Type, &vendor) &&
                    CFNumberGetValue(nproduct, kCFNumberSInt32Type, &product))
                {
                    aq_launcherAddItem(lh, app, vendor, product);
                }
            }
            idx ++;
        }
    }
    if (0 != launchList) CFRelease(launchList);
}


/** Save the preference data.
 *
 *  @param  lh          The session handle.
 */
static void aq_launcherSavePreferences(AQLauncherRef lh)
{
    CFMutableArrayRef launchList = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    assert(launchList);
    if (!launchList) return;

    struct AQLaunchItem* item = lh->m_items;
    while (item)
    {
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        assert(dict);
        if (!dict) return;

        CFNumberRef vendorID = CFNumberCreate(NULL, kCFNumberSInt32Type, &item->m_vendorID);
        CFNumberRef productID = CFNumberCreate(NULL, kCFNumberSInt32Type, &item->m_productID);

        CFDictionaryAddValue(dict, kPreferenceKeyAppID, item->m_applicationID);
        CFDictionaryAddValue(dict, kPreferenceKeyUsbVendorID, vendorID);
        CFDictionaryAddValue(dict, kPreferenceKeyUsbProductID, productID);

        CFRelease(vendorID);
        CFRelease(productID);

        CFArrayAppendValue(launchList, dict);

        CFRelease(dict);

        item = item->m_next;
    }

    CFPreferencesSetAppValue(kPreferenceKeyLaunchList, launchList, kAQLauncherPreferenceID);
    CFPreferencesAppSynchronize(kAQLauncherPreferenceID);

    CFRelease(launchList);
}



#pragma mark    ----------  Exported API  ----------



AQLauncherRef aq_LauncherOpen(CFStringRef path)
{
    AQLauncherRef lh = (AQLauncherRef)malloc(sizeof *lh);
    if (lh)
    {
        memset(lh, 0, sizeof *lh);

        lh->m_path = path ? CFRetain(path) : NULL;
        lh->m_flushNeeded = 0;
        lh->m_items = 0;
        lh->m_nextToEnumerate = 0;
        lh->m_controlPort = 0;

        aq_launcherLoadPreferences(lh);

        if (lh->m_path)
        {
            if (![[NSFileManager defaultManager] fileExistsAtPath:(NSString*)lh->m_path])
            {
                NSLog(@"The bundled launcher is missing: %@", (NSString*)lh->m_path);
                aq_LauncherClose(lh);
                lh = NULL;
            }
        }
    }
    return lh;
}


void aq_LauncherClose(AQLauncherRef lh)
{
    if (0 != lh)
    {
        if (lh->m_flushNeeded) aq_LauncherFlushLaunchItems(lh);
        lh->m_flushNeeded = 0;

        aq_launcherServerDisconnect(lh);

        if (0 != lh->m_path) CFRelease(lh->m_path);
        aq_launcherDeleteAllItems(lh);

        free(lh);
    }
}


// macOS 11 and 12 use the older public API.  Keep the deprecated call in this one fallback.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static Boolean setLegacyLoginItem(Boolean enabled)
{
    return SMLoginItemSetEnabled(kAQLauncherBundleID, enabled);
}
#pragma clang diagnostic pop

AQLauncherStatus aq_LauncherGetStatus(AQLauncherRef lh)
{
    if (!lh || !lh->m_path) return AQLauncherStatusUnavailable;
    if (@available(macOS 13.0, *))
    {
        SMAppService* service = [SMAppService loginItemServiceWithIdentifier:(NSString*)kAQLauncherBundleID];
        switch (service.status)
        {
            case SMAppServiceStatusNotRegistered: return AQLauncherStatusDisabled;
            case SMAppServiceStatusEnabled: return AQLauncherStatusEnabled;
            case SMAppServiceStatusRequiresApproval: return AQLauncherStatusRequiresApproval;
            case SMAppServiceStatusNotFound: return AQLauncherStatusUnavailable;
            default: return AQLauncherStatusUnknown;
        }
    }
    return aq_launcherServerConnect(lh) ? AQLauncherStatusEnabled : AQLauncherStatusUnknown;
}

static void copyLauncherError(CFStringRef* message, NSString* description)
{
    if (message) *message = CFRetain((CFStringRef)description);
}

int aq_LauncherInstall(AQLauncherRef lh, CFStringRef* errorMessage)
{
    if (errorMessage) *errorMessage = NULL;
    if (!lh || !lh->m_path)
    {
        copyLauncherError(errorMessage, @"The bundled launcher is missing.");
        return 0;
    }
    aq_LauncherFlushLaunchItems(lh);
    if (@available(macOS 13.0, *))
    {
        SMAppService* service = [SMAppService loginItemServiceWithIdentifier:(NSString*)kAQLauncherBundleID];
        if (service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval) return 1;
        NSError* error = nil;
        if ([service registerAndReturnError:&error]) return 1;
        copyLauncherError(errorMessage, [error localizedDescription] ?: @"macOS could not register the launcher.");
        return 0;
    }
    if (setLegacyLoginItem(true)) return 1;
    copyLauncherError(errorMessage, @"macOS could not enable the launcher at login.");
    return 0;
}

int aq_LauncherUninstall(AQLauncherRef lh, CFStringRef* errorMessage)
{
    if (errorMessage) *errorMessage = NULL;
    if (@available(macOS 13.0, *))
    {
        SMAppService* service = [SMAppService loginItemServiceWithIdentifier:(NSString*)kAQLauncherBundleID];
        if (service.status != SMAppServiceStatusNotRegistered)
        {
            NSError* error = nil;
            if (![service unregisterAndReturnError:&error])
            {
                copyLauncherError(errorMessage, [error localizedDescription] ?: @"macOS could not unregister the launcher.");
                return 0;
            }
        }
    }
    else if (!setLegacyLoginItem(false))
    {
        copyLauncherError(errorMessage, @"macOS could not disable the launcher at login.");
        return 0;
    }
    aq_launcherServerQuit(lh);
    aq_launcherServerDisconnect(lh);
    return 1;
}


AQLaunchItemRef aq_LauncherGetFirstLaunchItem(AQLauncherRef lh)
{
    if (lh->m_items)
    {
        lh->m_nextToEnumerate = lh->m_items->m_next;
        return lh->m_items;
    }
    else
    {
        lh->m_nextToEnumerate = 0;
        return 0;
    }
}


AQLaunchItemRef aq_LauncherGetNextLaunchItem(AQLauncherRef lh)
{
    if (lh->m_nextToEnumerate)
    {
        const struct AQLaunchItem* result = lh->m_nextToEnumerate;
        lh->m_nextToEnumerate = result->m_next;
        return result;
    }
    else
    {
        return 0;
    }
}


void aq_LauncherClearLaunchItems(AQLauncherRef lh)
{
    lh->m_flushNeeded = aq_launcherDeleteAllItems(lh) || lh->m_flushNeeded;
}


void aq_LauncherDeleteLaunchItem(AQLauncherRef lh, AQLaunchItemRef item)
{
    lh->m_flushNeeded = aq_launcherDeleteItem(lh, item) || lh->m_flushNeeded;
}


void aq_LauncherAddLaunchItem(AQLauncherRef lh, CFStringRef app, SInt32 vendorID, SInt32 productID)
{
    lh->m_flushNeeded = aq_launcherAddItem(lh, app, vendorID, productID) || lh->m_flushNeeded;
}


void aq_LauncherFlushLaunchItems(AQLauncherRef lh)
{
    aq_launcherSavePreferences(lh);         // write the updates to disk
    aq_launcherServerLoadPreferences(lh);   // if the launcher is running, tell it to reload its preferences
    lh->m_flushNeeded = 0;
}


void aq_LauncherStart(AQLauncherRef lh)
{
    aq_launcherServerStart(lh);
}


void aq_LauncherStop(AQLauncherRef lh)
{
    aq_launcherServerStop(lh);
}


void aq_LauncherPause(AQLauncherRef lh, float seconds)
{
    aq_launcherServerPause(lh, seconds);
}
