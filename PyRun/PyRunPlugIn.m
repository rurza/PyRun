//
//  PyRunPlugin.m
//  PyRun
//
//  Created by rurza on 15/03/2017.
//  Copyright © 2017 micropixels. All rights reserved.
//

#import "PyRunPlugIn.h"

@interface PyRunPlugIn ()
@property (nonatomic) CodaPlugInsController     *plugInsController;
@property (nonatomic) id<CodaPlugInBundle>      bundle;
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
    [self.plugInsController registerActionWithTitle:@"PyRun" target:self selector:@selector(test:)];
}

- (void)test:(id)sender
{
    NSLog(@"test! sender= %@", sender);
}

- (NSString *)name
{
    return @"PyRun";
}

@end
