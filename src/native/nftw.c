#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <janet.h>
#include <stdbool.h>
#include <unistd.h>

#include "os.h"

static JanetFunction *janet_callback = NULL;

static const char *FTW_(int flag) {
  switch (flag) {
  case FTW_F:
    return "f";
  case FTW_D:
    return "d";
  case FTW_DNR:
    return "dnr";
  case FTW_DP:
    return "dp";
  case FTW_NS:
    return "ns";
  case FTW_SL:
    return "sl";
  case FTW_SLN:
    return "sln";
  default:
    return "err";
  }
}

int callback(const char *path, const struct stat *st, int flag,
             struct FTW *info) {

  JanetTable *ftwtab = janet_table(0);
  janet_table_put(ftwtab, janet_ckeywordv("base"),
                  janet_wrap_integer(info->base));
  janet_table_put(ftwtab, janet_ckeywordv("level"),
                  janet_wrap_integer(info->level));

  return janet_unwrap_integer(janet_call(
      janet_callback, 4,
      (const Janet[]){janet_cstringv(path), stat2table(st, NULL),
                      janet_ckeywordv(FTW_(flag)), janet_wrap_table(ftwtab)}));
}

struct {
  const char *name;
  int value;
} flagnames[] = {
    {"chdir", FTW_CHDIR},
    {"depth", FTW_DEPTH},
    {"mount", FTW_MOUNT},
    {"phys", FTW_PHYS},
};

static Janet c_nftw(int32_t argc, Janet *argv) {
  janet_arity(argc, 3, 7);

  int flags = 0;

  for (int i = 3; i < argc; i++) {
    for (int j = 0; j < sizeof(flagnames) / sizeof(flagnames[0]); j++) {
      if (strcmp((const char *)janet_unwrap_keyword(argv[i]),
                 flagnames[j].name) == 0) {
        flags |= flagnames[j].value;
        break;
      }
    }
  }

  janet_callback = janet_unwrap_function(argv[1]);

  return janet_wrap_integer(nftw((const char *)janet_unwrap_string(argv[0]),
                                 callback, janet_unwrap_integer(argv[2]),
                                 flags));
}

static Janet c_fileno(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 1);
  return janet_wrap_integer(
      fileno(((JanetFile *)janet_unwrap_abstract(argv[0]))->file));
}

static Janet c_fstat(int32_t argc, Janet *argv) {
  janet_arity(argc, 1, 2);

  struct stat st;
  if (fstat(janet_unwrap_integer(argv[0]), &st) == -1)
    return janet_wrap_nil();

  const uint8_t *key =
      argc == 2 ? (const uint8_t *)janet_unwrap_string(argv[1]) : NULL;

  return stat2table(&st, key);
}

static int O_(char name) {
  switch (name) {
  case '+':
    return O_APPEND;
  case 'c':
    return O_CREAT;
  case 'x':
    return O_EXCL;
  case '-':
    return O_TRUNC;
  default:
    return 0;
  }
}

static int parseO(const unsigned char *opts) {
  int flags = 0;
  bool read = false;
  bool write = false;
  for (int i = 0; opts[i]; i++) {
    if (opts[i] == 'w')
      write = true;
    else if (opts[i] == 'r')
      read = true;
    else
      flags |= O_(opts[i]);
  }

  if (read && write)
    flags |= O_RDWR;
  else if (write)
    flags |= O_WRONLY;
  else if (read)
    flags |= O_RDONLY;

  return flags;
}

static Janet c_open(int argc, Janet *argv) {
  janet_arity(argc, 1, 3);

  int flags = argc > 1 ? parseO(janet_unwrap_string(argv[1])) : 0;
  jmode_t mode = argc > 2 ? os_getmode(argv, 2) : 644;

  return janet_wrap_integer(
      open((const char *)janet_unwrap_string(argv[0]), flags, mode));
}

static Janet c_close(int argc, Janet *argv) {
  janet_fixarity(argc, 1);

  return janet_wrap_integer(close(janet_unwrap_integer(argv[0])));
}

static Janet c_strerror(int argc, Janet *argv) {
  janet_fixarity(argc, 0);

  return janet_cstringv(strerror(errno));
}

static JanetReg cfuns[] = {
    {"nftw", c_nftw, "(nftw path callback fd_limit & flags)\n\nruns nftw"},
    {"fileno", c_fileno, "(fileno file)\n\nreturns fd"},
    {"fstat", c_fstat, "(fstat fd &opt key)\n\nreturns stats from fd"},
    {"open", c_open, "(open path &opt flags mode)\n\nreturns fd"},
    {"close", c_close, "(close fd)\n\ncloses fd"},
    {"strerror", c_strerror, "(strerror)\n\nprint errno error string"},
    {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "nftw", cfuns); }
