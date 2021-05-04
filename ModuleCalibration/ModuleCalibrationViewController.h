//
//  ModuleCalibrationViewController.h
//  FlareSensorChecker
//
//  Created by Jack on 2021/4/15.
//  Copyright © 2021 Jackie Wang. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MLFlare.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModuleCalibrationViewController : NSViewController

- (BOOL)connect;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
