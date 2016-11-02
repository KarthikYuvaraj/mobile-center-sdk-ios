/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 */

#import "MobileCenter+Internal.h"
#import <Foundation/Foundation.h>

@class SNMStackFrame;

@interface SNMException : NSObject <MSSerializableObject>

/*
 * Exception type.
 */
@property(nonatomic, nonnull) NSString *type;

/*
 * Exception reason.
 */
@property(nonatomic, nonnull) NSString *message;

/*
 * Stack frames [optional].
 */
@property(nonatomic, nullable) NSArray<SNMStackFrame *> *frames;

/*
 * Inner exceptions of this exception [optional].
 */
@property(nonatomic, nullable) NSArray<SNMException *> *innerExceptions;

/**
 * Is equal to another exception
 *
 * @param exception Exception
 *
 * @return Return YES if equal and NO if not equal
 */
- (BOOL)isEqual:(nullable SNMException *)exception;

@end
