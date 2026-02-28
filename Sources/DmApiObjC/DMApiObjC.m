#import "DMApiObjC.h"

#import <dlfcn.h>
#import <stdlib.h>

static NSString *const DMApiObjCErrorDomain = @"com.distromate.dm-api-swiftobjc";
static NSString *const DMDevLicenseErrorText =
    @"Development license is missing or corrupted. Run `distromate sdk renew` to regenerate the dev certificate.";

static uint32_t const DMDefaultBufferSize = 256;
static uint32_t const DMDefaultModeBufferSize = 64;

typedef NS_ENUM(NSInteger, DMApiObjCErrorCode) {
  DMApiObjCErrorLoadLibrary = 1001,
  DMApiObjCErrorLoadSymbol = 1002,
  DMApiObjCErrorMissingAppIdentity = 1003,
  DMApiObjCErrorDevLicenseInvalid = 1004,
};

typedef int32_t (*DMStatusNoArgFn)(void);
typedef int32_t (*DMStatusStrArgFn)(const char *);
typedef int32_t (*DMStatusU32ArgFn)(uint32_t);
typedef int32_t (*DMSetLicenseCallbackFn)(void (*callback)(void));
typedef int32_t (*DMU32OutFn)(uint32_t *);
typedef int32_t (*DMStringOutFn)(char *, uint32_t);
typedef int32_t (*DMActivationModeFn)(char *, uint32_t, char *, uint32_t);
typedef char *(*DMOwnedStringNoArgFn)(void);
typedef char *(*DMOwnedStringStrArgFn)(const char *);
typedef char *(*DMOwnedStringWaitFn)(uint64_t, uint32_t);
typedef const char *(*DMStaticStringNoArgFn)(void);
typedef int32_t (*DMQuitAndInstallFn)(const char *);
typedef void (*DMFreeStringFn)(void *);

typedef struct {
  DMFreeStringFn freeString;
  DMOwnedStringNoArgFn getLastError;

  DMOwnedStringStrArgFn checkForUpdates;
  DMOwnedStringStrArgFn downloadUpdate;
  DMOwnedStringStrArgFn cancelUpdateDownload;
  DMOwnedStringNoArgFn getUpdateState;
  DMOwnedStringNoArgFn getPostUpdateInfo;
  DMOwnedStringStrArgFn ackPostUpdateInfo;
  DMOwnedStringWaitFn waitForUpdateStateChange;
  DMQuitAndInstallFn quitAndInstall;
  DMOwnedStringStrArgFn jsonToCanonical;

  DMStatusStrArgFn setProductData;
  DMStatusStrArgFn setProductId;
  DMStatusStrArgFn setDataDirectory;
  DMStatusU32ArgFn setDebugMode;
  DMStatusStrArgFn setCustomDeviceFingerprint;

  DMStatusStrArgFn setLicenseKey;
  DMSetLicenseCallbackFn setLicenseCallback;
  DMStatusNoArgFn activateLicense;
  DMU32OutFn getLastActivationError;

  DMStatusNoArgFn isLicenseGenuine;
  DMStatusNoArgFn isLicenseValid;
  DMU32OutFn getServerSyncGracePeriodExpiryDate;
  DMActivationModeFn getActivationMode;

  DMStringOutFn getLicenseKey;
  DMU32OutFn getLicenseExpiryDate;
  DMU32OutFn getLicenseCreationDate;
  DMU32OutFn getLicenseActivationDate;
  DMU32OutFn getActivationCreationDate;
  DMU32OutFn getActivationLastSyncedDate;
  DMStringOutFn getActivationId;

  DMStaticStringNoArgFn getLibraryVersion;
  DMStatusNoArgFn reset;
} DMApiSymbols;

static DMApiLicenseCallback g_licenseCallback = nil;

static void DMApiLicenseCallbackThunk(void) {
  DMApiLicenseCallback callback = g_licenseCallback;
  if (callback != nil) {
    callback();
  }
}

static NSError *DMMakeError(DMApiObjCErrorCode code, NSString *message) {
  return [NSError errorWithDomain:DMApiObjCErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSString *DMTrimmed(NSString * _Nullable value) {
  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    return nil;
  }
  return trimmed;
}

static NSString *DMEnvValue(NSString *key) {
  const char *value = getenv(key.UTF8String);
  if (value == NULL) {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static NSArray<NSString *> *DMRelativeCandidates(NSString *pathValue) {
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];

  NSString *executablePath = NSBundle.mainBundle.executablePath;
  if (executablePath.length > 0) {
    NSString *executableDir = executablePath.stringByDeletingLastPathComponent;
    [candidates addObject:[executableDir stringByAppendingPathComponent:pathValue]];
    NSString *parent = executableDir.stringByDeletingLastPathComponent;
    if (parent.length > 0) {
      [candidates addObject:[parent stringByAppendingPathComponent:pathValue]];
    }
  }

  NSString *cwd = NSFileManager.defaultManager.currentDirectoryPath;
  if (cwd.length > 0) {
    [candidates addObject:[cwd stringByAppendingPathComponent:pathValue]];
  }

  [candidates addObject:pathValue];
  return candidates;
}

static NSArray<NSString *> *DMDefaultLibraryNames(void) {
  return @[ @"dm_api.dylib", @"libdm_api.dylib", @"dm_api.dll" ];
}

static NSString *DMResolveLibraryPath(NSString * _Nullable explicitPath) {
  NSString *configured = DMTrimmed(explicitPath);
  if (configured == nil) {
    configured = DMTrimmed(DMEnvValue(@"DM_API_PATH"));
  }

  if (configured != nil) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }

    for (NSString *candidate in DMRelativeCandidates(configured)) {
      if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
        return candidate;
      }
    }

    return configured;
  }

  for (NSString *defaultName in DMDefaultLibraryNames()) {
    for (NSString *candidate in DMRelativeCandidates(defaultName)) {
      if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
        return candidate;
      }
    }
  }

  return [DMDefaultLibraryNames() firstObject];
}

static void *DMLoadSymbol(void *handle, const char *symbol, NSError **error) {
  dlerror();
  void *ptr = dlsym(handle, symbol);
  const char *loadErr = dlerror();
  if (loadErr != NULL || ptr == NULL) {
    NSString *reason = loadErr != NULL ? [NSString stringWithUTF8String:loadErr] : @"unknown";
    if (error != NULL) {
      *error = DMMakeError(
          DMApiObjCErrorLoadSymbol,
          [NSString stringWithFormat:@"Failed to load symbol %s: %@", symbol, reason]);
    }
    return NULL;
  }
  return ptr;
}

static BOOL DMLoadSymbols(void *handle, DMApiSymbols *symbols, NSError **error) {
#define DM_LOAD(field, type, symbol)                         \
  do {                                                       \
    void *ptr = DMLoadSymbol(handle, symbol, error);         \
    if (ptr == NULL) {                                       \
      return NO;                                             \
    }                                                        \
    symbols->field = (type)ptr;                              \
  } while (0)

  DM_LOAD(freeString, DMFreeStringFn, "DM_FreeString");
  DM_LOAD(getLastError, DMOwnedStringNoArgFn, "DM_GetLastError");

  DM_LOAD(checkForUpdates, DMOwnedStringStrArgFn, "DM_CheckForUpdates");
  DM_LOAD(downloadUpdate, DMOwnedStringStrArgFn, "DM_DownloadUpdate");
  DM_LOAD(cancelUpdateDownload, DMOwnedStringStrArgFn, "DM_CancelUpdateDownload");
  DM_LOAD(getUpdateState, DMOwnedStringNoArgFn, "DM_GetUpdateState");
  DM_LOAD(getPostUpdateInfo, DMOwnedStringNoArgFn, "DM_GetPostUpdateInfo");
  DM_LOAD(ackPostUpdateInfo, DMOwnedStringStrArgFn, "DM_AckPostUpdateInfo");
  DM_LOAD(waitForUpdateStateChange, DMOwnedStringWaitFn, "DM_WaitForUpdateStateChange");
  DM_LOAD(quitAndInstall, DMQuitAndInstallFn, "DM_QuitAndInstall");
  DM_LOAD(jsonToCanonical, DMOwnedStringStrArgFn, "DM_JsonToCanonical");

  DM_LOAD(setProductData, DMStatusStrArgFn, "SetProductData");
  DM_LOAD(setProductId, DMStatusStrArgFn, "SetProductId");
  DM_LOAD(setDataDirectory, DMStatusStrArgFn, "SetDataDirectory");
  DM_LOAD(setDebugMode, DMStatusU32ArgFn, "SetDebugMode");
  DM_LOAD(setCustomDeviceFingerprint, DMStatusStrArgFn, "SetCustomDeviceFingerprint");

  DM_LOAD(setLicenseKey, DMStatusStrArgFn, "SetLicenseKey");
  DM_LOAD(setLicenseCallback, DMSetLicenseCallbackFn, "SetLicenseCallback");
  DM_LOAD(activateLicense, DMStatusNoArgFn, "ActivateLicense");
  DM_LOAD(getLastActivationError, DMU32OutFn, "GetLastActivationError");

  DM_LOAD(isLicenseGenuine, DMStatusNoArgFn, "IsLicenseGenuine");
  DM_LOAD(isLicenseValid, DMStatusNoArgFn, "IsLicenseValid");
  DM_LOAD(getServerSyncGracePeriodExpiryDate, DMU32OutFn, "GetServerSyncGracePeriodExpiryDate");
  DM_LOAD(getActivationMode, DMActivationModeFn, "GetActivationMode");

  DM_LOAD(getLicenseKey, DMStringOutFn, "GetLicenseKey");
  DM_LOAD(getLicenseExpiryDate, DMU32OutFn, "GetLicenseExpiryDate");
  DM_LOAD(getLicenseCreationDate, DMU32OutFn, "GetLicenseCreationDate");
  DM_LOAD(getLicenseActivationDate, DMU32OutFn, "GetLicenseActivationDate");
  DM_LOAD(getActivationCreationDate, DMU32OutFn, "GetActivationCreationDate");
  DM_LOAD(getActivationLastSyncedDate, DMU32OutFn, "GetActivationLastSyncedDate");
  DM_LOAD(getActivationId, DMStringOutFn, "GetActivationId");

  DM_LOAD(getLibraryVersion, DMStaticStringNoArgFn, "GetLibraryVersion");
  DM_LOAD(reset, DMStatusNoArgFn, "Reset");

#undef DM_LOAD
  return YES;
}

@interface DMApiObjC () {
  void *_libraryHandle;
  DMApiSymbols _symbols;
}

@property(nonatomic, copy, nullable) DMApiLicenseCallback callbackRef;

@end

@implementation DMApiObjC

- (nullable instancetype)initWithLibraryPath:(nullable NSString *)libraryPath
                                       error:(NSError * _Nullable * _Nullable)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }

  NSString *resolvedPath = DMResolveLibraryPath(libraryPath);
  void *handle = dlopen(resolvedPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
  if (handle == NULL) {
    if (error != NULL) {
      const char *raw = dlerror();
      NSString *reason = raw != NULL ? [NSString stringWithUTF8String:raw] : @"unknown";
      *error = DMMakeError(
          DMApiObjCErrorLoadLibrary,
          [NSString stringWithFormat:@"Failed to load library %@: %@", resolvedPath, reason]);
    }
    return nil;
  }

  DMApiSymbols symbols = {0};
  if (!DMLoadSymbols(handle, &symbols, error)) {
    dlclose(handle);
    return nil;
  }

  _libraryHandle = handle;
  _symbols = symbols;
  return self;
}

- (void)dealloc {
  if (_libraryHandle != NULL) {
    dlclose(_libraryHandle);
    _libraryHandle = NULL;
  }
}

+ (BOOL)shouldSkipCheckWithAppId:(nullable NSString *)appId
                       publicKey:(nullable NSString *)publicKey
                           error:(NSError * _Nullable * _Nullable)error {
  NSString *endpoint = DMTrimmed(DMEnvValue(@"DM_LAUNCHER_ENDPOINT"));
  NSString *token = DMTrimmed(DMEnvValue(@"DM_LAUNCHER_TOKEN"));
  if (endpoint.length > 0 && token.length > 0) {
    return NO;
  }

  NSString *resolvedAppId = DMTrimmed(appId);
  if (resolvedAppId == nil) {
    resolvedAppId = DMTrimmed(DMEnvValue(@"DM_APP_ID"));
  }

  NSString *resolvedPublicKey = DMTrimmed(publicKey);
  if (resolvedPublicKey == nil) {
    resolvedPublicKey = DMTrimmed(DMEnvValue(@"DM_PUBLIC_KEY"));
  }

  if (resolvedAppId.length == 0 || resolvedPublicKey.length == 0) {
    if (error != NULL) {
      *error = DMMakeError(
          DMApiObjCErrorMissingAppIdentity,
          @"App identity is required for dev-license checks. Provide appId/publicKey or set DM_APP_ID and DM_PUBLIC_KEY.");
    }
    return NO;
  }

  NSString *home = NSHomeDirectory();
  if (home.length == 0) {
    if (error != NULL) {
      *error = DMMakeError(DMApiObjCErrorDevLicenseInvalid, DMDevLicenseErrorText);
    }
    return NO;
  }

  NSString *pubkeyPath = [home
      stringByAppendingPathComponent:[NSString stringWithFormat:@".distromate-cli/dev_licenses/%@/pubkey", resolvedAppId]];

  NSError *readError = nil;
  NSString *devPublicKey =
      [NSString stringWithContentsOfFile:pubkeyPath encoding:NSUTF8StringEncoding error:&readError];
  devPublicKey = DMTrimmed(devPublicKey);

  if (devPublicKey.length == 0 || ![devPublicKey isEqualToString:resolvedPublicKey]) {
    if (error != NULL) {
      *error = DMMakeError(DMApiObjCErrorDevLicenseInvalid, DMDevLicenseErrorText);
    }
    return NO;
  }

  return YES;
}

- (nullable NSString *)getLastError {
  return [self ownedCStringToString:_symbols.getLastError()];
}

- (nullable NSString *)getActivationErrorName:(nullable NSNumber *)code {
  if (code == nil) {
    return nil;
  }

  static NSDictionary<NSNumber *, NSString *> *names;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    names = @{
      @0 : @"DM_ERR_OK",
      @1 : @"DM_ERR_FAIL",
      @2 : @"DM_ERR_INVALID_PARAMETER",
      @3 : @"DM_ERR_APPID_NOT_SET",
      @4 : @"DM_ERR_LICENSE_KEY_NOT_SET",
      @5 : @"DM_ERR_NOT_ACTIVATED",
      @6 : @"DM_ERR_LICENSE_EXPIRED",
      @7 : @"DM_ERR_NETWORK",
      @8 : @"DM_ERR_FILE_IO",
      @9 : @"DM_ERR_SIGNATURE",
      @10 : @"DM_ERR_BUFFER_TOO_SMALL",
    };
  });

  NSString *name = names[code];
  if (name != nil) {
    return name;
  }

  return [NSString stringWithFormat:@"UNKNOWN(%u)", code.unsignedIntValue];
}

- (BOOL)setProductData:(NSString *)productData {
  return _symbols.setProductData(productData.UTF8String) == 0;
}

- (BOOL)setProductId:(NSString *)productId {
  return _symbols.setProductId(productId.UTF8String) == 0;
}

- (BOOL)setDataDirectory:(NSString *)directoryPath {
  return _symbols.setDataDirectory(directoryPath.UTF8String) == 0;
}

- (BOOL)setDebugMode:(BOOL)enable {
  return _symbols.setDebugMode(enable ? 1u : 0u) == 0;
}

- (BOOL)setCustomDeviceFingerprint:(NSString *)fingerprint {
  return _symbols.setCustomDeviceFingerprint(fingerprint.UTF8String) == 0;
}

- (BOOL)setLicenseKey:(NSString *)licenseKey {
  return _symbols.setLicenseKey(licenseKey.UTF8String) == 0;
}

- (BOOL)setLicenseCallback:(DMApiLicenseCallback)callback {
  DMApiLicenseCallback copied = [callback copy];
  if (_symbols.setLicenseCallback(DMApiLicenseCallbackThunk) != 0) {
    return NO;
  }

  self.callbackRef = copied;
  g_licenseCallback = copied;
  return YES;
}

- (BOOL)activateLicense {
  return _symbols.activateLicense() == 0;
}

- (nullable NSNumber *)getLastActivationError {
  return [self callU32Out:_symbols.getLastActivationError];
}

- (BOOL)isLicenseGenuine {
  return _symbols.isLicenseGenuine() == 0;
}

- (BOOL)isLicenseValid {
  return _symbols.isLicenseValid() == 0;
}

- (nullable NSNumber *)getServerSyncGracePeriodExpiryDate {
  return [self callU32Out:_symbols.getServerSyncGracePeriodExpiryDate];
}

- (nullable NSDictionary<NSString *, NSString *> *)getActivationModeWithBufferSize:(uint32_t)bufferSize {
  uint32_t size = bufferSize == 0 ? DMDefaultModeBufferSize : bufferSize;
  char *initial = calloc(size, sizeof(char));
  char *current = calloc(size, sizeof(char));
  if (initial == NULL || current == NULL) {
    free(initial);
    free(current);
    return nil;
  }

  int32_t status = _symbols.getActivationMode(initial, size, current, size);
  NSDictionary<NSString *, NSString *> *result = nil;
  if (status == 0) {
    NSString *initialMode = [NSString stringWithUTF8String:initial] ?: @"";
    NSString *currentMode = [NSString stringWithUTF8String:current] ?: @"";
    result = @{ @"initial_mode" : initialMode, @"current_mode" : currentMode };
  }

  free(initial);
  free(current);
  return result;
}

- (nullable NSString *)getLicenseKeyWithBufferSize:(uint32_t)bufferSize {
  return [self callStringOut:_symbols.getLicenseKey bufferSize:bufferSize defaultSize:DMDefaultBufferSize];
}

- (nullable NSNumber *)getLicenseExpiryDate {
  return [self callU32Out:_symbols.getLicenseExpiryDate];
}

- (nullable NSNumber *)getLicenseCreationDate {
  return [self callU32Out:_symbols.getLicenseCreationDate];
}

- (nullable NSNumber *)getLicenseActivationDate {
  return [self callU32Out:_symbols.getLicenseActivationDate];
}

- (nullable NSNumber *)getActivationCreationDate {
  return [self callU32Out:_symbols.getActivationCreationDate];
}

- (nullable NSNumber *)getActivationLastSyncedDate {
  return [self callU32Out:_symbols.getActivationLastSyncedDate];
}

- (nullable NSString *)getActivationIdWithBufferSize:(uint32_t)bufferSize {
  return [self callStringOut:_symbols.getActivationId bufferSize:bufferSize defaultSize:DMDefaultBufferSize];
}

- (BOOL)reset {
  return _symbols.reset() == 0;
}

- (nullable NSDictionary<NSString *, id> *)checkForUpdates:(nullable NSDictionary<NSString *, id> *)options {
  return [self callEnvelopeWithOptions:_symbols.checkForUpdates options:options];
}

- (nullable NSDictionary<NSString *, id> *)downloadUpdate:(nullable NSDictionary<NSString *, id> *)options {
  return [self callEnvelopeWithOptions:_symbols.downloadUpdate options:options];
}

- (nullable NSDictionary<NSString *, id> *)cancelUpdateDownload:(nullable NSDictionary<NSString *, id> *)options {
  return [self callEnvelopeWithOptions:_symbols.cancelUpdateDownload options:options];
}

- (nullable NSDictionary<NSString *, id> *)getUpdateState {
  return [self parseEnvelope:[self ownedCStringToString:_symbols.getUpdateState()]];
}

- (nullable NSDictionary<NSString *, id> *)getPostUpdateInfo {
  return [self parseEnvelope:[self ownedCStringToString:_symbols.getPostUpdateInfo()]];
}

- (nullable NSDictionary<NSString *, id> *)ackPostUpdateInfo:(nullable NSDictionary<NSString *, id> *)options {
  return [self callEnvelopeWithOptions:_symbols.ackPostUpdateInfo options:options];
}

- (nullable NSDictionary<NSString *, id> *)waitForUpdateStateChange:(uint64_t)lastSequence
                                                           timeoutMs:(uint32_t)timeoutMs {
  NSString *raw = [self ownedCStringToString:_symbols.waitForUpdateStateChange(lastSequence, timeoutMs)];
  return [self parseEnvelope:raw];
}

- (int32_t)quitAndInstall:(nullable NSDictionary<NSString *, id> *)options {
  NSString *encoded = [self encodeOptions:options];
  return _symbols.quitAndInstall(encoded != nil ? encoded.UTF8String : NULL);
}

- (NSString *)getLibraryVersion {
  return [self staticCStringToString:_symbols.getLibraryVersion()];
}

- (nullable NSString *)jsonToCanonical:(NSString *)jsonStr {
  return [self ownedCStringToString:_symbols.jsonToCanonical(jsonStr.UTF8String)];
}

- (nullable NSNumber *)callU32Out:(DMU32OutFn)call {
  uint32_t value = 0;
  if (call(&value) != 0) {
    return nil;
  }
  return @(value);
}

- (nullable NSString *)callStringOut:(DMStringOutFn)call
                           bufferSize:(uint32_t)bufferSize
                          defaultSize:(uint32_t)defaultSize {
  uint32_t size = bufferSize == 0 ? defaultSize : bufferSize;
  char *buffer = calloc(size, sizeof(char));
  if (buffer == NULL) {
    return nil;
  }

  NSString *result = nil;
  if (call(buffer, size) == 0) {
    result = [NSString stringWithUTF8String:buffer];
  }

  free(buffer);
  return result;
}

- (nullable NSDictionary<NSString *, id> *)callEnvelopeWithOptions:(DMOwnedStringStrArgFn)call
                                                            options:(nullable NSDictionary<NSString *, id> *)options {
  NSString *encoded = [self encodeOptions:options];
  NSString *raw = [self ownedCStringToString:call(encoded != nil ? encoded.UTF8String : NULL)];
  return [self parseEnvelope:raw];
}

- (nullable NSDictionary<NSString *, id> *)parseEnvelope:(nullable NSString *)raw {
  if (raw.length == 0) {
    return nil;
  }

  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return nil;
  }

  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  return parsed;
}

- (nullable NSString *)encodeOptions:(nullable NSDictionary<NSString *, id> *)options {
  if (options == nil) {
    return nil;
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:nil];
  if (data == nil) {
    return nil;
  }

  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)staticCStringToString:(const char *)ptr {
  if (ptr == NULL) {
    return @"";
  }
  return [NSString stringWithUTF8String:ptr] ?: @"";
}

- (nullable NSString *)ownedCStringToString:(char *)ptr {
  if (ptr == NULL) {
    return nil;
  }

  NSString *value = [NSString stringWithUTF8String:ptr];
  _symbols.freeString(ptr);
  return value;
}

@end
