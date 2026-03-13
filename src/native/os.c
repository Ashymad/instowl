typedef struct stat jstat_t;
typedef mode_t jmode_t;

static int32_t janet_perm_to_unix(mode_t m) {
    return (int32_t) m;
}

static mode_t janet_perm_from_unix(int32_t x) {
    return (mode_t) x;
}

static const uint8_t *janet_decode_mode(mode_t m) {
    const char *str = "other";
    if (S_ISREG(m)) str = "file";
    else if (S_ISDIR(m)) str = "directory";
    else if (S_ISFIFO(m)) str = "fifo";
    else if (S_ISBLK(m)) str = "block";
    else if (S_ISSOCK(m)) str = "socket";
    else if (S_ISLNK(m)) str = "link";
    else if (S_ISCHR(m)) str = "character";
    return janet_ckeyword(str);
}

static int32_t janet_decode_permissions(jmode_t mode) {
    return (int32_t)(mode & 0777);
}

static int32_t os_parse_permstring(const uint8_t *perm) {
    int32_t m = 0;
    if (perm[0] == 'r') m |= 0400;
    if (perm[1] == 'w') m |= 0200;
    if (perm[2] == 'x') m |= 0100;
    if (perm[3] == 'r') m |= 0040;
    if (perm[4] == 'w') m |= 0020;
    if (perm[5] == 'x') m |= 0010;
    if (perm[6] == 'r') m |= 0004;
    if (perm[7] == 'w') m |= 0002;
    if (perm[8] == 'x') m |= 0001;
    return m;
}

static Janet os_make_permstring(int32_t permissions) {
    uint8_t bytes[9] = {0};
    bytes[0] = (permissions & 0400) ? 'r' : '-';
    bytes[1] = (permissions & 0200) ? 'w' : '-';
    bytes[2] = (permissions & 0100) ? 'x' : '-';
    bytes[3] = (permissions & 0040) ? 'r' : '-';
    bytes[4] = (permissions & 0020) ? 'w' : '-';
    bytes[5] = (permissions & 0010) ? 'x' : '-';
    bytes[6] = (permissions & 0004) ? 'r' : '-';
    bytes[7] = (permissions & 0002) ? 'w' : '-';
    bytes[8] = (permissions & 0001) ? 'x' : '-';
    return janet_stringv(bytes, sizeof(bytes));
}

static int32_t os_get_unix_mode(const Janet *argv, int32_t n) {
    int32_t unix_mode;
    if (janet_checkint(argv[n])) {
        /* Integer mode */
        int32_t x = janet_unwrap_integer(argv[n]);
        if (x < 0 || x > 0777) {
            janet_panicf("bad slot #%d, expected integer in range [0, 8r777], got %v", n, argv[n]);
        }
        unix_mode = x;
    } else {
        /* Bytes mode */
        JanetByteView bytes = janet_getbytes(argv, n);
        if (bytes.len != 9) {
            janet_panicf("bad slot #%d: expected byte sequence of length 9, got %v", n, argv[n]);
        }
        unix_mode = os_parse_permstring(bytes.bytes);
    }
    return unix_mode;
}

static jmode_t os_getmode(const Janet *argv, int32_t n) {
    return janet_perm_from_unix(os_get_unix_mode(argv, n));
}

/* Getters */
static Janet os_stat_dev(const jstat_t *st) {
    return janet_wrap_number(st->st_dev);
}
static Janet os_stat_inode(const jstat_t *st) {
    return janet_wrap_number(st->st_ino);
}
static Janet os_stat_mode(const jstat_t *st) {
    return janet_wrap_keyword(janet_decode_mode(st->st_mode));
}
static Janet os_stat_int_permissions(const jstat_t *st) {
    return janet_wrap_integer(janet_perm_to_unix(janet_decode_permissions(st->st_mode)));
}
static Janet os_stat_permissions(const jstat_t *st) {
    return os_make_permstring(janet_perm_to_unix(janet_decode_permissions(st->st_mode)));
}
static Janet os_stat_uid(const jstat_t *st) {
    return janet_wrap_number(st->st_uid);
}
static Janet os_stat_gid(const jstat_t *st) {
    return janet_wrap_number(st->st_gid);
}
static Janet os_stat_nlink(const jstat_t *st) {
    return janet_wrap_number(st->st_nlink);
}
static Janet os_stat_rdev(const jstat_t *st) {
    return janet_wrap_number(st->st_rdev);
}
static Janet os_stat_size(const jstat_t *st) {
    return janet_wrap_number(st->st_size);
}
static Janet os_stat_accessed(const jstat_t *st) {
    return janet_wrap_number((double) st->st_atime);
}
static Janet os_stat_modified(const jstat_t *st) {
    return janet_wrap_number((double) st->st_mtime);
}
static Janet os_stat_changed(const jstat_t *st) {
    return janet_wrap_number((double) st->st_ctime);
}
static Janet os_stat_blocks(const jstat_t *st) {
    return janet_wrap_number(st->st_blocks);
}
static Janet os_stat_blocksize(const jstat_t *st) {
    return janet_wrap_number(st->st_blksize);
}

struct OsStatGetter {
    const char *name;
    Janet(*fn)(const jstat_t *st);
};

static const struct OsStatGetter os_stat_getters[] = {
    {"dev", os_stat_dev},
    {"inode", os_stat_inode},
    {"mode", os_stat_mode},
    {"int-permissions", os_stat_int_permissions},
    {"permissions", os_stat_permissions},
    {"uid", os_stat_uid},
    {"gid", os_stat_gid},
    {"nlink", os_stat_nlink},
    {"rdev", os_stat_rdev},
    {"size", os_stat_size},
    {"blocks", os_stat_blocks},
    {"blocksize", os_stat_blocksize},
    {"accessed", os_stat_accessed},
    {"modified", os_stat_modified},
    {"changed", os_stat_changed},
    {NULL, NULL}
};

static Janet os_stat_or_lstat(int do_lstat, int32_t argc, Janet *argv) {
    janet_sandbox_assert(JANET_SANDBOX_FS_READ);
    janet_arity(argc, 1, 2);
    const char *path = janet_getcstring(argv, 0);
    JanetTable *tab = NULL;
    const uint8_t *key = NULL;
    if (argc == 2) {
        if (janet_checktype(argv[1], JANET_KEYWORD)) {
            key = janet_getkeyword(argv, 1);
        } else {
            tab = janet_gettable(argv, 1);
        }
    } else {
        tab = janet_table(0);
    }

    /* Build result */
    jstat_t st;
    int res;
    if (do_lstat) {
        res = lstat(path, &st);
    } else {
        res = stat(path, &st);
    }
    if (-1 == res) {
        return janet_wrap_nil();
    }

    if (NULL == key) {
        /* Put results in table */
        for (const struct OsStatGetter *sg = os_stat_getters; sg->name != NULL; sg++) {
            janet_table_put(tab, janet_ckeywordv(sg->name), sg->fn(&st));
        }
        return janet_wrap_table(tab);
    } else {
        /* Get one result */
        for (const struct OsStatGetter *sg = os_stat_getters; sg->name != NULL; sg++) {
            if (janet_cstrcmp(key, sg->name)) continue;
            return sg->fn(&st);
        }
        janet_panicf("unexpected keyword %v", janet_wrap_keyword(key));
    }
}
