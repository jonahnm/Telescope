// Thanks KpwnZ
#import <Foundation/Foundation.h>

#define AMFI_IS_CD_HASH_IN_TRUST_CACHE 6

int evaluateSignature(NSURL*, NSData **cdHashOut, BOOL *isAdhocSignedOut);