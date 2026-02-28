# dm-api-swift

Swift / Objective-C SDK for DistroMate `dm_api` native library.

This repository provides two library products:

- `DmApiSwift`: high-level Swift API.
- `DmApiObjC`: Objective-C API (also used by the Swift wrapper).

## Install (Swift Package Manager)

```swift
dependencies: [
  .package(url: "https://github.com/yangsengui/dm-api-swift.git", from: "1.2.0")
]
```

## Quick Start (Swift)

```swift
import DmApiSwift

let api = try DmApi()

_ = api.setProductData("<product-data>")
_ = api.setProductId("your-product-id")
_ = api.setLicenseKey("XXXX-XXXX-XXXX")

if !api.activateLicense() {
    throw NSError(domain: "DmApi", code: 1, userInfo: [
        NSLocalizedDescriptionKey: api.getLastError() ?? "activation failed",
    ])
}

if !api.isLicenseGenuine() {
    let code = api.getLastActivationError()
    let name = api.getActivationErrorName(code)
    throw NSError(domain: "DmApi", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "license check failed: \(name ?? "UNKNOWN"), err=\(api.getLastError() ?? "")",
    ])
}
```

## Quick Start (Objective-C)

```objective-c
#import <DmApiObjC/DMApiObjC.h>

NSError *error = nil;
DMApiObjC *api = [[DMApiObjC alloc] initWithLibraryPath:nil error:&error];
if (api == nil) {
    NSLog(@"init failed: %@", error.localizedDescription);
    return;
}

[api setProductData:@"<product-data>"];
[api setProductId:@"your-product-id"];
[api setLicenseKey:@"XXXX-XXXX-XXXX"];

if (![api activateLicense]) {
    NSLog(@"activation failed: %@", [api getLastError]);
}
```

## API Groups

- License setup: `setProductData`, `setProductId`, `setDataDirectory`, `setDebugMode`, `setCustomDeviceFingerprint`
- License activation: `setLicenseKey`, `setLicenseCallback`, `activateLicense`, `getLastActivationError`
- License state: `isLicenseGenuine`, `isLicenseValid`, `getServerSyncGracePeriodExpiryDate`, `getActivationMode`
- License details: `getLicenseKey`, `getLicenseExpiryDate`, `getLicenseCreationDate`, `getLicenseActivationDate`, `getActivationCreationDate`, `getActivationLastSyncedDate`, `getActivationId`
- Update: `checkForUpdates`, `downloadUpdate`, `cancelUpdateDownload`, `getUpdateState`, `getPostUpdateInfo`, `ackPostUpdateInfo`, `waitForUpdateStateChange`, `quitAndInstall`
- General: `getLibraryVersion`, `jsonToCanonical`, `getLastError`, `reset`

## Update API Notes

- Update APIs return parsed JSON envelope (`[String: Any]` / `NSDictionary`) when transport succeeds.
- If native API returns `NULL`, SDK returns `nil`; check `getLastError()`.
- `quitAndInstall()` returns native status directly:
  - `1`: accepted, process should exit soon
  - `-1`: business-level rejection (check `getLastError()`)
  - `-2`: transport or parse error

## Environment Variables

- `DM_API_PATH`: optional path to native library
- `DM_APP_ID`, `DM_PUBLIC_KEY`: optional defaults for app identity
- `DM_LAUNCHER_ENDPOINT`, `DM_LAUNCHER_TOKEN`: launcher IPC variables used by update APIs

## Build

```bash
swift test
```

## Release

- CI validates package build via `swift test`.
- Tag `v*` triggers GitHub Release packaging.
