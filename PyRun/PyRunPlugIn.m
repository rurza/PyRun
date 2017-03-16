//
//  PyRunPlugin.m
//  PyRun
//
//  Created by rurza on 15/03/2017.
//  Copyright © 2017 micropixels. All rights reserved.
//

#import "PyRunPlugIn.h"
#import "NTBTask.h"

static NSString *const kPyRunCommandName = @"command";

@interface PyRunPlugIn () <NSWindowDelegate, NSTextFieldDelegate>
@property (nonatomic) CodaPlugInsController     *plugInsController;
@property (nonatomic) id<CodaPlugInBundle>      bundle;
@property (nonatomic) NSString                  *commandDefinedByUser;
@property (nonatomic) BOOL                      windowDisplayed;
@property (nonatomic) BOOL                      canRun;

@property (nonatomic) NTBTask                   *task;
@property (nonatomic) NSMutableString           *output;

#pragma mark - GUI
@property (nonatomic) IBOutlet NSTextField      *codeTextField;
@property (nonatomic) IBOutlet NSTextView       *consoleOutputTextView;
@property (nonatomic) NSMenuItem                *runMenuItem;
@property (nonatomic) NSPanel                   *panel;
@end

@implementation PyRunPlugIn

- (id)initWithPlugInController:(CodaPlugInsController*)aController plugInBundle:(id <CodaPlugInBundle>)plugInBundle
{
    self = [super init];
    if (self) {
        self.plugInsController = aController;
        self.bundle = plugInBundle;
        [self setupPlugIn];
        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self
               selector:@selector(appWillTerminate:)
                   name:NSApplicationWillTerminateNotification
                 object:nil];
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

    if (self.canRun) {
        [self terminateTaskIfPossible:nil];
        
        NSString *launchPath = @"/bin/sh";
        NSString *command = [NSString stringWithFormat:@"cd %@; %@", [self escapedSitePath], self.commandDefinedByUser];
        NSArray *arguments = @[@"-c", command];
        
        NTBTask *task = [[NTBTask alloc] initWithLaunchPath:launchPath];
        task.arguments = arguments;
        
        void (^consoleHandler)(NSString *) = ^(NSString *output) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.output appendFormat:@"\n%@", output];
                self.consoleOutputTextView.string = self.output;
                [self.consoleOutputTextView scrollToEndOfDocument:nil];
            });
        };
        
        task.outputHandler = ^(NSString *output) {
            consoleHandler(output);
        };
        task.errorHandler = ^(NSString *output) {
            consoleHandler(output);
        };
        
        task.completionHandler = ^(NTBTask *task) {
            sender.title = @"Run";
        };
        
        [task launch];
        [self openSettings:nil];
        
        self.task = task;
        
        sender.title = @"Running";
        self.runMenuItem = sender;
    }
}

- (void)terminateTaskIfPossible:(id)sender
{
    if (self.task) {
        [self.task terminate];
        self.task = nil;
        self.runMenuItem.title = @"Run";
        self.consoleOutputTextView.string = @"";
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

#pragma mark - CodaPlugIn
- (NSString *)name
{
    return @"PyRun";
}

- (void)didLoadSiteNamed:(NSString *)name
{
    [self readJSON];
    self.canRun = YES;
}

#pragma mark - Window
- (void)windowWillClose:(NSNotification *)notification
{
    self.commandDefinedByUser = self.codeTextField.stringValue;
    self.windowDisplayed = NO;
    [self saveJSON];
}

- (void)openSettings:(id)sender
{
    if (self.windowDisplayed) {
        return;
    }
    NSArray *objects;
    [(NSBundle *)self.bundle loadNibNamed:@"PyRunSettings" owner:self topLevelObjects:&objects];
    for (id object in objects) {
        if ([object isKindOfClass:[NSPanel class]]) {
            self.panel = object;
        }
    }
    self.windowDisplayed = YES;
    self.panel.delegate = self;
    self.codeTextField.stringValue = self.commandDefinedByUser;
    self.codeTextField.placeholderString = [NSString stringWithFormat:@"You're in %@. Type your launch script here, for exmaple: \"source venv/bin/activate; python manage.py\"", [self escapedSitePath]];
    [self.codeTextField.currentEditor setSelectedRange:NSMakeRange(0, 0)];
    self.consoleOutputTextView.backgroundColor = [NSColor colorWithWhite:0 alpha:0.8];
    self.consoleOutputTextView.font = [NSFont fontWithName:@"Menlo" size:14];
    self.consoleOutputTextView.textColor = [NSColor whiteColor];
    self.consoleOutputTextView.string = self.output;
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

- (NSMutableString *)output
{
    if (!_output) {
        _output = [[NSMutableString alloc] init];
    }
    return _output;
}

#pragma mark - Notifications
- (void)appWillTerminate:(NSNotification *)note
{
    [self terminateTaskIfPossible:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
