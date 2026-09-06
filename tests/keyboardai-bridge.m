#import "../Core/Controllers/KayokoKeyboardAI.h"
#include <assert.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        assert(!KayokoKeyboardAIOpener(@"test", NO)); // Missing plugin: preview fallback.
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        assert(library);
        assert(!KayokoKeyboardAIOpener(nil, NO));
        assert(!KayokoKeyboardAIOpener(@42, NO));
        assert(!KayokoKeyboardAIOpener(@" \n", NO));
        assert(!KayokoKeyboardAIOpener(@"image caption", YES));
        NSString *limit = [@"a" stringByPaddingToLength:24000 withString:@"a" startingAtIndex:0];
        assert(KayokoKeyboardAIOpener(limit, NO));
        assert(!KayokoKeyboardAIOpener([limit stringByAppendingString:@"a"], NO));
        NSString *text = @"  原文 👨‍👩‍👧‍👦\n";
        KayokoKeyboardAIOpenText openText = KayokoKeyboardAIOpener(text, NO);
        assert(openText);
        openText(text); // Mock asserts lossless whitespace and composed characters.
        puts("Keyboard AI bridge: optional lookup, input bounds and lossless delivery passed.");
    }
    return 0;
}
