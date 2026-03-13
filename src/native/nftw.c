#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64

#include <ftw.h>
#include <janet.h>

#include "os.c"

static JanetFunction *janet_callback = NULL;

static const char *flagname(int flag) {
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
  JanetTable *stattab = janet_table(0);

  if (st) {
    for (const struct OsStatGetter *sg = os_stat_getters; sg->name != NULL;
         sg++) {
      janet_table_put(stattab, janet_ckeywordv(sg->name), sg->fn(st));
    }
  }

  JanetTable *ftwtab = janet_table(0);
  janet_table_put(ftwtab, janet_ckeywordv("base"),
                  janet_wrap_integer(info->base));
  janet_table_put(ftwtab, janet_ckeywordv("level"),
                  janet_wrap_integer(info->level));

  return janet_unwrap_integer(janet_call(
      janet_callback, 4,
      (const Janet[]){janet_cstringv(path),
                      st ? janet_wrap_table(stattab) : janet_wrap_nil(),
                      janet_ckeywordv(flagname(flag)),
                      janet_wrap_table(ftwtab)}));
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

static JanetReg cfuns[] = {
    {"nftw", c_nftw, "(nftw path callback fd_limit & flags)\n\nruns nftw"},
    {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "nftw", cfuns); }
