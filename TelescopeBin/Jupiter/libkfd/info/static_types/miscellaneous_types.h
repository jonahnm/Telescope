/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef miscellaneous_types_h
#define miscellaneous_types_h

#define GUARD_REQUIRED (1u << 1)

/*
 * kqueue stuff
 */

#define KQ_WORKLOOP_CREATE     0x01
#define KQ_WORKLOOP_DESTROY    0x02

#define KQ_WORKLOOP_CREATE_SCHED_PRI      0x01
#define KQ_WORKLOOP_CREATE_SCHED_POL      0x02
#define KQ_WORKLOOP_CREATE_CPU_PERCENT    0x04

struct kqueue_workloop_params {
    uint32_t kqwlp_version;
    uint32_t kqwlp_flags;
    uint64_t kqwlp_id;
    uint32_t kqwlp_sched_pri;
    uint32_t kqwlp_sched_pol;
    uint32_t kqwlp_cpu_percent;
    uint32_t kqwlp_cpu_refillms;
} __attribute__((packed));

__options_decl(kq_state_t, uint16_t, {
    KQ_SLEEP         = 0x0002,
    KQ_PROCWAIT      = 0x0004,
    KQ_KEV32         = 0x0008,
    KQ_KEV64         = 0x0010,
    KQ_KEV_QOS       = 0x0020,
    KQ_WORKQ         = 0x0040,
    KQ_WORKLOOP      = 0x0080,
    KQ_PROCESSING    = 0x0100,
    KQ_DRAIN         = 0x0200,
    KQ_DYNAMIC       = 0x0800,
    KQ_R2K_ARMED     = 0x1000,
    KQ_HAS_TURNSTILE = 0x2000,
});

/*
 * proc_info stuff
 */

#define PROC_INFO_CALL_LISTPIDS             0x1
#define PROC_INFO_CALL_PIDINFO              0x2
#define PROC_INFO_CALL_PIDFDINFO            0x3
#define PROC_INFO_CALL_KERNMSGBUF           0x4
#define PROC_INFO_CALL_SETCONTROL           0x5
#define PROC_INFO_CALL_PIDFILEPORTINFO      0x6
#define PROC_INFO_CALL_TERMINATE            0x7
#define PROC_INFO_CALL_DIRTYCONTROL         0x8
#define PROC_INFO_CALL_PIDRUSAGE            0x9
#define PROC_INFO_CALL_PIDORIGINATORINFO    0xa
#define PROC_INFO_CALL_LISTCOALITIONS       0xb
#define PROC_INFO_CALL_CANUSEFGHW           0xc
#define PROC_INFO_CALL_PIDDYNKQUEUEINFO     0xd
#define PROC_INFO_CALL_UDATA_INFO           0xe
#define PROC_INFO_CALL_SET_DYLD_IMAGES      0xf
#define PROC_INFO_CALL_TERMINATE_RSR        0x10

struct vinfo_stat {
    uint32_t vst_dev;
    uint16_t vst_mode;
    uint16_t vst_nlink;
    uint64_t vst_ino;
    uint32_t vst_uid;
    uint32_t vst_gid;
    int64_t vst_atime;
    int64_t vst_atimensec;
    int64_t vst_mtime;
    int64_t vst_mtimensec;
    int64_t vst_ctime;
    int64_t vst_ctimensec;
    int64_t vst_birthtime;
    int64_t vst_birthtimensec;
    int64_t vst_size;
    int64_t vst_blocks;
    uint32_t vst_blksize;
    uint32_t vst_flags;
    uint32_t vst_gen;
    uint32_t vst_rdev;
    int64_t vst_qspare[2];
};

#define PROC_PIDFDVNODEINFO         1
#define PROC_PIDFDVNODEPATHINFO     2
#define PROC_PIDFDSOCKETINFO        3
#define PROC_PIDFDPSEMINFO          4
#define PROC_PIDFDPSHMINFO          5
#define PROC_PIDFDPIPEINFO          6
#define PROC_PIDFDKQUEUEINFO        7
#define PROC_PIDFDATALKINFO         8
#define PROC_PIDFDKQUEUE_EXTINFO    9
#define PROC_PIDFDCHANNELINFO       10

struct proc_fileinfo {
    uint32_t fi_openflags;
    uint32_t fi_status;
    int64_t fi_offset;
    uint32_t fi_type;
    uint32_t fi_guardflags;
};

struct psem_info {
    struct vinfo_stat psem_stat;
    char psem_name[1024];
};

struct psem_fdinfo {
    struct proc_fileinfo pfi;
    struct psem_info pseminfo;
};

#define PROC_PIDDYNKQUEUE_INFO       0
#define PROC_PIDDYNKQUEUE_EXTINFO    1

struct kqueue_info {
    struct vinfo_stat kq_stat;
    uint32_t kq_state;
    uint32_t rfu_1;
};

struct kqueue_dyninfo {
    struct kqueue_info kqdi_info;
    uint64_t kqdi_servicer;
    uint64_t kqdi_owner;
    uint32_t kqdi_sync_waiters;
    uint8_t kqdi_sync_waiter_qos;
    uint8_t kqdi_async_qos;
    uint16_t kqdi_request_state;
    uint8_t kqdi_events_qos;
    uint8_t kqdi_pri;
    uint8_t kqdi_pol;
    uint8_t kqdi_cpupercent;
    uint8_t _kqdi_reserved0[4];
    uint64_t _kqdi_reserved1[4];
};

/*
 * perfmon stuff
 */

#define PERFMON_SPEC_MAX_ATTR_COUNT (32)

struct perfmon_layout {
    uint16_t pl_counter_count;
    uint16_t pl_fixed_offset;
    uint16_t pl_fixed_count;
    uint16_t pl_unit_count;
    uint16_t pl_reg_count;
    uint16_t pl_attr_count;
};

typedef char perfmon_name_t[16];

struct perfmon_event {
    char pe_name[32];
    uint64_t pe_number;
    uint16_t pe_counter;
};

struct perfmon_attr {
    perfmon_name_t pa_name;
    uint64_t pa_value;
};

struct perfmon_spec {
    struct perfmon_event* ps_events;
    struct perfmon_attr* ps_attrs;
    uint16_t ps_event_count;
    uint16_t ps_attr_count;
};

enum perfmon_kind {
    perfmon_cpmu,
    perfmon_upmu,
    perfmon_kind_max,
};

struct perfmon_source {
    const char* ps_name;
    const perfmon_name_t* ps_register_names;
    const perfmon_name_t* ps_attribute_names;
    struct perfmon_layout ps_layout;
    enum perfmon_kind ps_kind;
    bool ps_supported;
};

struct perfmon_counter {
    uint64_t pc_number;
};

struct perfmon_config {
    struct perfmon_source* pc_source;
    struct perfmon_spec pc_spec;
    uint16_t pc_attr_ids[PERFMON_SPEC_MAX_ATTR_COUNT];
    struct perfmon_counter* pc_counters;
    uint64_t pc_counters_used;
    uint64_t pc_attrs_used;
    bool pc_configured:1;
};

struct perfmon_device {
    void* pmdv_copyout_buf;
    uint64_t pmdv_mutex[2];
    struct perfmon_config* pmdv_config;
    bool pmdv_allocated;
};

enum perfmon_ioctl {
    PERFMON_CTL_ADD_EVENT = _IOWR('P', 5, struct perfmon_event),
    PERFMON_CTL_SPECIFY = _IOWR('P', 10, struct perfmon_spec),
};

/*
 * pmap stuff
 */

#define AP_RWNA   (0x0ull << 6)
#define AP_RWRW   (0x1ull << 6)
#define AP_RONA   (0x2ull << 6)
#define AP_RORO   (0x3ull << 6)

#define ARM_PTE_TYPE              0x0000000000000003ull
#define ARM_PTE_TYPE_VALID        0x0000000000000003ull
#define ARM_PTE_TYPE_MASK         0x0000000000000002ull
#define ARM_TTE_TYPE_L3BLOCK      0x0000000000000002ull
#define ARM_PTE_ATTRINDX          0x000000000000001cull
#define ARM_PTE_NS                0x0000000000000020ull
#define ARM_PTE_AP                0x00000000000000c0ull
#define ARM_PTE_SH                0x0000000000000300ull
#define ARM_PTE_AF                0x0000000000000400ull
#define ARM_PTE_NG                0x0000000000000800ull
#define ARM_PTE_ZERO1             0x000f000000000000ull
#define ARM_PTE_HINT              0x0010000000000000ull
#define ARM_PTE_PNX               0x0020000000000000ull
#define ARM_PTE_NX                0x0040000000000000ull
#define ARM_PTE_ZERO2             0x0380000000000000ull
#define ARM_PTE_WIRED             0x0400000000000000ull
#define ARM_PTE_WRITEABLE         0x0800000000000000ull
#define ARM_PTE_ZERO3             0x3000000000000000ull
#define ARM_PTE_COMPRESSED_ALT    0x4000000000000000ull
#define ARM_PTE_COMPRESSED        0x8000000000000000ull

#define ARM_TTE_VALID         0x0000000000000001ull
#define ARM_TTE_TYPE_MASK     0x0000000000000002ull
#define ARM_TTE_TYPE_TABLE    0x0000000000000002ull
#define ARM_TTE_TYPE_BLOCK    0x0000000000000000ull
#define ARM_TTE_TABLE_MASK    0x0000fffffffff000ull
#define ARM_TTE_PA_MASK       0x0000fffffffff000ull

#define PMAP_TT_L0_LEVEL    0x0
#define PMAP_TT_L1_LEVEL    0x1
#define PMAP_TT_L2_LEVEL    0x2
#define PMAP_TT_L3_LEVEL    0x3

#define ARM_16K_TT_L0_SIZE          0x0000800000000000ull
#define ARM_16K_TT_L0_OFFMASK       0x00007fffffffffffull
#define ARM_16K_TT_L0_SHIFT         47
#define ARM_16K_TT_L0_INDEX_MASK    0x0000800000000000ull

#define ARM_16K_TT_L1_SIZE          0x0000001000000000ull
#define ARM_16K_TT_L1_OFFMASK       0x0000000fffffffffull
#define ARM_16K_TT_L1_SHIFT         36
#define ARM_16K_TT_L1_INDEX_MASK    0x0000007000000000ull

#define ARM_16K_TT_L2_SIZE          0x0000000002000000ull
#define ARM_16K_TT_L2_OFFMASK       0x0000000001ffffffull
#define ARM_16K_TT_L2_SHIFT         25
#define ARM_16K_TT_L2_INDEX_MASK    0x0000000ffe000000ull

#define ARM_16K_TT_L3_SIZE          0x0000000000004000ull
#define ARM_16K_TT_L3_OFFMASK       0x0000000000003fffull
#define ARM_16K_TT_L3_SHIFT         14
#define ARM_16K_TT_L3_INDEX_MASK    0x0000000001ffc000ull

#endif /* miscellaneous_types_h */
