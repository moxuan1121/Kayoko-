#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*KayokoRegionShotOpenText)(NSString *text);
typedef void (*KayokoRegionShotOpenImage)(id image, id scene);

static inline KayokoRegionShotOpenText KayokoRegionShotOpener(id text, BOOL isImage) {
    if (isImage || ![text isKindOfClass:NSString.class] || [text length] > 24000 ||
        ![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]) return NULL;
    // Resolve on use: optional plugin, no direct linking or forced dylib loading.
    return (KayokoRegionShotOpenText)dlsym(RTLD_DEFAULT, "RSKAOpenTokens");
}

static inline KayokoRegionShotOpenImage KayokoRegionShotImageOpener(id image) {
    return image ? (KayokoRegionShotOpenImage)dlsym(RTLD_DEFAULT, "RSShowFloatingImage") : NULL;
}
