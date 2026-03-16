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

Janet stat2table(const jstat_t *st, const uint8_t *key);
jmode_t os_getmode(const Janet *argv, int32_t n);
