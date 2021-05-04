//
//  AppDelegate.m
//  FlareSensorChecker
//
//  Created by Jackie Wang on 2020/4/28.
//  Copyright © 2020 Jackie Wang. All rights reserved.
//

#import "AppDelegate.h"
#import "PortCheckerWindowController.h"
#import "IOCheckerWindowController.h"
#import "LTSMC.h"
#import "ModuleCalibrationViewController.h"

static int homeModes[] = {27, 27, 27, 27, 27, 27, 30, 30, 30, 30};
static int homeOffset[] = {1, -1, -1, -1, -1, -1, 1, 1, 1, 1};

@interface AppDelegate () <NSTableViewDelegate, NSTableViewDataSource>
{
    int _controllerID;
    BOOL _connected;
    BOOL _isMoving;
    BOOL _isStopCalibrated;
    int _selectedAxis;
    NSMutableArray *_tableDataSource;
    NSArray *_tableColumnIdentifier;
    NSDictionary *_axisParams;
    PortCheckerWindowController *_portWindowController;
}
@property (weak) IBOutlet NSTableView *tableView;
@property (unsafe_unretained) IBOutlet NSTextView *failMsgText;
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSComboBox *cbAxis;

@property (weak) IBOutlet NSTabView     *tabView;

@property (weak) IBOutlet ModuleCalibrationViewController   *mcViewController;


@end

@implementation AppDelegate

- (void)loadTableDataSource {
    NSMutableArray *keys = [NSMutableArray new];
    
    for (NSTableColumn *tableColumn in [self.tableView tableColumns]) {
        [keys addObject:tableColumn.identifier];
    }
    _tableColumnIdentifier = [keys copy];
    
    for (int row = 0; row < _axisParams.count; row++) {
        NSMutableDictionary *rowDict = [NSMutableDictionary new];
        for (int col = 0; col < 8; col++) {
            if (col == 0) {
                [rowDict setObject:@(row+1) forKey:keys[col]];
            } else if (col == 6) {
                [rowDict setObject:@"--" forKey:keys[col]];
            } else if (col == 7) {
                [rowDict setObject:@"--Pending--" forKey:keys[col]];
            } else {
                [rowDict setObject:@(0) forKey:keys[col]];
            }
        }
        [_tableDataSource addObject:rowDict];
    }
    
    [self.tableView reloadData];
}

- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"[yyyy-MM-dd HH:mm:ss]:"];
    return [formatter stringFromDate:NSDate.date];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _mcViewController.view.frame = _tabView.tabViewItems.firstObject.view.bounds;
    [_tabView.tabViewItems.firstObject.view addSubview:_mcViewController.view];
    
    if (!_axisParams) {
        NSString *path = [NSBundle.mainBundle pathForResource:@"Profile" ofType:@"plist"];
        _axisParams = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    // Insert code here to initialize your application
    if (!_tableDataSource) {
        _tableDataSource = [NSMutableArray new];
    }
    
    if (!_portWindowController) {
        _portWindowController = [[PortCheckerWindowController alloc] init];
    }
    
    [self.tableView setRowSizeStyle:NSTableViewRowSizeStyleCustom];
    [self loadTableDataSource];
    
    NSString *str = [NSString stringWithFormat:@"%@ Success to launch application\n", [self currentTimeString]];
    NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str attributes:@{NSForegroundColorAttributeName : NSColor.darkGrayColor}];
    
    self.failMsgText.editable = NO;
    [self.failMsgText.textStorage appendAttributedString:attributeString];
    [self.failMsgText scrollPageDown:self];
    
    [_cbAxis removeAllItems];
    [_cbAxis addItemsWithObjectValues:[_axisParams.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
        NSInteger num1 = [obj1 substringFromIndex:4].intValue;
        NSInteger num2 = [obj2 substringFromIndex:4].intValue;
        return num1<num2 ? NSOrderedAscending : NSOrderedDescending;
    }]];
    [NSThread detachNewThreadSelector:@selector(checkSensor) toTarget:self withObject:nil];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    if (_connected) {
        smc_stop(_controllerID, _selectedAxis, 0);
        
        nmcs_clear_card_errcode(_controllerID);   // clear card error
        nmcs_clear_errcode(_controllerID,0);      // clear bus error
        
        for (int axis = 1; axis <= _axisParams.count; axis++) {
            nmcs_clear_axis_errcode(_controllerID, axis);
        }
        
//        int rtn = 0;
//        for (int i = 1; i <= _axisParams.count ; i++) {
//            rtn |= smc_write_sevon_pin(_controllerID, i, 1);
//            usleep(5000);
//        }
        
        smc_board_close(_controllerID);
        _connected = NO;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    [self.failMsgText.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
    NSString *filename = [NSString stringWithFormat:@"%@/Documents/Flare/Logs/checker.log", NSHomeDirectory()];
    [self.failMsgText.textStorage.string writeToFile:filename atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return YES;
}

// disable / enable toolbar item.
- (void)switchStateToolbarItem:(NSToolbarItem *)sender enable:(BOOL)enabled {
    [sender setAction:enabled ? @selector(connectToolbar:) : nil];
}

- (BOOL)setAllAxisParams {
    BOOL flag = false;
    
    for (int axis = 1; axis <= _axisParams.count; axis++) {
        int rtn = 0;
        BOOL canMove = true;
        AxisParam   ap = GetAxisParam(axis);
        rtn = smc_set_profile_unit(_controllerID, axis,
                                   ap.startSpeed * ap.ppratio,
                                   ap.runSpeed * ap.ppratio,
                                   ap.accTime, ap.accTime,
                                   ap.stopSpeed * ap.ppratio);
        
        if (rtn) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_s_profile(_controllerID, axis, 0, 0.2))) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_home_pin_logic(_controllerID, axis, ap.homeLevel, 0))) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_homemode(_controllerID, axis, ap.homeDirect, 1, homeModes[axis-1], 0)))
        {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_home_profile_unit(_controllerID, axis, ap.startSpeed * ap.ppratio, ap.homeSpeed * ap.ppratio, ap.accTime, 0)))
        {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        flag &= canMove;
    }
    
    return flag;
}

- (IBAction)showHelp:(NSMenuItem *)sender {
    NSString *path = [NSBundle.mainBundle pathForResource:@"FlareSensorChecker (v2.0.0) user manunals" ofType:@"pdf"];
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (IBAction)showLogo:(NSButton *)sender {
    NSImageView *imageView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"MT_Name.png"]];
    [imageView setImageScaling:NSImageScaleProportionallyDown];
    [imageView setFrame:NSMakeRect(0, 0, 600, 60)];
    NSViewController *viewController = [[NSViewController alloc] init];
    viewController.view = [[NSView alloc] initWithFrame:imageView.frame];
    [viewController.view addSubview:imageView];
    
    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = viewController;
    
    if (@available(macOS 10.14, *)) {
        popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    } else {
        // Fallback on earlier versions
        popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    }
    popover.behavior = NSPopoverBehaviorTransient;
    [popover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (IBAction)shieldAxisToCalibration:(NSMenuItem *)sender {
}

- (IBAction)ioChecker:(NSToolbarItem *)sender {
    static IOCheckerWindowController *ioCheckerController = nil;
    
    if (!ioCheckerController) {
        ioCheckerController = [[IOCheckerWindowController alloc] initWithControllerState:_connected];
    } else {
        ioCheckerController.sysConnected = _connected;
    }
    
    [self.window beginSheet:ioCheckerController.window completionHandler:^(NSModalResponse returnCode) {
        
    }];
}

- (IBAction)portChecker:(NSToolbarItem *)sender {
    [self.window beginSheet:_portWindowController.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            
        }
    }];
}

- (IBAction)connectToolbar:(NSToolbarItem *)sender {
    if ([sender.label isEqualToString:@"Connect"]) {
        [self switchStateToolbarItem:sender enable:NO];
        [self appendMessage:[NSString stringWithFormat:@"Try to connect controller"] color:NSColor.darkGrayColor];
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            if ([self->_mcViewController connect]) {
                self->_controllerID = 0;
                WORD cardNum;
                DWORD cardTypeList;
                WORD cardIdList;
                smc_get_CardInfList(&cardNum, &cardTypeList, &cardIdList);
                nmcs_clear_card_errcode(self->_controllerID);   // clear card error
                nmcs_clear_errcode(self->_controllerID,0);      // clear bus error
                nmcs_set_alarm_clear(self->_controllerID,2,0);
                
                for (int axis = 1; axis <= self->_axisParams.count; axis++) {
                    nmcs_clear_axis_errcode(self->_controllerID, axis);
                }
                
                int rtn = 0;
                WORD inmode = 3;
                
                for (int axis = 1; axis < 13 ; axis++) {
                    if (0 != (rtn = smc_write_sevon_pin(self->_controllerID, axis, 0))) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showExecuteErrorMessage:rtn];
                        });
                    }
                    usleep(50000);
                    
                    if (0 != (rtn = smc_set_counter_inmode(self->_controllerID, axis, inmode))) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showExecuteErrorMessage:rtn];
                        });
                    }
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_cbAxis selectItemAtIndex:0];
                    [self selectAxis:self->_cbAxis];
                    
                    [self switchStateToolbarItem:sender enable:YES];
                    sender.label = @"Disconnect";
                    [sender setImage:[NSImage imageNamed:@"disconnect.png"]];
                    
                    [self appendMessage:@"Success to connect controller." color:NSColor.darkGrayColor];
                });
                
                [self setAllAxisParams];
                smc_write_outbit(self->_controllerID, 26, 0);
                sleep(1);
                self->_connected = YES;
                [self->_portWindowController setConnectState:self->_connected];
            } else {
                self->_controllerID = 3;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showExecuteErrorMessage:self->_controllerID];
                    NSAlert *alert = [NSAlert new];
                    alert.informativeText = @"Connect fail";
                    alert.messageText = @"Error";
                    [alert runModal];
                    [self switchStateToolbarItem:sender enable:YES];
                });
            }
        });
    } else {
        [self switchStateToolbarItem:sender enable:NO];
        [self appendMessage:[NSString stringWithFormat:@"Try to disconnect controller"] color:NSColor.darkGrayColor];
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [self->_mcViewController disconnect];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                sender.label = @"Connect";
                [sender setImage:[NSImage imageNamed:@"connect.png"]];
                [self appendMessage:@"Success to disconnect controller." color:NSColor.darkGrayColor];
                [self switchStateToolbarItem:sender enable:YES];
            });
            smc_write_outbit(self->_controllerID, 26, 1);
            self->_connected = NO;
            [self->_portWindowController setConnectState:self->_connected];
        });
    }
}

- (IBAction)selectAxis:(NSComboBox *)sender {
    NSString *axisString = sender.objectValueOfSelectedItem;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    
    if (regex) {
        NSTextCheckingResult *tcr = [regex firstMatchInString:axisString options:NSMatchingReportCompletion range:NSMakeRange(0, axisString.length)];
        if (tcr) {
            int axis = [[axisString substringWithRange:tcr.range] intValue];
            _selectedAxis = axis;
            [self appendMessage:[NSString stringWithFormat:@"Select axis %d", _selectedAxis] color:NSColor.darkGrayColor];
        }
    }
}

- (IBAction)showAxisHelp:(NSButton *)sender {
    NSImageView *imageView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"axisid.jpg"]];
    [imageView setFrame:NSMakeRect(0, 0, 415, 280)];
    NSViewController *viewController = [[NSViewController alloc] init];
    viewController.view = [[NSView alloc] initWithFrame:imageView.frame];
    [viewController.view addSubview:imageView];
    
    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = viewController;
    
    if (@available(macOS 10.14, *)) {
        popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    } else {
        // Fallback on earlier versions
        popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    }
    popover.behavior = NSPopoverBehaviorTransient;
    [popover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxX];
}

- (IBAction)move:(NSButton *)sender {
    int rtn = 0;
    int direction = 1;
    BOOL canMove = YES;
    
    if ([sender.title isEqualToString:@"Move+"]) {
        direction = 1;
    } else {
        direction = 0;
    }
    
    if (_connected) {
        _cbAxis.enabled = NO;
        for (int axis = 1; axis <= _axisParams.count; axis++) {
            smc_stop(_controllerID, axis, 0);
        }
        
        NSString *msg = [NSString stringWithFormat:@"Move axis %d to %@ limit", _selectedAxis, direction ? @"positive" : @"negative"];
        [self appendMessage:msg color:NSColor.darkGrayColor];
        
        AxisParam ap = GetAxisParam(_selectedAxis);
        rtn = smc_set_profile_unit(_controllerID, _selectedAxis,
                                   ap.startSpeed*ap.ppratio,
                                   ap.runSpeed*ap.ppratio,
                                   ap.accTime, ap.accTime,
                                   ap.stopSpeed*ap.ppratio);
        
        if (rtn) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_s_profile(_controllerID, _selectedAxis, 0, 0.2))) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        rtn |= smc_set_profile_unit(_controllerID, _selectedAxis, ap.startSpeed*ap.ppratio, ap.runSpeed*ap.ppratio, ap.accTime, ap.accTime, ap.stopSpeed*ap.ppratio);
        if(rtn!=0) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        __weak NSButton *button = sender;
        if (canMove) {
            if (0 != (rtn = smc_vmove(_controllerID, _selectedAxis, direction))) {
                [self showExecuteErrorMessage:rtn];
            } else {
                _isMoving = YES;
                sender.enabled = NO;
                if (canMove) {
                    dispatch_async(dispatch_get_global_queue(0, 0), ^{
                        while(smc_check_done(self->_controllerID, self->_selectedAxis)==0) { usleep(10000); } //等待运动停止
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self->_cbAxis.enabled = YES;
                            button.enabled = YES;
                            self->_isMoving = NO;
                            [self appendMessage:[NSString stringWithFormat:@"Success to move axis %d using vmove", self->_selectedAxis] color:NSColor.darkGrayColor];
                        });
                    });
                }
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                button.enabled = YES;
                self->_isMoving = NO;
            });
            [self appendMessage:[NSString stringWithFormat:@"Can't move axis %d because of some error happened", _selectedAxis] color:NSColor.redColor];
        }
    }
}

- (IBAction)moveToOrigin:(NSButton *)sender {
    if (_connected) {
        _cbAxis.enabled = NO;
        for (int axis = 1; axis <= _axisParams.count; axis++) {
            smc_stop(_controllerID, axis, 0);
        }
        
        [self appendMessage:[NSString stringWithFormat:@"Move axis %d to origin", _selectedAxis] color:NSColor.darkGrayColor];
        
        __block int rtn = 0;
        BOOL canMove = true;
        AxisParam ap = GetAxisParam(_selectedAxis);

        rtn = smc_set_profile_unit(_controllerID,
                                   _selectedAxis,
                                   ap.startSpeed*ap.ppratio, ap.runSpeed*ap.ppratio,
                                   ap.accTime, ap.accTime,
                                   ap.stopSpeed*ap.ppratio);
        
        if (rtn) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_s_profile(_controllerID, _selectedAxis, 0, 0.2))) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_home_pin_logic(_controllerID, _selectedAxis, ap.homeLevel, 0))) {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_homemode(_controllerID, _selectedAxis, ap.homeDirect, 1, homeModes[_selectedAxis-1], 0)))
        {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (0 != (rtn = smc_set_home_profile_unit(_controllerID, _selectedAxis, ap.startSpeed*ap.ppratio, ap.homeSpeed*ap.ppratio, ap.accTime, 0)))
        {
            canMove = NO;
            [self showExecuteErrorMessage:rtn];
        }
        
        if (canMove) {
            sender.enabled = NO;
            _isMoving = YES;
            
            __weak NSButton *button = sender;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (CheckAxisIOState(self->_selectedAxis)!=2 && 0 != (rtn = smc_vmove(self->_controllerID, self->_selectedAxis, 0))) {
                    smc_stop(self->_controllerID, self->_selectedAxis, 0);
                    [self showExecuteErrorMessage:rtn];
                    self->_isMoving = NO;
                    
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        self->_cbAxis.enabled = YES;
                        button.enabled = YES;
                        [self appendMessage:[NSString stringWithFormat:@"Fail to move axis %d to origin", self->_selectedAxis] color:NSColor.darkGrayColor];
                    });
                } else {
                    while (0 == smc_check_done(self->_controllerID, self->_selectedAxis)) { usleep(200000); }
                    
                    if (0 != (rtn = smc_home_move(self->_controllerID, self->_selectedAxis))) {
                        smc_stop(self->_controllerID, self->_selectedAxis, 0);
                        [self showExecuteErrorMessage:rtn];
                        self->_isMoving = NO;
                        
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            self->_cbAxis.enabled = YES;
                            button.enabled = YES;
                            [self appendMessage:[NSString stringWithFormat:@"Fail to move axis %d to origin", self->_selectedAxis] color:NSColor.darkGrayColor];
                        });
                    } else {
                        WORD state;
                        do {
                            smc_get_home_result(self->_controllerID, self->_selectedAxis, &state);
                            usleep(100000);
                        } while (!state);
                        
                        self->_isMoving = NO;
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            self->_cbAxis.enabled = YES;
                            button.enabled = YES;
                            [self appendMessage:[NSString stringWithFormat:@"Success to move axis %d to origin", self->_selectedAxis] color:NSColor.darkGrayColor];
                        });
                        
                        int axes[] = {self->_selectedAxis};
                        MoveAxisDistance(self->_selectedAxis, homeOffset[self->_selectedAxis-1], false, false);
                        usleep(1000*100);
                        CheckAxisState(axes, 1, false);
                    }
                }
            });
        } else {
            self->_cbAxis.enabled = YES;
            sender.enabled = YES;
            [self appendMessage:[NSString stringWithFormat:@"Can't move axis %d because of some error happened", _selectedAxis] color:NSColor.redColor];
        }
    }
}

- (IBAction)stopAxis:(NSButton *)sender {
    if (_connected) {
        int rtn = 0;
        if (0 == (rtn = smc_stop(_controllerID, _selectedAxis, 0))) {
            [self appendMessage:[NSString stringWithFormat:@"Stop axis %d", _selectedAxis] color:NSColor.darkGrayColor];
        } else {
            [self showExecuteErrorMessage:rtn];
        }
    }
}

- (IBAction)calibrateAllAxis:(NSButton *)sender {
    if (_connected) {
        _cbAxis.enabled = NO;
        if ([sender.title isEqualToString:@"Run Calibration"]) {
            _isStopCalibrated = NO;
            [self appendMessage:@"Start calibration" color:NSColor.darkGrayColor];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                self->_isMoving = true;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendMessage:@"Open auto-door" color:NSColor.darkGrayColor];
                });
                
                for (int axis = 1; axis <= self->_axisParams.count; axis++) {
                    smc_stop(self->_controllerID, axis, 0);
                }
                // open door
                smc_write_outbit(self->_controllerID, 17, 0);
                smc_write_outbit(self->_controllerID, 18, 1);
                smc_write_outbit(self->_controllerID, 19, 0);
                smc_write_outbit(self->_controllerID, 20, 1);
                sleep(3);
                
                for (int axis = 1; axis <= self->_axisParams.count; axis++) {
                    if (![self selfSingleAxis:axis]) {
                        break;
                    }
                }
                
                self->_isMoving = NO;
            });
            sender.title = @"Stop Calibration";
        } else {
            _isStopCalibrated = YES;
            sender.title = @"Run Calibration";
        }
    }
}

- (BOOL)selfSingleAxis:(int)axis {
    BOOL flag = true;
    int rtn = 0;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self appendMessage:[NSString stringWithFormat:@"Start self-check axis %d", axis] color:NSColor.darkGrayColor];
    });
    
    do {
        int ret = rtn = smc_vmove(_controllerID, axis, 0);
        if (ret!=0 && [NSThread.callStackSymbols.description containsString:@"calibrateAllAxis"]==NO){  // move to negative limit.
            smc_stop(_controllerID, axis, 0);
            [self showExecuteErrorMessage:rtn];
            flag = NO;
            break;
        } else {
            if(ret==104|| ret==105) smc_stop(_controllerID, axis, 1);
            while (0 == smc_check_done(_controllerID, axis)) {  // wait axis stopped
                if (_isStopCalibrated) {
                    flag = NO;
                    break;
                }
                usleep(200000);
            }
            
            if (0 != (rtn = smc_home_move(_controllerID, axis))) {  // start home move
                smc_stop(_controllerID, axis, 0);
                [self showExecuteErrorMessage:rtn];
                flag = NO;
                break;
            } else {
                WORD state;
                while (0 == smc_get_home_result(_controllerID, axis, &state)) { // wait axis stopped
                    if (state) { break; }
                    if (_isStopCalibrated) {  flag = NO; break; }
                }
                
                if (0 != (rtn = smc_vmove(_controllerID, axis, 1))) {   // go to positive limit
                    smc_stop(_controllerID, axis, 0);
                    [self showExecuteErrorMessage:rtn];
                    flag = NO;
                    break;
                } else {
                    while (0 == smc_check_done(_controllerID, axis)) { // wait axis stopped
                        if (_isStopCalibrated) {
                            flag = NO;
                            break;
                        }
                        usleep(200000);
                    }
                    
                    if (axis == 1 || axis == 2 || axis == 3
                        || axis == 4 || axis == 11 || axis == 12) {
                        if (0 != (rtn = smc_pmove_unit(_controllerID, axis, 0, 1))) {
                            smc_stop(_controllerID, axis, 0);
                            [self showExecuteErrorMessage:rtn];
                            flag = NO;
                            break;
                        } else {
                            while (0 == smc_check_done(_controllerID, axis)) {
                                if (_isStopCalibrated) {
                                    flag = NO;
                                    break;
                                }
                                usleep(200000);
                            }
                        }
                    } else {
                        if (0 != (rtn = smc_vmove(_controllerID, axis, 0))) {
                            smc_stop(_controllerID, axis, 0);
                            [self showExecuteErrorMessage:rtn];
                            flag = NO;
                            break;
                        } else {
                            while (0 == smc_check_done(_controllerID, axis)) {
                                if (_isStopCalibrated) {
                                    flag = NO;
                                    break;
                                }
                                usleep(200000);
                            }
                        }
                    }
                    
                }
            }
        }
    } while (0);
    
    if (flag) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendMessage:[NSString stringWithFormat:@"Success to self-check axis %d", axis] color:NSColor.darkGrayColor];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendMessage:[NSString stringWithFormat:@"Fail to self-check axis %d", axis] color:NSColor.redColor];
        });
    }
    return flag;
}

- (void)checkSensor {
    while (1) {
        if (!_connected) {
            sleep(1);
            continue;
        }
        
        DWORD errorcode = 0;
        nmcs_get_errcode(_controllerID, 2, &errorcode);
        
        if (errorcode != 0) {
            NSString *str = [NSString stringWithFormat:@"The bus error, errorcode: 0x%lx.", errorcode];
            NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str
                                                                                  attributes:@{NSForegroundColorAttributeName : NSColor.redColor}];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.failMsgText.textStorage appendAttributedString:attributeString];
                [self.failMsgText scrollPageDown:self];
            });
        }
        
        for (int axis = 1; axis <= _axisParams.count; axis++) {
            AxisParam ap = GetAxisParam(axis);
            DWORD state = smc_axis_io_status(_controllerID, axis);
            NSMutableDictionary *rowDict = self->_tableDataSource[axis-1];
            
            int sensorActivedCnt = 0;
            int index = 0;
            state <<= 1;
            
            do {
                state = state >> 1;
                int bit = state & 0x01;
                
                switch (index) {
                    case 0:
                        rowDict[_tableColumnIdentifier[4]] = @(bit);
                        if (bit) {
                            NSString *str = [self showErrorMessage:axis];
                            NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str
                                                                                                  attributes:@{NSForegroundColorAttributeName : NSColor.redColor}];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self.failMsgText.textStorage appendAttributedString:attributeString];
                                [self.failMsgText scrollPageDown:self];
                            });
                            sensorActivedCnt += 2;
                        }
                        break;
                    case 1:
                        rowDict[_tableColumnIdentifier[3]] = @(bit);
                        sensorActivedCnt += bit;
                        if([rowDict[_tableColumnIdentifier[2]] intValue]==1
                           && [rowDict[_tableColumnIdentifier[1]] isNotEqualTo:rowDict[_tableColumnIdentifier[3]]]) {
                            rowDict[_tableColumnIdentifier[2]] = @0;
                        }
                        break;
                    case 2:
                        rowDict[_tableColumnIdentifier[1]] = @(bit);
                        sensorActivedCnt += bit;
                        if([rowDict[_tableColumnIdentifier[2]] intValue]==1
                           && [rowDict[_tableColumnIdentifier[1]] isNotEqualTo:rowDict[_tableColumnIdentifier[3]]]) {
                            rowDict[_tableColumnIdentifier[2]] = @0;
                        }
                        break;
                    case 3:
                        rowDict[_tableColumnIdentifier[5]] = @(bit);
                        break;
                    case 4: {
                        rowDict[_tableColumnIdentifier[2]] = (ap.homeLevel==bit ? @0 : @1);
                        if([rowDict[_tableColumnIdentifier[2]] intValue]==1
                           && [rowDict[_tableColumnIdentifier[1]] isNotEqualTo:rowDict[_tableColumnIdentifier[3]]]) {
                            rowDict[_tableColumnIdentifier[2]] = @0;
                        }
                    } break;
                    default:
                        break;
                }
                index++;
            } while (state);
            
            if ((axis!=4&&sensorActivedCnt >= 2) || (axis==4 && sensorActivedCnt>2)) {
                rowDict[_tableColumnIdentifier[7]] = @"FAIL";
            } else {
                rowDict[_tableColumnIdentifier[7]] = @"PASS";
            }
            
            int rtn = 0;
            double position;
            if (0 == (rtn = smc_get_encoder_unit(_controllerID, axis, &position))) {
                AxisParam ap = GetAxisParam(axis);
                double pos = position / ap.ppratio;
                rowDict[_tableColumnIdentifier[6]] = [NSString stringWithFormat:@"%.4lf", pos];;
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showExecuteErrorMessage:rtn];
                });
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
            usleep(5000);
        }
        
        if (_isMoving) {
            usleep(100000);
        } else {
            sleep(1);
        }
    }
}

- (NSString *)showErrorMessage:(int)axis {
    NSMutableString *errorMsg = [NSMutableString new];
    
    if (_controllerID != -1) {
        do {
            DWORD errorcode = 0;
            nmcs_get_node_od(_controllerID, 2, 1002+axis, 0x603F, 00, 16, &errorcode);
            [errorMsg appendFormat:@"%@ Axis %d driver alarm.(Error Code: 0x%lx) ", [self currentTimeString], axis, errorcode];
            
            nmcs_get_errcode(_controllerID, 2, &errorcode);
            
            if (errorcode != 0) {
                [errorMsg appendFormat:@"The bus error, errorcode: 0x%lx.", errorcode];
                break;
            }
            
            nmcs_get_card_errcode(_controllerID, &errorcode);
            
            if (errorcode != 0) {
                [errorMsg appendFormat:@"The bus error, errorcode: 0x%lx.", errorcode];
                break;
            }
            
        } while (0);
    }
    
    [errorMsg appendString:@"\n"];
    
    return errorMsg;
}

- (void)showExecuteErrorMessage:(int)errorCode {
    static NSDictionary *kvErrors = nil;
    NSString *errorMessage = nil;
    
    if (!kvErrors) {
        NSString *path = [NSBundle.mainBundle pathForResource:@"ErrorCode" ofType:@"plist"];
        kvErrors = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    
    if (kvErrors) {
        errorMessage =  kvErrors[[NSString stringWithFormat:@"%d", errorCode]];
        
        if (!errorMessage) {
            errorMessage = @"Unknown error";
        }
    } else {
        errorMessage = @"Unknown error";
    }
    
    NSString *str = nil;
    
    if (_selectedAxis > 0) {
        str = [NSString stringWithFormat:@"%@ Axis %d. %@\n", [self currentTimeString], _selectedAxis, errorMessage];
    } else {
        str = [NSString stringWithFormat:@"%@ %@\n", [self currentTimeString], errorMessage];
    }
    NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str attributes:@{NSForegroundColorAttributeName : NSColor.redColor}];
    dispatch_block_t block = ^(){
        [self.failMsgText.textStorage appendAttributedString:attributeString];
        [self.failMsgText scrollPageDown:self];
    };
    
    if(NSThread.currentThread.isMainThread){
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (void)appendMessage:(NSString *)message color:(NSColor *)color {
    dispatch_block_t block = ^(){
        NSString *str = [NSString stringWithFormat:@"%@ %@\n", [self currentTimeString], message];
        NSAttributedString *attributeString = [[NSAttributedString alloc] initWithString:str attributes:@{NSForegroundColorAttributeName : color}];
        [self.failMsgText.textStorage appendAttributedString:attributeString];
        [self.failMsgText scrollRangeToVisible:NSMakeRange(self.failMsgText.string.length, 0)];
    };
    if(NSThread.currentThread.isMainThread) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

#pragma - mark TableView Delegate
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _tableDataSource.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 28;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *dict = _tableDataSource[row];
    NSTableCellView *view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    [view.subviews[0] setFrame:view.bounds];
    
    if ([view.subviews[0] isKindOfClass:NSTextField.class]) {
        ((NSTextField *)view.subviews[0]).stringValue = [NSString stringWithFormat:@"%@", dict[tableColumn.identifier]];
        if ([tableColumn.identifier isEqualToString:@"fsc_status"]) {
            ((NSTextField *)view.subviews[0]).textColor = [dict[tableColumn.identifier] isEqualToString:@"FAIL"] ? NSColor.redColor : NSColor.greenColor;
        }
    } else if ([view.subviews[0] isKindOfClass:NSImageView.class]) {
        [(NSImageView *)view.subviews[0] setImageScaling:NSImageScaleProportionallyUpOrDown];
        int type = [dict[tableColumn.identifier] intValue];
        
        switch (type) {
            case 0:
                [((NSImageView *)view.subviews[0]) setImage:[NSImage imageNamed:@"grayLed.png"]];
                break;
            case 1:
                if ([tableColumn.identifier isEqualToString:@"fsc_emg"]
                    || [tableColumn.identifier isEqualToString:@"fsc_servo"]) {
                    [((NSImageView *)view.subviews[0]) setImage:[NSImage imageNamed:@"redLed.png"]];
                } else {
                    [((NSImageView *)view.subviews[0]) setImage:[NSImage imageNamed:@"greenLed.png"]];
                }
                break;
            case 2:
                [((NSImageView *)view.subviews[0]) setImage:[NSImage imageNamed:@"redLed.png"]];
                break;
            default:
                break;
        }
    }
    
    return view;
}

@end
