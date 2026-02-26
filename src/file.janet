(import ./libc)

(defn file-exists? [path]
  (= (os/stat path :mode) :file))

(defn dir-exists? [path]
  (= (os/stat path :mode) :directory))

(defn mkdirp [path]
  (if (not (dir-exists? path)) (do (mkdirp (libc/dirname path)) (os/mkdir path))))

(defn move-file [src dst]
  (mkdirp (libc/dirname dst))
  (os/rename src dst))
