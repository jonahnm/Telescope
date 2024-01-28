//
//  logging.c
//  TSUI
//
//  Created by knives on 1/20/24.
//

#include <stdio.h>
#include <Foundation/Foundation.h>
const char * GlobalLogging = "[*] starting jb\n";
void AppendLog(NSString *format, ...) 
{
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@",msg);
    GlobalLogging = [@(GlobalLogging) stringByAppendingString:[NSString stringWithFormat:@"%@\n", msg]].UTF8String;
}
