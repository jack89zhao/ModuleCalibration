//
//  IOCheckerWindowController.h
//  FlareSensorChecker
//
//  Created by Jackie Wang on 2020/7/1.
//  Copyright © 2020 Jackie Wang. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface IOCheckerWindowController : NSWindowController

@property BOOL sysConnected;
- (instancetype)initWithControllerState:(BOOL)controllerState;

@end

NS_ASSUME_NONNULL_END
