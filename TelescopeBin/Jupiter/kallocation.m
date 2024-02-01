//
//  kallocation.m
//  Telescope
//
//  Created by Jonah Butler on 1/21/24.
//

#import <Foundation/Foundation.h>
#include <unistd.h>
#include <mach/mach.h>
#include "boot_info.h"
#include "fun/krw.h"
int message_size_for_kalloc_size(int kalloc_size) {
	return ((3*kalloc_size)/4) - 0x74;
}
uint64_t getProc_thing(pid_t pid) {
    uint64_t proc = bootInfo_getUInt64(@"kernel_proc");
    while(true) {
        if(kread32(proc + 0x60) == pid) {
            return proc;
        }
        proc = kread64(proc + 0x8);
        if(!proc) {
            return -1;
        }
    }
    return 0;
}
void *kalloc_msg(uint64_t size) {
	NSLog(@"Kalloc called with size: %p",size);
	// sleep(2);
	mach_port_t port = MACH_PORT_NULL;
	kern_return_t err = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
	if (err != KERN_SUCCESS) {
	NSLog(@"unable to allocate port\n");
		exit(EXIT_FAILURE);
	}
	struct simple_msg  {
	mach_msg_header_t hdr;
	char buf[0];
	};
	
	mach_msg_size_t msg_size = message_size_for_kalloc_size(size);
	struct simple_msg* msg = malloc(msg_size);
	memset(msg, 0, msg_size);
	
	msg->hdr.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MAKE_SEND, 0);
	msg->hdr.msgh_size = msg_size;
	msg->hdr.msgh_remote_port = port;
	msg->hdr.msgh_local_port = MACH_PORT_NULL;
	msg->hdr.msgh_id = 0x41414142;
	
	err = mach_msg(&msg->hdr,
				MACH_SEND_MSG|MACH_MSG_OPTION_NONE,
				msg_size,
				0,
				MACH_PORT_NULL,
				MACH_MSG_TIMEOUT_NONE,
				MACH_PORT_NULL);
	
	if (err != KERN_SUCCESS) {
	NSLog(@"kalloc failed to send message\n");
		exit(EXIT_FAILURE);
	}
	NSLog(@"Getting current task.");
	usleep(1500);
	uint64_t proc = getProc_thing(getpid());
    uint64_t proc_ro = kread64(proc + 0x18);
    uint64_t pr_task = kread64(proc_ro + 0x8);
	// sleep(2);
	uint64_t itk_space_pac = kread64(pr_task + 0x300);
	uint64_t itk_space = itk_space_pac | 0xffffff8000000000;
	NSLog(@"itk_space: %p",itk_space);
	// sleep(2);
	uint32_t port_index = MACH_PORT_INDEX(port);
	uint32_t table_size = kread32(itk_space + 0x14);
	NSLog(@"[i] table_size: 0x%x, port_index: 0x%x\n", table_size, port_index);
	// sleep(2);
		if (port_index >= table_size) {
			NSLog(@"[-] invalid port name? 0x%x\n", port);
			// sleep(2);
		}
	uint64_t is_table = kread64_smr(itk_space + 0x20);
	NSLog(@"is_table: %p",is_table);
	// sleep(2);
	uint64_t entry = is_table + port_index * 0x18/*SIZE(ipc_entry)*/;
	NSLog(@"entry: %p",entry);
	// sleep(2);
	uint64_t object_pac = kread64(entry);
	uint64_t object = object_pac | 0xffffff8000000000;
	uint64_t port_kaddr = object;
	NSLog(@"object: %p",object);
	// sleep(2);
		// find the message buffer:
		UInt64 mqueue = kread64_ptr(port_kaddr + 0x20); // ipc_port.ip_messages
		NSLog(@"mqueue: %p",mqueue);
	// sleep(2);
		UInt64 circlequeue = kread64_ptr(mqueue + 0x0); // ipc_mqueue.imq_messages
	NSLog(@"circlequeue: %p",circlequeue);
	// sleep(2);
		UInt64 head = kread64_ptr(circlequeue + 0x0); // circle_queue_head.head
	NSLog(@"head: %p",head);
	// sleep(2);
		uint64_t message_buffer = kread64_ptr(head - 0x0); // first element of the circle queue __container_of which would be a pointer to an ipc_kmsg (hopefully) aka our kernel message buffer
		NSLog(@"message buffer: %llx\n", message_buffer);
	// sleep(2);
		// leak the message buffer:
	kwrite64(head, 0);
	UInt64 imq_msgcountoff = mqueue + sizeof(mach_port_seqno_t) + sizeof(mach_port_name_t);
	uint16_t imq_msgcount = kread16(imq_msgcountoff);
	NSLog(@"imq_msgcount: %d",imq_msgcount);
	kwrite16(imq_msgcountoff, imq_msgcount+1);
	UInt64 imq_qlimitoff = imq_msgcountoff + sizeof(uint16_t);
	uint16_t imq_qlimit = kread16(imq_qlimitoff);
	NSLog(@"imq_qlimit: %d",imq_qlimit);
	kwrite16(imq_qlimitoff,imq_qlimit+1);
	return message_buffer; // now pray this works.
}
