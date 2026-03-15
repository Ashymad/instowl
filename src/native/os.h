#pragma once

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64
#endif

#include <janet.h>
#include <sys/stat.h>
#include <sys/types.h>

typedef struct stat jstat_t;
typedef mode_t jmode_t;

struct OsStatGetter {
    const char *name;
    Janet(*fn)(const jstat_t *st);
};

extern const struct OsStatGetter os_stat_getters[];
