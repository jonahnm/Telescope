#include <sys/fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <sys/mman.h>
#include <Foundation/Foundation.h>
#include <stdio.h>
#include <ctype.h>
#include "../libkfd.h"
#include "xpc/xpc.h"
#include "xpc/xpc_connection.h"

int userspaceReboot(void);
void overwrite(void);
