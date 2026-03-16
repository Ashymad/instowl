(import ./libc)
(import ./native/nftw)

(defn file-exists? [path]
  (= (os/stat path :mode) :file))

(defn dir-exists? [path]
  (= (os/stat path :mode) :directory))

(defn mkdirp [path]
  (if (not (dir-exists? path)) (do (mkdirp (libc/dirname path)) (os/mkdir path))))

(defn copy-file [src dst]
  (def src_fd (libc/ctry (nftw/open src :r)))
  (if (file-exists? dst) (os/rm dst))
  (def dst_fd (libc/ctry (nftw/open dst :wxc (nftw/fstat src_fd :int-permissions))))
  (libc/sendfile dst_fd src_fd)
  (nftw/close src_fd)
  (nftw/close dst_fd))

(defn move-file [src dst]
  (mkdirp (libc/dirname dst))
  (try (os/rename src dst)
    ([a b] (copy-file src dst))))

(defn rmrf [path]
  (nftw/nftw path (fn [file stat ftype info]
                    (if (= ftype :dp)
                      (os/rmdir file)
                      (os/rm file))
                    0) 1024 :depth :phys))

(defn which [exec]
  (var ret nil)
  (if (or (string/has-prefix? "/" exec) (string/has-prefix? "./" exec))
    (if (file-exists? exec) (set ret exec))
    (each dir (string/split ":" (os/getenv "PATH"))
      (let [path (string/join [dir "/" exec])]
        (if (file-exists? path)
          (do
            (set ret path)
            (break))))))
    ret)

