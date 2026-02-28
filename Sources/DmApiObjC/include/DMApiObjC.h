#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^DMApiLicenseCallback)(void);

@interface DMApiObjC : NSObject

- (nullable instancetype)initWithLibraryPath:(nullable NSString *)libraryPath
                                       error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)shouldSkipCheckWithAppId:(nullable NSString *)appId
                       publicKey:(nullable NSString *)publicKey
                           error:(NSError * _Nullable * _Nullable)error;

- (nullable NSString *)getLastError;
- (nullable NSString *)getActivationErrorName:(nullable NSNumber *)code;

- (BOOL)setProductData:(NSString *)productData;
- (BOOL)setProductId:(NSString *)productId;
- (BOOL)setDataDirectory:(NSString *)directoryPath;
- (BOOL)setDebugMode:(BOOL)enable;
- (BOOL)setCustomDeviceFingerprint:(NSString *)fingerprint;

- (BOOL)setLicenseKey:(NSString *)licenseKey;
- (BOOL)setLicenseCallback:(DMApiLicenseCallback)callback;
- (BOOL)activateLicense;
- (nullable NSNumber *)getLastActivationError;

- (BOOL)isLicenseGenuine;
- (BOOL)isLicenseValid;
- (nullable NSNumber *)getServerSyncGracePeriodExpiryDate;
- (nullable NSDictionary<NSString *, NSString *> *)getActivationModeWithBufferSize:(uint32_t)bufferSize;

- (nullable NSString *)getLicenseKeyWithBufferSize:(uint32_t)bufferSize;
- (nullable NSNumber *)getLicenseExpiryDate;
- (nullable NSNumber *)getLicenseCreationDate;
- (nullable NSNumber *)getLicenseActivationDate;
- (nullable NSNumber *)getActivationCreationDate;
- (nullable NSNumber *)getActivationLastSyncedDate;
- (nullable NSString *)getActivationIdWithBufferSize:(uint32_t)bufferSize;

- (BOOL)reset;

- (nullable NSDictionary<NSString *, id> *)checkForUpdates:(nullable NSDictionary<NSString *, id> *)options;
- (nullable NSDictionary<NSString *, id> *)downloadUpdate:(nullable NSDictionary<NSString *, id> *)options;
- (nullable NSDictionary<NSString *, id> *)cancelUpdateDownload:(nullable NSDictionary<NSString *, id> *)options;
- (nullable NSDictionary<NSString *, id> *)getUpdateState;
- (nullable NSDictionary<NSString *, id> *)getPostUpdateInfo;
- (nullable NSDictionary<NSString *, id> *)ackPostUpdateInfo:(nullable NSDictionary<NSString *, id> *)options;
- (nullable NSDictionary<NSString *, id> *)waitForUpdateStateChange:(uint64_t)lastSequence
                                                           timeoutMs:(uint32_t)timeoutMs;
- (int32_t)quitAndInstall:(nullable NSDictionary<NSString *, id> *)options;

- (NSString *)getLibraryVersion;
- (nullable NSString *)jsonToCanonical:(NSString *)jsonStr;

@end

NS_ASSUME_NONNULL_END
