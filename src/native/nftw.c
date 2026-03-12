#include <ftw.h>
#include <janet.h>

static JanetFunction *janet_callback = NULL;

int callback(const char *path, const struct stat *st, int flag,
             struct FTW *info) {
  return janet_unwrap_integer(janet_call(
      janet_callback, 2,
      (const Janet[]){janet_wrap_string(path), janet_wrap_integer(flag)}));
}

static Janet c_nftw(int32_t argc, Janet *argv) {
  janet_fixarity(argc, 2);
  janet_callback = janet_unwrap_function(argv[2]);
  return janet_wrap_integer(nftw((const char *)janet_unwrap_string(argv[1]),
                                 callback, 1024, FTW_DEPTH));
}

static JanetReg cfuns[] = {
    {"nftw", c_nftw, "(nftw path callback)\n\nruns nftw"}, {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "nftw", cfuns); }
