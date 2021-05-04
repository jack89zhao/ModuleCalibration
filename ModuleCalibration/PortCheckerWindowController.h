//
//  PortCheckerViewController.h
//  FlareSensorChecker
//
//  Created by Jackie Wang on 2020/6/29.
//  Copyright © 2020 Jackie Wang. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PortCheckerWindowController : NSWindowController

- (void)checkPortname;
- (void)setConnectState:(BOOL)connected;

@end

NS_ASSUME_NONNULL_END
