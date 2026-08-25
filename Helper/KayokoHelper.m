//
//  KayokoHelper.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoHelperConfiguration.h"
#import "KayokoHelperProcessContext.h"
#import "KayokoHelperRuntime.h"

__attribute((constructor)) static void initialize() {
    KayokoHelperConfiguration *configuration = [KayokoHelperConfiguration currentConfiguration];
    if (!configuration.isEnabled) {
        return;
    }

    KayokoHelperProcessContext *context = [KayokoHelperProcessContext currentContext];
    switch (context.kind) {
    case KayokoHelperProcessKindKeyboardExtension:
        return;
    case KayokoHelperProcessKindSpringBoard:
        [[KayokoHelperRuntime sharedRuntime] installSpringBoardRuntimeWithConfiguration:configuration];
        return;
    case KayokoHelperProcessKindApplication:
        [[KayokoHelperRuntime sharedRuntime] installApplicationRuntimeWithConfiguration:configuration];
        return;
    case KayokoHelperProcessKindUnsupported:
        return;
    }
}
