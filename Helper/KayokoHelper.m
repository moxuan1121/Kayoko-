//
//  KayokoHelper.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoHelperConfiguration.h"
#import "KayokoHelperRuntime.h"

__attribute((constructor)) static void initialize() {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }

    KayokoHelperConfiguration *configuration = [KayokoHelperConfiguration currentConfiguration];
    if (!configuration.isEnabled) {
        return;
    }

    [[KayokoHelperRuntime sharedRuntime] installSpringBoardRuntimeWithConfiguration:configuration];
}
