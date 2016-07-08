/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 */

#import "AVALog.h"
#import <Foundation/Foundation.h>

@interface AVALogContainer : NSObject

/**
 * Unique batch Id.
 */
@property(nonatomic) NSString *batchId;

/**
 * The list of logs
 */
@property(nonatomic) NSArray<AVALog> *logs;

/**
 * Initializer
 *
 * batchID Unique batch Id
 */
- (id)initWithBatchId:(NSString *)batchId;

/**
 * Serialize logs into a JSON string
 */
- (NSString *)serializeLog;

/**
 * Is valid container
 */
- (BOOL)isValid;

@end