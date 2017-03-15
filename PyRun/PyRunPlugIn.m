//
//  PyRunPlugin.m
//  PyRun
//
//  Created by rurza on 15/03/2017.
//  Copyright © 2017 micropixels. All rights reserved.
//

#import "PyRunPlugIn.h"

static NSString *const kPyRunCommandName = @"command";

@interface PyRunPlugIn () <NSWindowDelegate>
@property (nonatomic, strong) CodaPlugInsController     *plugInsController;
@property (nonatomic, strong) id<CodaPlugInBundle>      bundle;
@property (nonatomic, strong) NSTask                    *task;
@property (nonatomic, strong) NSMenuItem                *runMenuItem;
@property (nonatomic, strong) NSPanel                   *panel;
@property (nonatomic, strong) NSString                  *commandDefinedByUser;
@property (nonatomic, strong) IBOutlet NSTextField      *codeTextField;

@end

@implementation PyRunPlugIn

- (id)initWithPlugInController:(CodaPlugInsController*)aController plugInBundle:(id <CodaPlugInBundle>)plugInBundle
{
    self = [super init];
    if (self) {
        self.plugInsController = aController;
        self.bundle = plugInBundle;
        [self setupPlugIn];
    }
    
    return self;
}

- (void)setupPlugIn
{
    [self.plugInsController registerActionWithTitle:@"Run" underSubmenuWithTitle:nil target:self selector:@selector(runCode:) representedObject:nil keyEquivalent:@"@~tr" pluginName:[self name]];
    [self.plugInsController registerActionWithTitle:@"Stop" underSubmenuWithTitle:nil target:self selector:@selector(terminateTaskIfPossible:) representedObject:nil keyEquivalent:@"@." pluginName:[self name]];
    [self.plugInsController registerActionWithTitle:@"Preferences..." target:self selector:@selector(openSettings:)];
}


- (void)runCode:(NSMenuItem *)sender
{
    if (!self.commandDefinedByUser) {
        [self readJSON];
        if (!self.commandDefinedByUser) {
            [self openSettings:nil];
            return;
        }
    }
    [self terminateTaskIfPossible:nil];
    
    NSString *launchPath = @"/bin/sh";
    NSString *command = [NSString stringWithFormat:@"cd %@; %@", [self escapedSitePath], self.commandDefinedByUser];
    NSArray *arguments = @[@"-c", command];
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments;
    [task launch];
    self.task = task;

    sender.title = @"Running";
    self.runMenuItem = sender;
    [self openWebsiteIfPossible];
}

- (void)terminateTaskIfPossible:(id)sender
{
    if (self.task) {
        [self.task terminate];
        self.task = nil;
        self.runMenuItem.title = @"Run";
    }
}

- (void)openWebsiteIfPossible
{
    NSURL *url = [NSURL URLWithString:[self.plugInsController siteLocalURL]];
    if (url) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self.task isRunning]) {
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
        });
    }
}


- (NSString *)name
{
    return @"PyRun";
}

#pragma mark - Window
- (void)windowWillClose:(NSNotification *)notification
{
    self.commandDefinedByUser = self.codeTextField.stringValue;
    [self saveJSON];
}

- (void)openSettings:(id)sender
{
    NSArray *objects;
    [(NSBundle *)self.bundle loadNibNamed:@"PyRunSettings" owner:self topLevelObjects:&objects];
    for (id object in objects) {
        if ([object isKindOfClass:[NSPanel class]]) {
            self.panel = object;
        }
    }
    self.panel.delegate = self;
    self.codeTextField.stringValue = self.commandDefinedByUser?: @"";
    self.codeTextField.placeholderString = [NSString stringWithFormat:@"You're in %@. Type your launch script here, for exmaple: \"source venv/bin/activate; python manage.py\"", [self escapedSitePath]];
    
}
#pragma mark - JSON
- (void)readJSON
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *configurationFilePath = [self configurationFilePath:NO];
    if ([fileManager fileExistsAtPath:configurationFilePath]) {
        NSData *fileData = [NSData dataWithContentsOfFile:configurationFilePath];
        NSError *error;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:fileData options:0 error:&error];
        if (error || !dict || ![dict objectForKey:kPyRunCommandName]) {
            NSLog(@"Can't read json");
            [fileManager removeItemAtPath:configurationFilePath error:&error];
        } else {
            self.commandDefinedByUser = [dict objectForKey:kPyRunCommandName];
        }
    }
}
- (void)saveJSON
{
    NSString *configurationFilePath = [self configurationFilePath:NO];
    NSDictionary *dict = @{kPyRunCommandName:self.commandDefinedByUser?:@""};
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:0
                                                         error:&error];
    
    if (!jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {    
        BOOL success = [jsonData writeToFile:configurationFilePath options:NSDataWritingAtomic error:&error];
        NSLog(@"💾 = %i %@", success, error?: @"");
    }
}

- (NSString *)escapedSitePath
{
    NSString *currentSitePath = [[self.plugInsController siteLocalPath] stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
    return currentSitePath;
}

- (NSString *)configurationFilePath:(BOOL)escaped
{
    return [NSString stringWithFormat:@"%@/%@.json", escaped ? [self escapedSitePath]:[self.plugInsController siteLocalPath], [self name]];
}

@end
