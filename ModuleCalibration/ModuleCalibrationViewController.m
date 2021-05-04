//
//  ModuleCalibrationViewController.m
//  FlareSensorChecker
//
//  Created by Jack on 2021/4/15.
//  Copyright © 2021 Jackie Wang. All rights reserved.
//

#import "ModuleCalibrationViewController.h"
#import <JKFoundation/JKFoundation.h>

@interface ModuleCalibrationViewController ()

/// common
@property (weak) IBOutlet NSButton      *btSysCalibration;
@property (weak) IBOutlet NSButton      *btLightSourceSwitch;
@property (weak) IBOutlet NSButton      *btDoorSwitch;

/// initial setting
@property (weak) IBOutlet NSButton      *btLoadInitPos;
@property (weak) IBOutlet NSButton      *btMoveToInitPos;
@property (weak) IBOutlet NSButton      *btShowFrameGrabberSettting;
@property (weak) IBOutlet NSTextField   *tfInitPosFile;

/// Laser Calibration
@property (weak) IBOutlet NSButton      *btLaserCalibration;
@property (weak) IBOutlet NSButton      *btLaserBack;
@property (weak) IBOutlet NSTextField   *tfLaserDiffHeight;

/// Luxmeter Check
@property (weak) IBOutlet NSButton      *btLuxPowerOn;
@property (weak) IBOutlet NSButton      *btLuxConnect;
@property (weak) IBOutlet NSButton      *btLuxDarkCalibration;
@property (weak) IBOutlet NSButton      *btLuxMeasure;
@property (weak) IBOutlet NSTextField   *tfLuxmeterLux;
@property (weak) IBOutlet NSTextField   *tfLuxmeterCCT;

/// Go to Flare Position
@property (weak) IBOutlet NSButton      *btFlareGo;
@property (weak) IBOutlet NSButton      *btFlareCapture;
@property (weak) IBOutlet NSTextField   *tfRotation;
@property (weak) IBOutlet NSTextField   *tfSwing;

/// DUT Movement
@property (weak) IBOutlet NSButton      *btDUTMoveLeft;
@property (weak) IBOutlet NSButton      *btDUTMoveRight;
@property (weak) IBOutlet NSButton      *btDUTMoveDoor;
@property (weak) IBOutlet NSButton      *btDUTMoveBack;
@property (weak) IBOutlet NSTextField   *tfDUTMoveOffset;

/// Base Plate Movement
@property (weak) IBOutlet NSButton      *btBaseMoveLeft;
@property (weak) IBOutlet NSButton      *btBaseMoveRight;
@property (weak) IBOutlet NSButton      *btBaseMoveDoor;
@property (weak) IBOutlet NSButton      *btBaseMoveBack;
@property (weak) IBOutlet NSTextField   *tfBaseMoveOffset;

@property (weak) IBOutlet NSButton      *btSavePosition;
@property (weak) IBOutlet NSTextField   *tfSavedPosFile;

@property (weak) IBOutlet NSTextView    *logShower;

@end

@implementation ModuleCalibrationViewController
{
    bool                _connected;
    
    NSArray             *_axisControlGroup;
}

- (instancetype)init {
    self = [super init];
    if(self) {
        [[NSBundle bundleForClass:self.class] loadNibNamed:self.className owner:self topLevelObjects:nil];
        _axisControlGroup = @[_btSysCalibration, _btLightSourceSwitch, _btDoorSwitch,
                              _btLoadInitPos, _btMoveToInitPos, _btShowFrameGrabberSettting,
                              _btLaserCalibration, _btLaserBack,
                              _btLuxPowerOn, _btLuxConnect, _btLuxDarkCalibration, _btLuxMeasure,
                              _btFlareGo, _btFlareCapture, _tfRotation, _tfSwing,
                              _btDUTMoveBack, _btDUTMoveDoor, _btDUTMoveLeft, _btDUTMoveRight,
                              _btBaseMoveBack, _btBaseMoveDoor, _btBaseMoveLeft, _btBaseMoveRight,
                              _tfDUTMoveOffset, _tfBaseMoveOffset,
                              _btSavePosition
        ];
        InitializeSystem();
        for(NSControl *ctrl in _axisControlGroup) {
            ctrl.enabled = NO;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (BOOL)connect {
    _connected = Connect("169.254.1.32");
    dispatch_sync(dispatch_get_main_queue(), ^(){
        self->_btSysCalibration.enabled = YES;
        MLLevel doorLvl = GetInBitState(MLInDoorLeftOpened);
        self->_btDoorSwitch.state = doorLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
        MLLevel lightLvl = GetOutBitState(MLOutLightSourcePower);
        self->_btLightSourceSwitch.state = lightLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
        MLLevel luxLvl = GetOutBitState(MLOutLuxmetePower);
        self->_btLuxPowerOn.image = luxLvl==MLLow ? [NSImage imageNamed:@"greenLedMini"] : [NSImage imageNamed:@"redLedMini"];
        self->_btLuxConnect.image = [NSImage imageNamed:@"redLedMini"];
    });
    
    return _connected;
}

- (void)disconnect {
    Disconnect();
    _connected = NO;
    dispatch_async(dispatch_get_main_queue(), ^(){
        self->_btDoorSwitch.state = NSControlStateValueOff;
        self->_btLightSourceSwitch.state = NSControlStateValueOff;
        self->_btLuxPowerOn.image  = [NSImage imageNamed:@"redLedMini"];
        self->_btLuxConnect.image = [NSImage imageNamed:@"redLedMini"];
        self->_btSysCalibration.image = [NSImage imageNamed:@"redLedMini"];
        for(NSControl *ctrl in self->_axisControlGroup) {
            ctrl.enabled = NO;
        }
    });
}

- (void)display:(NSString *)message color:(NSColor *)color {
    dispatch_block_t block = ^(){
        NSString *str = [NSString stringWithFormat:@"%@ %@\n", [self currentTimeString], message];
        NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str attributes:@{NSForegroundColorAttributeName : color}];
        [self.logShower.textStorage appendAttributedString:attributeString];
        [self.logShower scrollRangeToVisible:NSMakeRange(self.logShower.string.length, 0)];
    };
    if(NSThread.currentThread.isMainThread) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"[yyyy-MM-dd HH:mm:ss]:"];
    return [formatter stringFromDate:NSDate.date];
}

- (IBAction)systemCalibration:(NSButton *)sender {
    for(NSControl *ctrl in _axisControlGroup) {
        ctrl.enabled = NO;
    }
    [self display:@"start system calibration..." color:NSColor.darkGrayColor];
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        PowerOn();
        bool isReady = NO, isStopped = NO;
        while(isReady==NO && isStopped==NO) {
            usleep(1000*100);
            isReady = IsMoveFinished();
            isStopped = IsStopActived();
        }
        if(isReady) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                [self display:@"system calibration finished." color:NSColor.darkGrayColor];
                self->_btSysCalibration.image = [NSImage imageNamed:@"greenLedMini"];
                for(NSControl *ctrl in self->_axisControlGroup) {
                    ctrl.enabled = YES;
                }
                if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                    self->_btLuxDarkCalibration.enabled = NO;
                    self->_btLuxMeasure.enabled = NO;
                }
            });
        }
    });
}

- (IBAction)lightSwitch:(NSButton *)sender {
    sender.enabled = NO;
    __block NSControlStateValue state = sender.state;
    [self display:state==NSControlStateValueOn?@"Opening light source....":@"Closing light source...." color:NSColor.darkGrayColor];
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        SetBitState(MLOutLightSourcePower, state==NSControlStateValueOn?MLLow:MLHigh);
        dispatch_async(dispatch_get_main_queue(), ^(){
            usleep(1000*500);
            MLLevel lightLvl = GetOutBitState(MLOutLightSourcePower);
            self->_btLightSourceSwitch.state = lightLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
            self->_btLightSourceSwitch.enabled = YES;
            NSString *msg = [NSString stringWithFormat:@"light source is %@", lightLvl==MLLow ? @"ON" : @"OFF"];
            [self display:msg color:NSColor.darkGrayColor];
        });
    });
}

- (IBAction)doorSwitch:(NSButton *)sender {
    sender.enabled = NO;
    __block NSControlStateValue state = sender.state;
    NSString *msg = [NSString stringWithFormat:@"%@ door...", state==NSControlStateValueOn ? @"opening" : @"closing"];
    [self display:msg color:NSColor.darkGrayColor];
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        if(state==NSControlStateValueOn) {
            DoorOpen();
        } else {
            DoorClose();
        }
        dispatch_async(dispatch_get_main_queue(), ^(){
            MLLevel doorLvl = GetInBitState(MLInDoorLeftOpened);
            self->_btDoorSwitch.state = doorLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
            self->_btDoorSwitch.enabled = YES;
            NSString *msg = [NSString stringWithFormat:@"door is %@", doorLvl==MLLow ? @"opened" : @"closed"];
            [self display:msg color:NSColor.darkGrayColor];
        });
    });
}



- (IBAction)loadInitPosFile:(NSButton *)sender {
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    oPanel.allowedFileTypes = @[@"txt"];
    oPanel.directoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    if([oPanel runModal]==NSModalResponseOK) {
        NSString *posStr = [NSString stringWithContentsOfFile:oPanel.URL.relativePath encoding:NSUTF8StringEncoding error:nil];
        NSMutableArray *posData = [[posStr componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
        [posData removeObject:@""];
        if(posData.count!=10) {
            _tfInitPosFile.stringValue = @"";
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Invalid initial Position file";
            alert.informativeText = @"the file must contains 10 axes positions";
            [alert runModal];
        } else {
            _tfInitPosFile.stringValue = oPanel.URL.relativePath;
        }
    } else {
        _tfInitPosFile.stringValue = @"";
    }
}

- (IBAction)moveToInitPos:(NSButton *)sender {
    if(_connected) {
        for(NSControl *ctrl in _axisControlGroup) {
            ctrl.enabled = NO;
        }
        NSString *msg = [NSString stringWithFormat:@"moving all axes move initial position..."];
        [self display:msg color:NSColor.darkGrayColor];
        __block NSString *path = _tfInitPosFile.stringValue;
        dispatch_async(dispatch_get_global_queue(0, 0), ^(){
            int axes[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
            if(path.length>0) {
                NSString *posStr = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                NSArray<NSString *> *posData = [posStr componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
                if(posData.count!=10) {
                    dispatch_sync(dispatch_get_main_queue(), ^(){
                        self->_tfInitPosFile.stringValue = @"";
                        NSAlert *alert = [NSAlert new];
                        alert.messageText = @"Invalid initial Position file";
                        alert.informativeText = @"the file must contains 10 axes positions";
                        [alert runModal];
                    });
                } else {
                    for(int axis=1; axis<=posData.count; axis++) {
                        MoveAxisToPosition(axis, posData[axis-1].doubleValue, false, false);
                    }
                    CheckAxisState(axes, 10, false);
                }
            } else {
                MoveToInitPos(axes, 10);
            }
            dispatch_async(dispatch_get_main_queue(), ^(){
                NSString *msg = [NSString stringWithFormat:@"all axes moved to initial position."];
                [self display:msg color:NSColor.darkGrayColor];
                for(NSControl *ctrl in self->_axisControlGroup) {
                    ctrl.enabled = YES;
                }
                if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                    self->_btLuxDarkCalibration.enabled = NO;
                    self->_btLuxMeasure.enabled = NO;
                }
            });
        });
    }
}

- (IBAction)showGrabberSetting:(NSButton *)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Not implemented";
    [alert runModal];
}

- (IBAction)laserCalibration:(NSButton *)sender {
    if(_connected) {
        __block NSString *laserPortName = @"/dev/cu.usbserial-Laser";
        if([JKSerialPort.portPaths containsObject:laserPortName]==NO) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Cann't find the Laser port{/dev/cu.usbserial-Laser}!";
            alert.informativeText = laserPortName;
            [alert runModal];
            return;
        }
        for(NSControl *ctrl in _axisControlGroup) {
            ctrl.enabled = NO;
        }
        NSString *msg = [NSString stringWithFormat:@"start laser calibration..."];
        [self display:msg color:NSColor.darkGrayColor];
        __block int axisLift = 4;
        dispatch_async(dispatch_get_global_queue(0, 0), ^(){
            SetBitState(MLOutSpotPower, MLHigh);
            int axes[] = {MLAxisRotationY};
            MoveToInitPos(axes, 1);
            
            int axes1[] = {MLAxisLaser};
            JMoveAxis(MLAxisLaser, 0, false);   // move to negative limit
            usleep(100*1000);
            CheckAxisState(axes1, 1, false);     // wait axis stopped
            usleep(100*1000);
            SetBitState(MLOutLaserPower, MLLow);
            usleep(2000*1000);
            
            char port[128];
            sprintf(port, "%s", [laserPortName cStringUsingEncoding:NSUTF8StringEncoding]);
            double heightBase = GetLaserDiffOfHeight(port);
            int counter = 0;
            while(heightBase==-99.998 && counter++<3) {
                usleep(1000*500);
                heightBase = GetLaserDiffOfHeight(port);
            }
            if(heightBase==-99.998) {
                dispatch_async(dispatch_get_main_queue(), ^(){
                    NSAlert *alert = [NSAlert new];
                    alert.messageText = @"Failed to measure the height";
                    [alert runModal];
                    self->_tfLaserDiffHeight.stringValue = @"----";
                });
            } else {
                usleep(1000*1000);
                heightBase = GetLaserDiffOfHeight(port);
                
                double dutPos = GetLaserDUTPos();
                MoveAxisToPosition(MLAxisLaser, dutPos, false, false);  // start laser axis to dut-pos
                usleep(100*1000);
                CheckAxisState(axes1, 1, false);                         // wait axis stopped
                usleep(2000*1000);
                bool calibrationSuccess = false;
                double heightDUT = GetLaserDiffOfHeight(port);
                int counter = 0;
                while(heightDUT==-99.998 && counter++<3) {
                    usleep(1000*500);
                    heightDUT = GetLaserDiffOfHeight(port);
                }
                if(heightDUT==-99.998) {
                    dispatch_async(dispatch_get_main_queue(), ^(){
                        NSAlert *alert = [NSAlert new];
                        alert.messageText = @"Failed to measure the height";
                        [alert runModal];
                        self->_tfLaserDiffHeight.stringValue = @"----";
                    });
                } else {
                    double hDiff = heightBase-heightDUT;
                    double newHeightDUT = -1;
                    for(int i=0; i<5&&calibrationSuccess==false; i++) {
                        heightDUT = GetLaserDiffOfHeight(port);
                        double distance = heightBase-heightDUT;                 //  the offset from dut to base
                        int axes1[] = {axisLift};
                        MoveAxisDistance(axisLift, distance, false, false); // move offset
                        usleep(100*1000);
                        CheckAxisState(axes1, 1, false);                        // wait axis stopped
                        usleep(500*1000);
                        newHeightDUT = GetLaserDiffOfHeight(port);
                        calibrationSuccess = fabs(newHeightDUT-heightBase)<0.01;
                    }
                    
                    SetBitState(MLOutLaserPower, MLHigh);
                    
                    NSString *msg = [NSString stringWithFormat:@"laser calibration finished."];
                    [self display:msg color:NSColor.darkGrayColor];
                    dispatch_sync(dispatch_get_main_queue(), ^(){
                        self->_tfLaserDiffHeight.stringValue = [NSString stringWithFormat:@"%.4lf", hDiff];
                    });
                    
                    // move to spot pos
                    SetBitState(MLOutSpotPower, MLLow);
                    double spotPos = GetLaserSpotPos();
                    MoveAxisToPosition(MLAxisLaser, spotPos, YES, NO);
                    CheckAxisState(axes, 1, false);     // wait axis stopped
                }
            }
            dispatch_sync(dispatch_get_main_queue(), ^(){
                for(NSControl *ctrl in self->_axisControlGroup) {
                    ctrl.enabled = YES;
                }
                if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                    self->_btLuxDarkCalibration.enabled = NO;
                    self->_btLuxMeasure.enabled = NO;
                }
            });
        });
    }
}

- (IBAction)laserBack:(NSButton *)sender {
    if(_connected) {
        for(NSControl *ctrl in _axisControlGroup) {
            ctrl.enabled = NO;
        }
        NSString *msg = [NSString stringWithFormat:@"laser back"];
        [self display:msg color:NSColor.darkGrayColor];
        dispatch_async(dispatch_get_global_queue(0, 0), ^(){
            int axes[] = {MLAxisLaser};
            JMoveAxis(MLAxisLaser, 0, false);
            usleep(1000*100);
            CheckAxisState(axes, 1, false);
            SetBitState(MLOutLaserPower, MLHigh);
            SetBitState(MLOutSpotPower, MLHigh);
            dispatch_sync(dispatch_get_main_queue(), ^(){
                for(NSControl *ctrl in self->_axisControlGroup) {
                    ctrl.enabled = YES;
                }
                if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                    self->_btLuxDarkCalibration.enabled = NO;
                    self->_btLuxMeasure.enabled = NO;
                }
            });
        });
    }
}

- (IBAction)goSpotPosition:(NSButton *)sender {
    double spotPos = GetLaserSpotPos();
    MoveAxisToPosition(MLAxisLaser, spotPos, YES, NO);
}

- (IBAction)luxmeterPowerOn:(NSButton *)sender {
    sender.enabled = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        SetBitState(MLOutLuxmetePower, MLLow);
        usleep(1000*3000);  // waiting for stable
        dispatch_sync(dispatch_get_main_queue(), ^(){
            sender.enabled = YES;
            self->_btLuxConnect.enabled = YES;
        });
    });
}

- (IBAction)luxmeterConnect:(NSButton *)sender {
    sender.enabled = NO;
    gDarkLuxmeterValue = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        NSString *luxPath = @"/dev/cu.usbserial-Luxmeter";
        if([JKSerialPort.portPaths containsObject:luxPath]) {
            NSString *msg = [NSString stringWithFormat:@"connecting luxmeter..."];
            [self display:msg color:NSColor.darkGrayColor];
            if(ConnectIlluminometer((char *)luxPath.UTF8String)) {
                NSString *msg = [NSString stringWithFormat:@"connected to luxmeter."];
                [self display:msg color:NSColor.darkGrayColor];
                dispatch_sync(dispatch_get_main_queue(), ^(){
                    sender.state = NSControlStateValueOn;
                    sender.image = [NSImage imageNamed:@"greenLedMini"];
                });
            } else {
                NSString *msg = [NSString stringWithFormat:@"failed to connect luxmeter"];
                [self display:msg color:NSColor.darkGrayColor];
                dispatch_sync(dispatch_get_main_queue(), ^(){
                    sender.state = NSControlStateValueOff;
                    sender.image = [NSImage imageNamed:@"redLedMini"];
                });
            }
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^(){
                sender.state = NSControlStateValueOff;
                sender.image = [NSImage imageNamed:@"redLedMini"];
                NSAlert *alert = [NSAlert new];
                alert.messageText = [NSString stringWithFormat:@"Cannot find the luxmeter:\r\n%@", luxPath];
                [alert runModal];
            });
        }
        dispatch_sync(dispatch_get_main_queue(), ^(){
            sender.enabled = YES;
            self->_btLuxDarkCalibration.enabled = YES;
            self->_btLuxMeasure.enabled = YES;
        });
    });
}

static double gDarkLuxmeterValue;
- (IBAction)luxmeterDarkCalibration:(NSButton *)sender {
    self->_btLuxDarkCalibration.enabled = NO;
    self->_btLuxMeasure.enabled = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        NSString *msg = [NSString stringWithFormat:@"start luxmeter dark calibration..."];
        [self display:msg color:NSColor.darkGrayColor];
        SetBitState(MLOutCylinderHome, MLLow);      // cylinder back;
        SetBitState(MLOutLuxmetePower, MLLow);      // power on Luxmeter;
        SetBitState(MLOutLightSourcePower, MLHigh);
        SetBitState(MLOutLaserPower, MLHigh);
        SetBitState(MLOutSpotPower, MLHigh);
        
        NSString *luxPath = @"/dev/cu.usbserial-Luxmeter";
        DoorClose();    // close door;
        dispatch_async(dispatch_get_main_queue(), ^(){
            MLLevel doorLvl = GetInBitState(MLInDoorLeftOpened);
            self->_btDoorSwitch.state = doorLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
            self->_btDoorSwitch.enabled = YES;
        });

        usleep(1000*3000);
        if(ConnectIlluminometer((char *)luxPath.UTF8String)) {
            __block double *values = malloc(sizeof(double)*3);
            LuxmeterMeasure(values, 3, 5000);
            gDarkLuxmeterValue = values[0];
            dispatch_sync(dispatch_get_main_queue(), ^(){
                self->_tfLuxmeterLux.stringValue = [NSString stringWithFormat:@"%.lf", values[0]];
                self->_tfLuxmeterCCT.stringValue = [NSString stringWithFormat:@"%.1lf", values[1]];
            });
            NSString *msg = [NSString stringWithFormat:@"dark value: %.lf", values[0]];
            [self display:msg color:NSColor.darkGrayColor];
            free(values);
            DoorOpen();
            dispatch_async(dispatch_get_main_queue(), ^(){
                MLLevel doorLvl = GetInBitState(MLInDoorLeftOpened);
                self->_btDoorSwitch.state = doorLvl==MLLow ? NSControlStateValueOn : NSControlStateValueOff;
                self->_btDoorSwitch.enabled = YES;
                self->_btLuxDarkCalibration.enabled = YES;
                self->_btLuxMeasure.enabled = YES;
            });
        }
    });
}

- (IBAction)luxmeterMeasure:(NSButton *)sender {
    __block double *values = malloc(sizeof(double)*3);
    self->_btLuxDarkCalibration.enabled = NO;
    self->_btLuxMeasure.enabled = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
        NSString *msg = [NSString stringWithFormat:@"start luxmeter measurement..."];
        [self display:msg color:NSColor.darkGrayColor];
        SetBitState(MLOutLaserPower, MLHigh);
        SetBitState(MLOutSpotPower, MLHigh);
        
        DoorClose();
        SetBitState(MLOutLightSourcePower, MLLow);
        SetBitState(MLOutCylinderShop, MLLow);
        LuxmeterMeasure(values, 3, 5000);
        SetBitState(MLOutLightSourcePower, MLHigh);
        SetBitState(MLOutCylinderShop, MLHigh);
        DoorOpen();
    
        msg = [NSString stringWithFormat:@"luxmeter: %.lf", values[0]-gDarkLuxmeterValue];
        [self display:msg color:NSColor.darkGrayColor];
        dispatch_sync(dispatch_get_main_queue(), ^(){
            self->_tfLuxmeterLux.stringValue = [NSString stringWithFormat:@"%.lf", values[0]-gDarkLuxmeterValue];
            self->_tfLuxmeterCCT.stringValue = [NSString stringWithFormat:@"%.1lf", values[1]];
            sender.enabled = YES;
            self->_btLuxDarkCalibration.enabled = YES;
            self->_btLuxMeasure.enabled = YES;
        });
        free(values);
    });
}

- (IBAction)doDUTModuleMovement:(NSButton *)sender {
    if(_connected) {
        __block MLAxis axis = [sender.identifier intValue];
        __block int dir = [[sender.identifier substringWithRange:NSMakeRange(sender.identifier.length-1, 1)] isEqualTo:@"-"] ? -1 : 1;
        __block double offset = axis==5||axis==6 ? fabs(_tfDUTMoveOffset.stringValue.doubleValue) : fabs(_tfBaseMoveOffset.stringValue.doubleValue);
        for(NSControl *ctrl in _axisControlGroup) {
            ctrl.enabled = NO;
        }
        NSString *msg = [NSString stringWithFormat:@"moving axis %d(offset:%.1lf)...", axis, dir*offset];
        [self display:msg color:NSColor.darkGrayColor];
        dispatch_async(dispatch_get_global_queue(0, 0), ^(){
            int axes[] = {axis};
            MoveAxisDistance(axis, offset*dir, false, false);
            usleep(100*1000);
            CheckAxisState(axes, 1, false);
            dispatch_sync(dispatch_get_main_queue(), ^(){
                NSString *msg = [NSString stringWithFormat:@"finish moved"];
                [self display:msg color:NSColor.darkGrayColor];
                for(NSControl *ctrl in self->_axisControlGroup) {
                    ctrl.enabled = YES;
                }
                if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                    self->_btLuxDarkCalibration.enabled = NO;
                    self->_btLuxMeasure.enabled = NO;
                }
            });
        });
    }
}

- (IBAction)flareGO:(NSButton *)sender {
    if(_tfInitPosFile.stringValue.length>0) {
        NSString *posStr = [NSString stringWithContentsOfFile:_tfInitPosFile.stringValue encoding:NSUTF8StringEncoding error:nil];
        NSMutableArray *posData = [[posStr componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
        [posData removeObject:@""];
        if(posData.count!=10) {
            _tfInitPosFile.stringValue = @"";
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Invalid initial Position file";
            alert.informativeText = @"the file must contains 10 axes positions";
            [alert runModal];
        } else {
            if(_connected) {
                for(NSControl *ctrl in _axisControlGroup) {
                    ctrl.enabled = NO;
                }
                __block NSString *path = _tfInitPosFile.stringValue;
                __block double rPos = _tfRotation.doubleValue;
                __block double sPos = _tfSwing.doubleValue;
                NSString *msg = [NSString stringWithFormat:@"start flare go(Rotation: %.1lf, Swing: %.1lf)...", rPos, sPos];
                [self display:msg color:NSColor.darkGrayColor];
                dispatch_async(dispatch_get_global_queue(0, 0), ^(){
                    SetBitState(MLOutCylinderHome, MLLow);  // cylinder back;
                    
                    // laser back;
                    int axes[] = {MLAxisLaser};
                    JMoveAxis(MLAxisLaser, 0, false);
                    usleep(1000*100);
                    CheckAxisState(axes, 1, false);
                    
//                    int axes[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
                    NSString *posStr = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                    NSArray<NSString *> *posData = [posStr componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
                    // move all axes to initial position
//                    for(int axis=1; axis<=posData.count; axis++) {
//                        MoveAxisToPosition(axis, posData[axis-1].doubleValue, false, false);
//                    }
//                    CheckAxisState(axes, 10, false);
                    double rTargetPos = posData[MLAxisRotation-1].doubleValue+rPos;
                    double sTargetPos = posData[MLAxisRotationY-1].doubleValue+sPos;
                    MoveAxisToPosition(MLAxisRotation, rTargetPos, false, false);
                    MoveAxisToPosition(MLAxisRotationY, sTargetPos, false, false);
                    int axes1[] = {MLAxisRotation, MLAxisRotationY};
                    CheckAxisState(axes1, 2, false);
                    NSString *msg = [NSString stringWithFormat:@"finish flare go"];
                    [self display:msg color:NSColor.darkGrayColor];
                    dispatch_sync(dispatch_get_main_queue(), ^(){
                        for(NSControl *ctrl in self->_axisControlGroup) {
                            ctrl.enabled = YES;
                        }
                        if([self->_btLuxConnect.image isEqualTo:[NSImage imageNamed:@"redLedMini"]]) {
                            self->_btLuxDarkCalibration.enabled = NO;
                            self->_btLuxMeasure.enabled = NO;
                        }
                    });
                });
            }
        }
    } else {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Please load initial position file at first";
        [alert runModal];
    }
}

- (IBAction)flareCapture:(NSButton *)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Not implemented";
    [alert runModal];
}

- (IBAction)savePosition:(id)sender {
    NSSavePanel *sPanel = [NSSavePanel savePanel];
    sPanel.directoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    sPanel.nameFieldStringValue = @"init_position";
    sPanel.allowedFileTypes = @[@"txt"];
    _tfSavedPosFile.stringValue = @"";
    if([sPanel runModal]) {
        NSMutableString *posStr = [NSMutableString new];
        for(int axis=1; axis<=10; axis++) {
            double pos = GetAxisPosition(axis);
            [posStr appendFormat:@"%.6lf\r\n", pos];
        }
        NSError *err = nil;
        [posStr writeToFile:sPanel.URL.relativePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if(err) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Failed to save init positioin of axes";
            alert.informativeText = err.description;
            [alert runModal];
        }else {
            NSString *msg = [NSString stringWithFormat:@"saved all axes position in file(%@)", sPanel.URL.relativePath];
            [self display:msg color:NSColor.darkGrayColor];
            _tfSavedPosFile.stringValue = sPanel.URL.relativePath;
            [NSWorkspace.sharedWorkspace openURL:sPanel.directoryURL];
        }
    }
}


- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *tf = obj.object;
    if([@[_tfDUTMoveOffset, _tfBaseMoveOffset] containsObject:tf]) {
        if(tf.stringValue.length==0) {
            tf.stringValue = @"1";
        }
    } else if([tf isEqualTo:_tfSwing]) {
        if(tf.doubleValue<-90) tf.stringValue = @"-90";
        if(tf.doubleValue>90) tf.stringValue = @"90";
    } else if([tf isEqualTo:_tfRotation]) {
        if(tf.doubleValue<-180) tf.stringValue = @"-180";
        if(tf.doubleValue>163) tf.stringValue = @"163";
    }
}



@end
