#import "../Core/Controllers/KayokoRegionShot.h"
#include <assert.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        assert(!KayokoRegionShotOpener(@"test", NO)); // Missing plugin: preview fallback.
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        assert(library);
        assert(!KayokoRegionShotOpener(nil, NO));
        assert(!KayokoRegionShotOpener(@42, NO));
        assert(!KayokoRegionShotOpener(@" \n", NO));
        assert(!KayokoRegionShotOpener(@"image caption", YES));
        NSString *limit = [@"a" stringByPaddingToLength:24000 withString:@"a" startingAtIndex:0];
        assert(KayokoRegionShotOpener(limit, NO));
        assert(!KayokoRegionShotOpener([limit stringByAppendingString:@"a"], NO));
        NSString *text = @"  原文 👨‍👩‍👧‍👦\n";
        KayokoRegionShotOpenText openText = KayokoRegionShotOpener(text, NO);
        assert(openText);
        openText(text); // Mock asserts lossless whitespace and composed characters.
        puts("RegionShot bridge: optional lookup, input bounds and lossless delivery passed.");
    }
    return 0;
}
