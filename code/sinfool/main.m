#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <sys/stat.h>

// CHANGE ME to the root of this repo (as an absolute path)
#define RUN_HOME "/Users/ipad_kid/Desktop/sinfool"
// #error Once you've defined RUN_HOME, delete me

/**
 @brief Convert a Flex patch to code
 
 @param patch The Flex patch
 @param uikit Pointer to a BOOL which will indicate if UIKit needs to be linked against
 @param logos If the output should be logos (otherwise plain Obj-C)
 
 @return a UTF8 encoded string of the code
 */
NSString *codeFromFlexPatch(NSDictionary *patch, BOOL *uikit, BOOL logos) {
    NSString *ret;
    @autoreleasepool {
        NSMutableString *xm = [NSMutableString stringWithString:@"#import <UIKit/UIKit.h>\n\n"];
        
        if (!logos) {
            [xm appendString:@"#include <substrate.h>\n\n"];
        }
        
        NSString *swiftPatchStr = @"PatchedSwiftClassName";
        
        NSMutableString *constructor = [NSMutableString stringWithString:@"static __attribute__((constructor)) void _fttLocalInit() {\n"];
        NSMutableArray<NSString *> *usedClasses = [NSMutableArray array];
        NSMutableArray<NSString *> *usedMetaClasses = [NSMutableArray array];
        NSMutableArray<NSString *> *usedSwiftClasses = [NSMutableArray array];
        
        for (NSDictionary *unit in patch[@"units"]) {
            NSDictionary *objcInfo = unit[@"methodObjc"];
            NSString *className = objcInfo[@"className"];
            NSString *selectorName = objcInfo[@"selector"];
            
            NSString *logosConvention = [selectorName stringByReplacingOccurrencesOfString:@":" withString:@"$"];
            NSString *cleanClassName = [className stringByReplacingOccurrencesOfString:@"." withString:swiftPatchStr];
            
            NSString *implMainName = [NSString stringWithFormat:@"_ftt_meth_$%@$%@", cleanClassName, logosConvention];
            NSString *origImplName = [NSString stringWithFormat:@"_orig%@", implMainName];
            NSString *patchImplName = [NSString stringWithFormat:@"_patched%@", implMainName];
            
            NSString *flexDisplayName = objcInfo[@"displayName"];
            NSArray<NSString *> *displayName = [flexDisplayName componentsSeparatedByString:@")"];
            NSString *bashedMethodTypeValue = displayName.firstObject;
            NSString *returnType = [bashedMethodTypeValue substringFromIndex:2];
            
            BOOL isClassMethod = [[returnType substringToIndex:1] isEqualToString:@"+"];
            
            NSMutableString *implArgList = [NSMutableString stringWithString:@"(id self, SEL _cmd"];
            NSMutableString *justArgCall = [NSMutableString stringWithString:@"(self, _cmd"];
            NSMutableString *justArgType = [NSMutableString stringWithString:@"(id, SEL"];
            
            NSMutableString *realMethodName = [NSMutableString string];
            [realMethodName appendString:[bashedMethodTypeValue stringByReplacingOccurrencesOfString:@"(" withString:@" ("]];
            [realMethodName appendFormat:@")%@", [displayName[1] substringFromIndex:1]];
            
            for (int displayId = 1; displayId < displayName.count-1; displayId++) {
                NSArray<NSString *> *typeBreakup = [displayName[displayId] componentsSeparatedByString:@"("];
                NSString *argType = typeBreakup.lastObject;
                [implArgList appendFormat:@", %@ arg%d", argType, displayId];
                [justArgCall appendFormat:@", arg%d", displayId];
                [justArgType appendFormat:@", %@", argType];
                
                [realMethodName appendFormat:@")arg%d%@", displayId, displayName[displayId+1]];
            }
            
            [implArgList appendString:@")"];
            [justArgCall appendString:@")"];
            [justArgType appendString:@")"];
            
            BOOL callsOrig = NO;
            
            NSMutableString *implBody = [NSMutableString string];
            NSString *smartComment = unit[@"name"];
            NSString *defaultComment = [NSString stringWithFormat:@"Unit for %@", flexDisplayName];
            if (smartComment.length > 0 && ![smartComment isEqualToString:defaultComment]) {
                [implBody appendFormat:@"    // %@\n", smartComment];
            }
            
            NSArray *allOverrides = unit[@"overrides"];
            for (NSDictionary *override in allOverrides) {
                if (override.count == 0) {
                    continue;
                }
                
                NSString *origValue = override[@"value"][@"value"];
                
                if ([origValue isKindOfClass:NSString.class]) {
                    NSString *subToEight = origValue.length >= 8 ? [origValue substringToIndex:8] : NULL;
                    
                    if ([subToEight isEqualToString:@"(FLNULL)"]) {
                        origValue = @"NULL";
                    } else if ([subToEight isEqualToString:@"FLcolor:"]) {
                        NSArray *color = [[origValue substringFromIndex:8] componentsSeparatedByString:@","];
                        NSString *restrict colorBase = @"[UIColor colorWithRed:%@/255.0 green:%@/255.0 blue:%@/255.0 alpha:%@/255.0]";
                        origValue = [NSString stringWithFormat:colorBase, color[0], color[1], color[2], color[3]];
                        if (uikit) {
                            *uikit = YES;
                        }
                    } else {
                        origValue = [NSString stringWithFormat:@"@\"%@\"", origValue];
                    }
                }
                
                int argument = [override[@"argument"] intValue];
                if (argument == 0) {
                    [implBody appendFormat:@"    return %@;\n", origValue];
                    break;
                } else {
                    [implBody appendFormat:@"    arg%i = %@;\n", argument, origValue];
                }
            }
            
            NSUInteger overrideCount = allOverrides.count;
            NSDictionary *argsHolder = allOverrides.firstObject;
            if (![argsHolder isKindOfClass:NSDictionary.class]) {
                continue;
            }
            
            if (overrideCount == 0 || [argsHolder[@"argument"] intValue] > 0) {
                if ([bashedMethodTypeValue isEqualToString:@"-(void"]) {
                    if (overrideCount > 0) {
                        if (logos) {
                            [implBody appendString:@"    %orig;\n"];
                        } else {
                            callsOrig = YES;
                            [implBody appendFormat:@"    %@%@;\n", origImplName, justArgCall];
                        }
                    }
                } else {
                    if (logos) {
                        [implBody appendString:@"    return %orig;\n"];
                    } else {
                        callsOrig = YES;
                        [implBody appendFormat:@"    return %@%@;\n", origImplName, justArgCall];
                    }
                }
            }
            
            if (callsOrig) {
                [xm appendFormat:@"static %@ (*%@)%@;\n", returnType, origImplName, justArgType];
            }
            
            if (logos) {
                [xm appendFormat:@"%%hook %@\n%@ {\n%@}\n%%end\n\n", cleanClassName, realMethodName, implBody];
            } else {
                [xm appendFormat:@"static %@ %@%@ {\n%@}\n\n", returnType, patchImplName, implArgList, implBody];
            }
            
            NSString *internalClassName = [NSString stringWithFormat:@"_ftt_class_%@", cleanClassName];
            
            if (logos) {
                if ([className containsString:@"."]) {
                    if (![usedSwiftClasses containsObject:className]) {
                        [usedSwiftClasses addObject:className];
                    }
                }
            } else {
                if (![usedClasses containsObject:className]) {
                    [constructor appendFormat:@"    Class %@ = objc_getClass(\"%@\");\n", internalClassName, className];
                    [usedClasses addObject:className];
                }
                
                if (isClassMethod) {
                    NSString *metaClassName = [@"_ftt_metaClass" stringByAppendingString:internalClassName];
                    if (![usedMetaClasses containsObject:metaClassName]) {
                        [constructor appendFormat:@"    Class %@ = objc_getClass(%@);\n", metaClassName, internalClassName];
                        [usedMetaClasses addObject:metaClassName];
                    }
                    internalClassName = metaClassName;
                }
                
                [constructor appendFormat:@"    MSHookMessageEx(%@, @selector(%@), (IMP)%@, ", internalClassName, selectorName, patchImplName];
                if (callsOrig) {
                    [constructor appendFormat:@"(IMP *)%@", origImplName];
                } else {
                    [constructor appendString:@"NULL"];
                }
                [constructor appendString:@");\n"];
            }
        }
        
        if (logos) {
            if (usedSwiftClasses.count) {
                [xm appendString:@"%ctor {\n    %init("];
                NSString *lastClass = usedSwiftClasses.lastObject;
                for (NSString *className in usedSwiftClasses) {
                    NSString *comma = [className isEqualToString:lastClass] ? @");\n" : @",\n        ";
                    NSString *patchedClassName = [className stringByReplacingOccurrencesOfString:@"." withString:swiftPatchStr];
                    [xm appendFormat:@"%@ = objc_getClass(\"%@\")%@", patchedClassName, className, comma];
                }
                [xm appendString:@"\n}\n"];
            }
        } else {
            [constructor appendString:@"}\n"];
            [xm appendString:constructor];
        }
        
        ret = [NSString stringWithString:xm];
    }
    
    return ret;
}

int main() {
    CFTimeInterval topStartTime = CFAbsoluteTimeGetCurrent();
    
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *workspace = @RUN_HOME;
    NSString *appTypes = [workspace stringByAppendingPathComponent:@"Apps"];
    NSString *sandboxOrig = [workspace stringByAppendingPathComponent:@"Sandbox"];
    NSString *patchesDir = [workspace stringByAppendingPathComponent:@"patches"];
    NSStringEncoding fileEncoding = NSUTF8StringEncoding;
    [fileManager createDirectoryAtPath:appTypes withIntermediateDirectories:NO attributes:NULL error:NULL];
    [fileManager removeItemAtPath:[workspace stringByAppendingPathComponent:@"list.html"] error:NULL];
    [fileManager removeItemAtPath:sandboxOrig error:NULL];
    NSArray<NSString *> *failingBuilds = [[NSString stringWithContentsOfFile:[workspace stringByAppendingPathComponent:@"failed.txt"] encoding:fileEncoding error:NULL] componentsSeparatedByString:@"\n"];
    unsigned int cores;
    size_t len = sizeof(cores);
    sysctlbyname("hw.ncpu", &cores, &len, NULL, 0);
    
    for (int sands = 0; sands < cores; sands++) {
        NSString *expandSand = [NSString stringWithFormat:@"%@%d", sandboxOrig, sands];
        [fileManager removeItemAtPath:expandSand error:NULL];
        [fileManager createDirectoryAtPath:expandSand withIntermediateDirectories:NO attributes:NULL error:NULL];
    }
    
    NSArray *sinPatches = [fileManager contentsOfDirectoryAtPath:patchesDir error:NULL];
    for (NSString *patchID in sinPatches) {
        NSString *fullPatchPath = [patchesDir stringByAppendingPathComponent:patchID];
        NSDictionary *patch = [NSDictionary dictionaryWithContentsOfFile:fullPatchPath];
        if (!patch) {
            continue;
        }
        
        BOOL uikit = NO;
        float version = 0.1;
        
        // Tweak.*m handling
        NSString *mm = codeFromFlexPatch(patch, &uikit, NO);
        NSString *xm = codeFromFlexPatch(patch, NULL, YES);
        
        // Creating sandbox
        NSString *name = patch[@"title"];
        NSString *validChars = @"QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklZxcvbnm1234567890";
        NSCharacterSet *charsOnlyStrip = [NSCharacterSet characterSetWithCharactersInString:validChars];
        NSMutableString *mutTitle = NSMutableString.new;
        for (NSUInteger charIndex = 0; charIndex < name.length; charIndex++) {
            unichar someChar = [name characterAtIndex:charIndex];
            if ([charsOnlyStrip characterIsMember:someChar]) {
                [mutTitle appendFormat:@"%c", someChar];
            }
        }
        NSString *title = [NSString stringWithString:mutTitle];
        NSString *sandbox = [sandboxOrig stringByAppendingPathComponent:title];
        while ([fileManager fileExistsAtPath:sandbox]) {
            sandbox = [sandbox stringByAppendingString:@"c"];
            version += 0.1;
        }
        [fileManager createDirectoryAtPath:sandbox withIntermediateDirectories:YES attributes:NULL error:NULL];
        
        // Makefile handling
        NSMutableString *makefile = NSMutableString.new;
        [makefile appendFormat:@""
         "ARCHS = armv7 arm64\n"
         "TARGET = iphone:clang:9.3:8.0\n"
         "DEBUG = 0\n\n"
         "include $(THEOS)/makefiles/common.mk\n\n"
         "TWEAK_NAME = %@\n"
         "%@_FILES = Tweak.mm\n", title, title];
        if (uikit) {
            [makefile appendFormat:@"%@_FRAMEWORKS = UIKit\n", title];
        }
        [makefile appendString:@"\ninclude $(THEOS_MAKE_PATH)/tweak.mk\n"];
        [makefile writeToFile:[sandbox stringByAppendingPathComponent:@"Makefile"] atomically:NO encoding:fileEncoding error:NULL];
        
        // plist handling
        NSString *executable = patch[@"applicationIdentifier"];
        if ([executable isEqualToString:@"com.flex.systemwide"]) executable = @"com.apple.UIKit";
        NSDictionary *plist = @{@"Filter": @{@"Bundles": @[executable]}};
        NSString *plistPath = [NSString stringWithFormat:@"%@/%@.plist", sandbox, title];
        [plist writeToFile:plistPath atomically:NO];
        
        // Control file handling
        NSString *cloudIden = patch[@"cloudID"];
        NSString *description = [patch[@"description"] stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n.\n"];
        description = [description stringByReplacingOccurrencesOfString:@"\n" withString:@"\n "];
        NSArray *controlDesc = [description componentsSeparatedByString:@"\n "];
        NSString *stringVersion = [[NSString stringWithFormat:@"0.%f", version] substringToIndex:5];
        title = title.lowercaseString;
        NSString *control = [NSString stringWithFormat:@""
                             "Package: com.sinfool.%@\n"
                             "Name: %@\n"
                             "Author: Sinfool\n"
                             "Description: %@\n %@\n .\n patchID: %@\n"
                             "Depends: mobilesubstrate\n"
                             "Maintainer: ipad_kid <ipadkid358@gmail.com>\n"
                             "Architecture: iphoneos-arm\n"
                             "Section: Tweaks\n"
                             "Version: %@\n"
                             "Icon: file:///private/var/mobile/Library/Sinfool/%@\n"
                             "Homepage: https://ipadkid.cf/sinfool/index.html\n",
                             title, name, controlDesc[0], description, cloudIden, stringVersion, executable];
        [control writeToFile:[sandbox stringByAppendingPathComponent:@"control"] atomically:NO encoding:fileEncoding error:NULL];
        [mm writeToFile:[sandbox stringByAppendingPathComponent:@"Tweak.mm"] atomically:NO encoding:fileEncoding error:NULL];
        [xm writeToFile:[sandbox stringByAppendingPathComponent:@"Tweak.xm"] atomically:NO encoding:fileEncoding error:NULL];
        
        NSString *postInst = @"#!/bin/bash\n\n/usr/bin/sinfoolicons\nexit 0\n";
        NSString *postinstPath = [sandbox stringByAppendingPathComponent:@"postinst"];
        [postInst writeToFile:postinstPath atomically:NO encoding:fileEncoding error:NULL];
        chmod(postinstPath.UTF8String, 0775);
        [fileManager copyItemAtPath:fullPatchPath toPath:[sandbox stringByAppendingPathComponent:@"Flex.plist"] error:NULL];
        
        NSString *fileOut = [appTypes stringByAppendingPathComponent:executable];
        NSString *webDescription = [patch[@"description"] stringByReplacingOccurrencesOfString:@"\n" withString:@"</br>"];
        NSString *webRoot = @"/sinfool";
        NSString *localSandbox = sandbox.lastPathComponent;
        NSString *buildStatus = [failingBuilds containsObject:localSandbox] ? @"<em>Status: Build failing</em>" : [NSString stringWithFormat:@"(<a href=\"cydia://url/https://cydia.saurik.com/api/share#?source=https://ipadkid.cf%@/&package=com.sinfool.%@\">Open in Cydia</a>)    (<a href=\"%@/debs/com.sinfool.%@_%@-1_iphoneos-arm.deb\">Deb download</a>)", webRoot, title, webRoot, title, stringVersion];
        NSString *stringOut = [NSString stringWithFormat:@"<p id=\"%@\"><strong>%@</strong>\t(<a href=\"http://getflex.co/patch/id/%@\">Open in Flex 3</a>)\t%@\t(<a href=\"%@/Sandbox/%@/\">View project</a>)</br>Identifier: com.sinfool.%@</br>Version: %@</br>PatchID: %@</br>Description: %@</p>", cloudIden, name, cloudIden, buildStatus, webRoot, localSandbox, title, stringVersion, cloudIden, webDescription];
        
        FILE *writeOutHTML = fopen(fileOut.UTF8String, "a");
        fprintf(writeOutHTML, "%s", stringOut.UTF8String);
        fclose(writeOutHTML);
    }
    
    NSArray *generated = [fileManager contentsOfDirectoryAtPath:appTypes error:NULL];
    const char *listName = RUN_HOME "/list.html";
    NSUInteger totalPatchCount = sinPatches.count;
    NSString *humanDate = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterNoStyle];
    FILE *htmlFile = fopen(listName, "w");
    fprintf(htmlFile, "<!DOCTYPE HTML><html><head><title>Sinfool Repo Patches</title><meta charset=\"utf-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" /><!--[if lte IE 8]><script src=\"/sinfool/assets/js/ie/html5shiv.js\"></script><![endif]--><link rel=\"stylesheet\" href=\"/sinfool/assets/css/main.css\" /><!--[if lte IE 8]><link rel=\"stylesheet\" href=\"/sinfool/assets/css/ie8.css\" /><![endif]--></head><body><article class=\"container box style3\"><header><p>This is a list of all %lu patches by Sinfool. This website is autogenerated. Last fetch was on %s</p></header>", totalPatchCount, humanDate.UTF8String);
    fclose(htmlFile);
    for (NSString *eachApp in generated) {
        NSString *initFile = [appTypes stringByAppendingPathComponent:eachApp];
        NSString *links = [NSString stringWithContentsOfFile:initFile encoding:fileEncoding error:NULL];
        FILE *writeOut = fopen(listName, "a");
        const char *bundleChar = eachApp.UTF8String;
        fprintf(writeOut, "<section id=\"%s\"><header><h2>%s</h2></header>%s</section>", bundleChar, bundleChar, links.UTF8String);
        fclose(writeOut);
    }
    
    FILE *htmlFileClose = fopen(listName, "a");
    fprintf(htmlFileClose, "</article><script src=\"/sinfool/assets/js/jquery.min.js\"></script><script src=\"/sinfool/assets/js/jquery.scrolly.min.js\"></script><script src=\"/sinfool/assets/js/jquery.poptrox.min.js\"></script><script src=\"/sinfool/assets/js/skel.min.js\"></script><script src=\"/sinfool/assets/js/util.js\"></script><!--[if lte IE 8]><script src=\"/sinfool/assets/js/ie/respond.min.js\"></script><![endif]--><script src=\"/sinfool/assets/js/main.js\"></script></body></html>");
    fclose(htmlFileClose);
    
    [fileManager removeItemAtPath:appTypes error:NULL];
    
    NSArray *theosProjs = [fileManager contentsOfDirectoryAtPath:sandboxOrig error:NULL];
    int organize = 0;
    for (NSString *theosProj in theosProjs) {
        NSString *projDir = [sandboxOrig stringByAppendingPathComponent:theosProj];
        NSString *destFolder = [NSString stringWithFormat:@"%@%d/%@", sandboxOrig, organize%cores, theosProj];
        organize++;
        [fileManager copyItemAtPath:projDir toPath:destFolder error:NULL];
    }
    
    CFTimeInterval botStartTime = CFAbsoluteTimeGetCurrent();
    printf("Finished generating %lu projects in %f seconds\n", totalPatchCount, botStartTime-topStartTime);
    
    return 0;
}
