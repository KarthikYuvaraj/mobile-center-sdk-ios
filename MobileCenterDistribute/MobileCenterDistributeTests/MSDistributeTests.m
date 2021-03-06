
#import <Foundation/Foundation.h>
#import <OCHamcrestIOS/OCHamcrestIOS.h>
#import <OCMock/OCMock.h>
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MSAlertController.h"
#import "MSBasicMachOParser.h"
#import "MSDistribute.h"
#import "MSDistributeInternal.h"
#import "MSDistributePrivate.h"
#import "MSDistributeTestUtil.h"
#import "MSDistributeUtil.h"
#import "MSKeychainUtil.h"
#import "MSLogManager.h"
#import "MSMobileCenter.h"
#import "MSServiceAbstract.h"
#import "MSServiceAbstractProtected.h"
#import "MSServiceInternal.h"
#import "MSUserDefaults.h"
#import "MSUtility+Environment.h"

static NSString *const kMSTestAppSecret = @"IAMSECRET";

// Mocked SFSafariViewController for url validation.
@interface SFSafariViewController : UIViewController

@property(class, nonatomic) NSURL *url;

- (instancetype)initWithURL:(NSURL *)url;

@end

static NSURL *sfURL;

@implementation SFSafariViewController

- (instancetype)initWithURL:(NSURL *)url {
  if ((self = [super init])) {
    [[self class] setUrl:url];
  }
  return self;
}
+ (NSURL *)url {
  return sfURL;
}

+ (void)setUrl:(NSURL *)url {
  sfURL = url;
}
@end

static NSURL *sfURL;

@interface MSDistributeTests : XCTestCase

@property(nonatomic) MSDistribute *sut;
@property(nonatomic) id parserMock;

@end

@implementation MSDistributeTests

- (void)setUp {
  [super setUp];
  [MS_USER_DEFAULTS removeObjectForKey:kMSUpdateTokenRequestIdKey];
  [MS_USER_DEFAULTS removeObjectForKey:kMSIgnoredReleaseIdKey];
  [MSKeychainUtil clear];
  self.sut = [MSDistribute new];

  // Make sure we disable the debug-mode checks so we can actually test the logic.
  [MSDistributeTestUtil mockUpdatesAllowedConditions];

  // MSBasicMachOParser may fail on test projects' main bundle. It's mocked to prevent it.
  id parserMock = OCMClassMock([MSBasicMachOParser class]);
  self.parserMock = parserMock;
  OCMStub([parserMock machOParserForMainBundle]).andReturn(self.parserMock);
  OCMStub([self.parserMock uuid])
      .andReturn([[NSUUID alloc] initWithUUIDString:@"CD55E7A9-7AD1-4CA6-B722-3D133F487DA9"]);
}

- (void)tearDown {
  [super tearDown];
  [MS_USER_DEFAULTS removeObjectForKey:kMSUpdateTokenRequestIdKey];
  [MS_USER_DEFAULTS removeObjectForKey:kMSIgnoredReleaseIdKey];
  [MSKeychainUtil clear];
  [self.parserMock stopMocking];
  [MSDistributeTestUtil unMockUpdatesAllowedConditions];
}

- (void)testUpdateURL {

  // If
  NSArray *bundleArray =
      @[ @{
        @"CFBundleURLSchemes" : @[ [NSString stringWithFormat:@"mobilecenter-%@", kMSTestAppSecret] ]
      } ];
  id bundleMock = OCMClassMock([NSBundle class]);
  OCMStub([bundleMock mainBundle]).andReturn(bundleMock);
  NSDictionary<NSString *, id> *plist = @{ @"CFBundleShortVersionString" : @"1.0", @"CFBundleVersion" : @"1" };
  OCMStub([bundleMock infoDictionary]).andReturn(plist);
  OCMStub([bundleMock objectForInfoDictionaryKey:@"CFBundleURLTypes"]).andReturn(bundleArray);
  OCMStub([bundleMock objectForInfoDictionaryKey:@"MSAppName"]).andReturn(@"Something");
  id distributeMock = OCMPartialMock(self.sut);

  // Disable for now to bypass initializing sender.
  [distributeMock setEnabled:NO];
  [distributeMock startWithLogManager:OCMProtocolMock(@protocol(MSLogManager)) appSecret:kMSTestAppSecret];

  // Enable again.
  [distributeMock setEnabled:YES];

  // When
  NSURL *url = [distributeMock buildTokenRequestURLWithAppSecret:kMSTestAppSecret];
  NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
  NSMutableDictionary<NSString *, NSString *> *queryStrings = [NSMutableDictionary<NSString *, NSString *> new];
  [components.queryItems
      enumerateObjectsUsingBlock:^(__kindof NSURLQueryItem *_Nonnull queryItem, NSUInteger idx, BOOL *_Nonnull stop) {
        if (queryItem.value) {
          [queryStrings setObject:(NSString * _Nonnull)queryItem.value forKey:queryItem.name];
        }
      }];

  // Then
  assertThat(url, notNilValue());
  assertThatLong(queryStrings.count, equalToLong(4));
  assertThatBool([components.path containsString:kMSTestAppSecret], isTrue());
  assertThat(queryStrings[kMSURLQueryPlatformKey], is(kMSURLQueryPlatformValue));
  assertThat(queryStrings[kMSURLQueryRedirectIdKey],
             is([NSString stringWithFormat:kMSDefaultCustomSchemeFormat, kMSTestAppSecret]));
  assertThat(queryStrings[kMSURLQueryRequestIdKey], notNilValue());
  assertThat(queryStrings[kMSURLQueryReleaseHashKey], notNilValue());
}

- (void)testMalformedUpdateURL {

  // If
  NSString *badAppSecret = @"weird\\app\\secret";
  id bundleMock = OCMClassMock([NSBundle class]);
  OCMStub([bundleMock mainBundle]).andReturn([NSBundle bundleForClass:[self class]]);

  // When
  NSURL *url = [self.sut buildTokenRequestURLWithAppSecret:badAppSecret];

  assertThat(url, nilValue());
}

- (void)testOpenURLInSafariApp {

  // If
  XCTestExpectation *openURLCalledExpectation = [self expectationWithDescription:@"openURL Called."];
  NSURL *url = [NSURL URLWithString:@"https://contoso.com"];
  id appMock = OCMClassMock([UIApplication class]);
  OCMStub([appMock sharedApplication]).andReturn(appMock);
  OCMStub([appMock canOpenURL:url]).andReturn(YES);
  OCMStub([appMock openURL:url]).andDo(nil);

  // When
  [self.sut openURLInSafariApp:url];
  dispatch_async(dispatch_get_main_queue(), ^{
    [openURLCalledExpectation fulfill];
  });

  // Then
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {
                                 OCMVerify([appMock openURL:url]);
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

- (void)testOpenURLInEmbeddedSafari {

  // If
  NSURL *url = [NSURL URLWithString:@"https://contoso.com"];

  // When
  @try {
    [self.sut openURLInEmbeddedSafari:url fromClass:[SFSafariViewController class]];
  } @catch (NSException *ex) {

    /**
     * TODO: This is not a UI test so we expect it to fail with NSInternalInconsistencyException exception.
     * Hopefully it doesn't prevent the URL to be set. Maybe introduce UI testing for this case in the future.
     */
  }

  // Then
  assertThat(SFSafariViewController.url, is(url));
}

- (void)testSetApiUrlWorks {

  // When
  NSString *testUrl = @"https://example.com";
  [MSDistribute setApiUrl:testUrl];
  MSDistribute *distribute = [MSDistribute sharedInstance];

  // Then
  XCTAssertTrue([[distribute apiUrl] isEqualToString:testUrl]);
}

- (void)testSetInstallUrlWorks {

  // If
  NSString *testUrl = @"https://example.com";
  NSArray *bundleArray =
      @[ @{
        @"CFBundleURLSchemes" : @[ [NSString stringWithFormat:@"mobilecenter-%@", kMSTestAppSecret] ]
      } ];
  id bundleMock = OCMClassMock([NSBundle class]);
  OCMStub([bundleMock mainBundle]).andReturn(bundleMock);
  NSDictionary<NSString *, id> *plist = @{ @"CFBundleShortVersionString" : @"1.0", @"CFBundleVersion" : @"1" };
  OCMStub([bundleMock infoDictionary]).andReturn(plist);
  OCMStub([bundleMock objectForInfoDictionaryKey:@"CFBundleURLTypes"]).andReturn(bundleArray);

  // When
  [MSDistribute setInstallUrl:testUrl];
  MSDistribute *distribute = [MSDistribute sharedInstance];
  NSURL *url = [distribute buildTokenRequestURLWithAppSecret:kMSTestAppSecret];

  // Then
  XCTAssertTrue([[distribute installUrl] isEqualToString:testUrl]);
  XCTAssertTrue([url.absoluteString hasPrefix:testUrl]);
}

- (void)testDefaultInstallUrlWorks {

  // If
  NSArray *bundleArray =
      @[ @{
        @"CFBundleURLSchemes" : @[ [NSString stringWithFormat:@"mobilecenter-%@", kMSTestAppSecret] ]
      } ];
  id bundleMock = OCMClassMock([NSBundle class]);
  OCMStub([bundleMock mainBundle]).andReturn(bundleMock);
  NSDictionary<NSString *, id> *plist = @{ @"CFBundleShortVersionString" : @"1.0", @"CFBundleVersion" : @"1" };
  OCMStub([bundleMock infoDictionary]).andReturn(plist);
  OCMStub([bundleMock objectForInfoDictionaryKey:@"CFBundleURLTypes"]).andReturn(bundleArray);

  // When
  NSString *instalURL = [self.sut installUrl];
  NSURL *tokenRequestURL = [self.sut buildTokenRequestURLWithAppSecret:kMSTestAppSecret];

  // Then
  XCTAssertNotNil(instalURL);
  XCTAssertTrue([tokenRequestURL.absoluteString hasPrefix:kMSDefaultInstallUrl]);
}

- (void)testDefaultApiUrlWorks {

  // Then
  XCTAssertNotNil([self.sut apiUrl]);
  XCTAssertTrue([[self.sut apiUrl] isEqualToString:kMSDefaultApiUrl]);
}

- (void)testHandleUpdate {

  // If
  MSReleaseDetails *details = [MSReleaseDetails new];
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock showConfirmationAlert:[OCMArg any]]).andDo(nil);

  // When
  [distributeMock handleUpdate:details];

  // Then
  OCMReject([distributeMock showConfirmationAlert:[OCMArg any]]);

  // If
  details.id = @1;
  details.downloadUrl = [NSURL URLWithString:@"https://contoso.com/valid/url"];

  // When
  [distributeMock handleUpdate:details];

  // Then
  OCMReject([distributeMock showConfirmationAlert:[OCMArg any]]);

  // If
  details.status = @"available";
  details.minOs = @"1000.0";

  // When
  [distributeMock handleUpdate:details];

  // Then
  OCMReject([distributeMock showConfirmationAlert:[OCMArg any]]);

  // If
  details.minOs = @"1.0";
  OCMStub([distributeMock isNewerVersion:[OCMArg any]]).andReturn(NO).andReturn(YES);

  // When
  [distributeMock handleUpdate:details];

  // Then
  OCMReject([distributeMock showConfirmationAlert:[OCMArg any]]);

  // When
  [distributeMock handleUpdate:details];

  // Then
  OCMVerify([distributeMock showConfirmationAlert:[OCMArg any]]);
}

- (void)testShowConfirmationAlert {

  // If
  id mobileCenterMock = OCMPartialMock(self.sut);
  id alertControllerMock = OCMClassMock([MSAlertController class]);
  MSReleaseDetails *details = [MSReleaseDetails new];
  OCMStub([alertControllerMock alertControllerWithTitle:[OCMArg any] message:[OCMArg any]])
      .andReturn(alertControllerMock);
  details.releaseNotes = @"Release Note";
  details.mandatoryUpdate = false;

  // When
  XCTestExpectation *expection = [self expectationWithDescription:@"Confirmation alert has been displayed"];
  [mobileCenterMock showConfirmationAlert:details];
  dispatch_async(dispatch_get_main_queue(), ^{
    [expection fulfill];
  });

  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {

                                 // Then
                                 OCMVerify([alertControllerMock alertControllerWithTitle:[OCMArg any]
                                                                                 message:details.releaseNotes]);
                                 OCMVerify(
                                     [alertControllerMock addDefaultActionWithTitle:[OCMArg any] handler:[OCMArg any]]);
                                 OCMVerify(
                                     [alertControllerMock addCancelActionWithTitle:[OCMArg any] handler:[OCMArg any]]);
                               }];
}

- (void)testShowConfirmationAlertForMandatoryUpdate {

  // If
  id mobileCenterMock = OCMPartialMock(self.sut);
  id alertControllerMock = OCMClassMock([MSAlertController class]);
  MSReleaseDetails *details = [MSReleaseDetails new];
  OCMStub([alertControllerMock alertControllerWithTitle:[OCMArg any] message:[OCMArg any]])
      .andReturn(alertControllerMock);
  details.releaseNotes = @"Release Note";
  details.mandatoryUpdate = true;

  // When
  XCTestExpectation *expection = [self expectationWithDescription:@"Confirmation alert has been displayed"];
  [mobileCenterMock showConfirmationAlert:details];
  dispatch_async(dispatch_get_main_queue(), ^{
    [expection fulfill];
  });

  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {

                                 // Then
                                 OCMVerify([alertControllerMock alertControllerWithTitle:[OCMArg any]
                                                                                 message:details.releaseNotes]);
                                 OCMReject(
                                     [alertControllerMock addDefaultActionWithTitle:[OCMArg any] handler:[OCMArg any]]);
                                 OCMVerify(
                                     [alertControllerMock addCancelActionWithTitle:[OCMArg any] handler:[OCMArg any]]);
                               }];
}

- (void)testOpenUrl {

  // If
  NSString *scheme = [NSString stringWithFormat:kMSDefaultCustomSchemeFormat, kMSTestAppSecret];
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock sharedInstance]).andReturn(distributeMock);
  OCMStub([distributeMock checkLatestRelease:[OCMArg any]]).andDo(nil);

  // Disable for now to bypass initializing sender.
  [distributeMock setEnabled:NO];
  [distributeMock startWithLogManager:OCMProtocolMock(@protocol(MSLogManager)) appSecret:kMSTestAppSecret];

  // Enable again.
  [distributeMock setEnabled:YES];
  NSURL *url = [NSURL URLWithString:@"invalid://?"];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?", scheme]];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?request_id=FIRST-REQUEST", scheme]];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?request_id=FIRST-REQUEST&update_token=token", scheme]];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  id userDefaultsMock = OCMClassMock([MSUserDefaults class]);
  OCMStub([userDefaultsMock shared]).andReturn(userDefaultsMock);
  OCMStub([userDefaultsMock objectForKey:kMSUpdateTokenRequestIdKey]).andReturn(@"FIRST-REQUEST");
  url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?request_id=FIRST-REQUEST&update_token=token",
                                                        [NSString stringWithFormat:kMSDefaultCustomSchemeFormat,
                                                                                   @"Invalid-app-secret"]]];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?request_id=FIRST-REQUEST&update_token=token", scheme]];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMVerify([distributeMock checkLatestRelease:@"token"]);

  // If
  [distributeMock setEnabled:NO];

  // When
  [MSDistribute openUrl:url];

  // Then
  OCMReject([distributeMock checkLatestRelease:[OCMArg any]]);
}

- (void)testApplyEnabledStateTrueForDebugConfig {
  [MS_USER_DEFAULTS removeObjectForKey:kMSUpdateTokenRequestIdKey];
  [MS_USER_DEFAULTS removeObjectForKey:kMSIgnoredReleaseIdKey];

  // If
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock checkLatestRelease:[OCMArg any]]).andDo(nil);
  OCMStub([distributeMock requestUpdateToken]).andDo(nil);

  // When
  [distributeMock applyEnabledState:YES];

  // Then
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSUpdateTokenRequestIdKey]);
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSIgnoredReleaseIdKey]);

  // When
  [distributeMock applyEnabledState:NO];

  // Then
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSUpdateTokenRequestIdKey]);
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSIgnoredReleaseIdKey]);
}

- (void)testApplyEnabledStateTrue {

  // If
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock checkLatestRelease:[OCMArg any]]).andDo(nil);
  OCMStub([distributeMock requestUpdateToken]).andDo(nil);

  // When
  [distributeMock applyEnabledState:YES];

  // Then
  XCTAssertTrue([distributeMock checkForUpdatesAllowed]);
  OCMVerify([distributeMock requestUpdateToken]);

  // If
  [MSKeychainUtil storeString:@"UpdateToken" forKey:kMSUpdateTokenKey];

  // When
  [distributeMock applyEnabledState:YES];

  // Then
  OCMVerify([distributeMock checkLatestRelease:[OCMArg any]]);

  // If
  [MS_USER_DEFAULTS setObject:@"RequestID" forKey:kMSUpdateTokenRequestIdKey];
  [MS_USER_DEFAULTS setObject:@"ReleaseID" forKey:kMSIgnoredReleaseIdKey];

  // Then
  XCTAssertNotNil([MS_USER_DEFAULTS objectForKey:kMSUpdateTokenRequestIdKey]);
  XCTAssertNotNil([MS_USER_DEFAULTS objectForKey:kMSIgnoredReleaseIdKey]);

  // When
  [distributeMock applyEnabledState:NO];

  // Then
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSUpdateTokenRequestIdKey]);
  XCTAssertNil([MS_USER_DEFAULTS objectForKey:kMSIgnoredReleaseIdKey]);
}

- (void)testcheckForUpdatesAllConditionsMet {

  // If
  [MSDistributeTestUtil unMockUpdatesAllowedConditions];
  id mobileCenterMock = OCMClassMock([MSMobileCenter class]);
  id utilMock = OCMClassMock([MSUtility class]);
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock checkLatestRelease:[OCMArg any]]).andDo(nil);
  OCMStub([distributeMock requestUpdateToken]).andDo(nil);

  // When
  OCMStub([mobileCenterMock isDebuggerAttached]).andReturn(NO);
  OCMStub([utilMock isRunningInDebugConfiguration]).andReturn(NO);
  OCMStub([utilMock currentAppEnvironment]).andReturn(MSEnvironmentOther);

  // Then
  XCTAssertTrue([self.sut checkForUpdatesAllowed]);

  // When
  [distributeMock applyEnabledState:YES];

  // Then
  XCTAssertTrue([distributeMock checkForUpdatesAllowed]);
  OCMVerify([distributeMock requestUpdateToken]);
}

- (void)testcheckForUpdatesDebuggerAttached {

  // When
  [MSDistributeTestUtil unMockUpdatesAllowedConditions];
  id mobileCenterMock = OCMClassMock([MSMobileCenter class]);
  id utilMock = OCMClassMock([MSUtility class]);
  OCMStub([mobileCenterMock isDebuggerAttached]).andReturn(YES);
  OCMStub([utilMock isRunningInDebugConfiguration]).andReturn(NO);
  OCMStub([utilMock currentAppEnvironment]).andReturn(MSEnvironmentOther);

  // Then
  XCTAssertFalse([self.sut checkForUpdatesAllowed]);
}

- (void)testcheckForUpdatesDebugConfig {

  // When
  [MSDistributeTestUtil unMockUpdatesAllowedConditions];
  id mobileCenterMock = OCMClassMock([MSMobileCenter class]);
  id utilMock = OCMClassMock([MSUtility class]);
  OCMStub([mobileCenterMock isDebuggerAttached]).andReturn(NO);
  OCMStub([utilMock isRunningInDebugConfiguration]).andReturn(YES);
  OCMStub([utilMock currentAppEnvironment]).andReturn(MSEnvironmentOther);

  // Then
  XCTAssertFalse([self.sut checkForUpdatesAllowed]);
}

- (void)testcheckForUpdatesInvalidEnvironment {

  // When
  [MSDistributeTestUtil unMockUpdatesAllowedConditions];
  id mobileCenterMock = OCMClassMock([MSMobileCenter class]);
  id utilMock = OCMClassMock([MSUtility class]);
  OCMStub([mobileCenterMock isDebuggerAttached]).andReturn(NO);
  OCMStub([utilMock isRunningInDebugConfiguration]).andReturn(NO);
  OCMStub([utilMock currentAppEnvironment]).andReturn(MSEnvironmentTestFlight);

  // Then
  XCTAssertFalse([self.sut checkForUpdatesAllowed]);
}

- (void)testNotDeleteUpdateToken {

  // If
  id userDefaultsMock = OCMClassMock([MSUserDefaults class]);
  OCMStub([userDefaultsMock shared]).andReturn(userDefaultsMock);
  OCMStub([userDefaultsMock objectForKey:kMSSDKHasLaunchedWithDistribute]).andReturn(@1);
  id keychainMock = OCMClassMock([MSKeychainUtil class]);

  // When
  [MSDistribute new];

  // Then
  OCMReject([keychainMock deleteStringForKey:kMSUpdateTokenKey]);
}

- (void)testDeleteUpdateTokenAfterReinstall {

  // If
  id userDefaultsMock = OCMClassMock([MSUserDefaults class]);
  OCMStub([userDefaultsMock shared]).andReturn(userDefaultsMock);
  OCMStub([userDefaultsMock objectForKey:kMSSDKHasLaunchedWithDistribute]).andReturn(nil);
  id keychainMock = OCMClassMock([MSKeychainUtil class]);

  // When
  [MSDistribute new];

  // Then
  OCMVerify([keychainMock deleteStringForKey:kMSUpdateTokenKey]);
  OCMVerify([userDefaultsMock setObject:@(1) forKey:kMSSDKHasLaunchedWithDistribute]);
}

- (void)testWithoutNetwork {

  // If
  id reachabilityMock = OCMClassMock([MS_Reachability class]);
  OCMStub([reachabilityMock reachabilityForInternetConnection]).andReturn(reachabilityMock);
  [reachabilityMock setValue:NotReachable forKey:@"currentReachabilityStatus"];
  id distributeMock = OCMPartialMock(self.sut);

  // When
  [distributeMock requestUpdateToken];

  // Then
  OCMReject([distributeMock buildTokenRequestURLWithAppSecret:[OCMArg any]]);
}

- (void)testPackageHash {

  // If
  // cd55e7a9-7ad1-4ca6-b722-3d133f487da9:1.0:1 -> 1ddf47f8dda8928174c419d530adcc13bb63cebfaf823d83ad5269b41e638ef4
  id distributeMock = OCMPartialMock(self.sut);
  id bundleMock = OCMClassMock([NSBundle class]);
  OCMStub([bundleMock mainBundle]).andReturn(bundleMock);
  NSDictionary<NSString *, id> *plist = @{ @"CFBundleShortVersionString" : @"1.0", @"CFBundleVersion" : @"1" };
  OCMStub([bundleMock infoDictionary]).andReturn(plist);

  // When
  NSString *hash = MSPackageHash();

  // Then
  assertThat(hash, equalTo(@"1ddf47f8dda8928174c419d530adcc13bb63cebfaf823d83ad5269b41e638ef4"));
}

- (void)testDismissEmbeddedSafari {

  // If
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  id viewControllerMock = OCMClassMock([UIViewController class]);
  self.sut.safariHostingViewController = nil;

  // When
  [self.sut dismissEmbeddedSafari];
  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {
                                 OCMReject([viewControllerMock dismissViewControllerAnimated:OCMOCK_ANY
                                                                                  completion:OCMOCK_ANY]);
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

- (void)testDismissEmbeddedSafariWithNilVC {

  // If
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  self.sut.safariHostingViewController = nil;

  // When
  [self.sut dismissEmbeddedSafari];
  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {

                                 // No exceptions so far test succeeded.
                                 assertThat(self.sut.safariHostingViewController, nilValue());
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

- (void)testDismissEmbeddedSafariWithNilSelf {

  // If
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  self.sut.safariHostingViewController = nil;

  // When
  [self.sut dismissEmbeddedSafari];
  self.sut = nil;

  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {

                                 // No exceptions so far test succeeded.
                                 assertThat(self.sut, nilValue());
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

- (void)testDismissEmbeddedSafariWithValidVC {

  // If
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  id viewControllerMock = OCMClassMock([UIViewController class]);
  self.sut.safariHostingViewController = viewControllerMock;

  // When
  [self.sut dismissEmbeddedSafari];
  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self
      waitForExpectationsWithTimeout:1
                             handler:^(NSError *error) {
                               OCMVerify([viewControllerMock dismissViewControllerAnimated:YES completion:OCMOCK_ANY]);
                               if (error) {
                                 XCTFail(@"Expectation Failed with error: %@", error);
                               }
                             }];
}

- (void)testDismissEmbeddedSafariWhenOpenURL {

  // If
  id distributeMock = OCMPartialMock(self.sut);
  OCMStub([distributeMock sharedInstance]).andReturn(distributeMock);
  OCMStub([distributeMock isEnabled]).andReturn(YES);
  ((MSDistribute *)distributeMock).appSecret = kMSTestAppSecret;
  id userDefaultsMock = OCMClassMock([MSUserDefaults class]);
  OCMStub([userDefaultsMock shared]).andReturn(userDefaultsMock);
  OCMStub([userDefaultsMock objectForKey:kMSUpdateTokenRequestIdKey]).andReturn(@"FIRST-REQUEST");
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?request_id=FIRST-REQUEST&update_token=token",
                                                               [NSString stringWithFormat:kMSDefaultCustomSchemeFormat,
                                                                                          kMSTestAppSecret]]];
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  id viewControllerMock = OCMClassMock([UIViewController class]);
  self.sut.safariHostingViewController = viewControllerMock;

  // When
  [MSDistribute openUrl:url];
  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self
      waitForExpectationsWithTimeout:1
                             handler:^(NSError *error) {
                               OCMVerify([viewControllerMock dismissViewControllerAnimated:YES completion:OCMOCK_ANY]);
                               if (error) {
                                 XCTFail(@"Expectation Failed with error: %@", error);
                               }
                             }];
}

- (void)testDismissEmbeddedSafariWhenDisabling {

  // If
  XCTestExpectation *safariDismissedExpectation = [self expectationWithDescription:@"Safari dismissed processed"];
  id viewControllerMock = OCMClassMock([UIViewController class]);
  self.sut.safariHostingViewController = viewControllerMock;

  // When
  [self.sut applyEnabledState:NO];
  dispatch_async(dispatch_get_main_queue(), ^{
    [safariDismissedExpectation fulfill];
  });

  // Then
  [self
      waitForExpectationsWithTimeout:1
                             handler:^(NSError *error) {
                               OCMVerify([viewControllerMock dismissViewControllerAnimated:YES completion:OCMOCK_ANY]);
                               if (error) {
                                 XCTFail(@"Expectation Failed with error: %@", error);
                               }
                             }];
}

@end
