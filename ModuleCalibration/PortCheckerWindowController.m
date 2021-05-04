//
//  PortCheckerViewController.m
//  FlareSensorChecker
//
//  Created by Jackie Wang on 2020/6/29.
//  Copyright © 2020 Jackie Wang. All rights reserved.
//

#import "PortCheckerWindowController.h"
#import<JKFoundation/JKFoundation.h>

@interface PortCheckerWindowController () <NSWindowDelegate, JKSerialPortMonitorDelegate>
{
    NSDictionary *_portnames;
    BOOL _isConnected;
}
@end

@implementation PortCheckerWindowController

- (instancetype)init {
    if (self = [super init]) {
        [NSBundle.mainBundle loadNibNamed:@"PortCheckerWindowController" owner:self topLevelObjects:nil];
        
        NSString *path = [NSBundle.mainBundle pathForResource:@"PortProfile" ofType:@"plist"];
        _portnames = [NSDictionary dictionaryWithContentsOfFile:path];
        [JKSerialPort addMonitor:self];
    }
    
    return self;
}

- (IBAction)exitChecker:(NSButton *)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (void)windowWillClose:(NSNotification *)notification {
    
}

- (void)setConnectState:(BOOL)connected {
    _isConnected = connected;
}

- (void)checkPortname {
    if (_portnames) {
        NSMutableDictionary *kvImages = [NSMutableDictionary new];
        NSArray *portnames = [self enumPortNamesAtComputer];
        
        NSArray *keys = [_portnames.allKeys sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            int num1 = [[(NSString *)obj1 substringToIndex:1] intValue];
            int num2 = [[(NSString *)obj2 substringToIndex:1] intValue];
            
            return num1 > num2;
        }];
        
        for (NSString *name in keys) {
            if ([portnames containsObject:_portnames[name]]) {
                [kvImages setObject:[NSImage imageNamed:@"gou.png"] forKey:name];
            } else {
                if ([name containsString:@"luxmeter"]) {
                    [kvImages setObject:_isConnected ? [NSImage imageNamed:@"cha.png"] : [NSImage imageNamed:@"tan.png"] forKey:name];
                } else {
                    [kvImages setObject:[NSImage imageNamed:@"cha.png"] forKey:name];
                }
            }
        }
        
        NSArray *views = self.window.contentView.subviews;
        
        for (NSView *v  in views) {
            v.hidden = v.tag>keys.count;
            if(v.hidden==NO) {
                if ([v isKindOfClass:NSTextField.class]) {
                    if ([v.identifier isEqualToString:@"key"]) {
                        [(NSTextField*)v setStringValue:keys[v.tag - 1]];
                    } else if ([v.identifier isEqualToString:@"value"]) {
                        [(NSTextField*)v setStringValue:[NSString stringWithFormat:@"/dev/%@", _portnames[keys[v.tag - 1]]]];
                    }
                } else if ([v isKindOfClass:NSImageView.class]) {
                    [(NSImageView*)v setImage:kvImages[keys[v.tag - 1]]];
                }
            }
        }
    }
}

- (NSArray *)enumPortNamesAtComputer {
    NSArray *array = [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/dev" error:nil];
    return [array filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self BEGINSWITH 'cu.usb'"]];
}

- (void)port:(NSString *)portName connected:(BOOL)connected {
    [self checkPortname];
}

@end
