#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*KayokoKeyboardAIOpenText)(NSString *text);

static inline KayokoKeyboardAIOpenText KayokoKeyboardAIOpener(id text, BOOL isImage) {
    if (isImage || ![text isKindOfClass:NSString.class] || [text length] > 24000 ||
        ![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]) return NULL;
    // Resolve on use: optional plugin, no direct linking or forced dylib loading.
    return (KayokoKeyboardAIOpenText)dlsym(RTLD_DEFAULT, "KAOpenCopiedText");
}
