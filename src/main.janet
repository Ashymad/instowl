(import ./libc)
(import ./file)
(import ./tools)
(import ./utils)
(import ./native/nftw)

(def columns ((libc/ioctl 1 :TIOCGWINSZ) 1))
(def tty? (= (libc/isatty 1) 1))

(def spinner "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
(var spin (string/slice spinner 0 3))

(defn rotate [spin_]
  (utils/rotate spin_ spinner 3))

(defn message [state line log_file]
  (file/write log_file line "\n")
  (if tty?
    (do
      (def pre (string/format "\x1b[2K{%s}⸉%s⸊→" state spin))
      (prinf "%s%s\r" pre (string/slice line 0 (max 0 (min (- columns (length pre)) (length line)))))
      (flush))
    (printf "{%s}→%s" state line)))

(defn prinfer [state log_file pipe]
  (def buf @"")
  (while (ev/read pipe 1024 buf)
    (def lines (string/split "\n" buf))
    (def len (length lines))
    (if (> len 1)
      (loop [[idx line] :pairs lines]
        (if (< idx (- len 1))
          (message state line log_file)
          (do
            (buffer/clear buf)
            (buffer/push-string buf line)))))))

(defmacro errexit [msg]
  ~(do
     (set errormsg ,msg)
     (set state :error)))

(defn runp [state env & args]
  (def log_file (file/open "./instowl.log" :a))
  (file/write log_file (string/join ["RUN:" ;args "\n"] " "))
  (def proc (os/spawn args :e env))
  (ev/gather
    (prinfer state log_file (proc :out))
    (prinfer state log_file (proc :err))
    (os/proc-wait proc)
    (while (and tty? (nil? (get proc :return-code)))
      (ev/sleep 0.2) 
      (set spin (rotate spin))
      (prinf "{%s}⸉%s⸊\r" state spin)
      (flush)))
  (def code (get proc :return-code))
  (os/proc-close proc)
  (file/close log_file)
  code)

(defmacro checkrun [newstate cmd & args]
  (with-syms [$ret $cmd]
    ~(utils/letsome ,$cmd (tools/gettool ,cmd)
      (let [,$ret (runp state env ,$cmd ,;args)]
        (if (= ,$ret 0)
          (set state ,newstate)
          (errexit (string/format "Command '%s' failed with code: %d" ,$cmd ,$ret))))
      (errexit (string/format "Unable to find the tool '%s'" ,cmd)))))

(defn path/join [& args]
  (string/join [;args] "/"))

(defn stropt [a b]
  (string/join [a b] "="))

(defn main [& args]
    (def home (os/getenv "HOME"))
    (def target (path/join home ".local"))
    (def stowdir (path/join target "pkg"))
    (def pkg (libc/basename (os/getenv "PWD")))
    (def pkgdir (path/join stowdir pkg))
    (def destdir (libc/mkdtemp "/tmp/instowl.XXXXXX"))

    (def env (os/environ))
    (merge-into env {:err :pipe
                     :out :pipe
                     "PATH" (string/join [(os/getenv "PATH") (path/join target "bin")] ":")
                     "PKG_CONFIG_PATH" (path/join target "lib" "pkgconfig")
                     "CFLAGS" (string/join ["-idirafter" (path/join target "include")] " ")
                     "PERL5LIB" (path/join target "lib" "perl5")
                     "GOPATH" destdir
                     "CC" (os/getenv "CC")
                     "CXX" (os/getenv "CXX")
                     "CFLAGS" (os/getenv "CFLAGS")})

    (var ret 0)
    (var state :init)
    (var errormsg "Unknown")
    (var prefix target)
    (var builddir ".")

    (if (file/file-exists? "./instowl.log") (os/rm "./instowl.log"))

    (while (not= state :exit)
      (let [log_file (file/open "./instowl.log" :a)]
        (file/write log_file (string/join ["STATE:" state "\n"] " "))
        (file/close log_file))
      (case state
        :init
        (cond
          (file/file-exists? "configure") (set state :conf/configure)
          (file/file-exists? "Makefile") (set state :build/make)
          (file/file-exists? "go.mod") (set state :build/go)
          (file/file-exists? "Cargo.toml") (set state :build/cargo)
          (file/file-exists? "pyproject.toml") (set state :build/pep517)
          (file/file-exists? "setup.py") (set state :build/setuptools)
          (file/file-exists? "project.janet") (set state :build/jpm)
          (utils/some? (libc/glob "*.pro")) (set state :conf/qmake)
          (file/file-exists? "CMakeLists.txt") (set state :conf/cmake)
          (file/file-exists? "configure.ac") (set state :conf/autotools)
          (file/file-exists? "meson.build") (set state :conf/meson)
          (errexit "Unable to auto-detect the build system"))

        :conf/autotools
        (checkrun :conf/configure :autoreconf "-vi") 

        :conf/configure
        (checkrun :build/make :configure (stropt "--prefix" prefix))

        :conf/qmake
        (do
          (os/mkdir "build")
          (set builddir "build")
          (set prefix "/usr/local")
          (os/cd builddir)
          (checkrun :build/make :qmake "..")
          (os/cd ".."))

        :conf/meson
        (do
          (set builddir "build")
          (checkrun :build/ninja :meson "setup" builddir (stropt "--prefix" prefix)))

        :conf/cmake
        (do
          (set builddir "build")
          (checkrun :build/make :cmake "-B" builddir "-S" "." (stropt "-DCMAKE_INSTALL_PREFIX" prefix)))

        :build/make
        (checkrun :install/make
                  :make
                  "-C" builddir
                  ;(if (nil? (os/getenv "CC")) [] [(stropt "CC" (os/getenv "CC"))])
                  ;(if (nil? (os/getenv "CXX")) [] [(stropt "CXX" (os/getenv "CXX"))])
                  (string/format "-j%d" (libc/get_nprocs)))

        :build/go
        (checkrun :install/go :go "build" "-v")

        :build/cargo
        (checkrun :install/cargo :cargo "build" "--locked" "--release")

        :build/setuptools
        (checkrun :install/setuptools :python "setup.py" "build")

        :build/pep517
        (checkrun :install/pep517 :python "-m" "build" "--wheel" "--no-isolation")

        :build/ninja
        (checkrun :install/ninja :ninja "-C" builddir)

        :build/jpm
        (checkrun :install/jpm :jpm "build")

        :install/make
        (checkrun :move
                  :make
                  "-C" builddir
                  "install"
                  (stropt "PREFIX" prefix)
                  (stropt "CMAKE_INSTALL_PREFIX" prefix)
                  (stropt "DESTDIR" destdir)
                  (stropt "INSTALL_ROOT" destdir))

        :install/ninja
        (checkrun :move :ninja "-C" builddir "install" (stropt "DESTDIR" destdir))

        :install/go
        (do
          (set prefix "")
          (checkrun :install/go :go "install" "-v")
          (checkrun :move :go "clean" "-modcache"))

        :install/jpm
        (checkrun :move
                  :jpm
                  (stropt "--dest-dir" destdir)
                  (stropt "--binpath" (path/join prefix "bin"))
                  (stropt "--manpath" (path/join prefix "man"))
                  (stropt "--modpath" (path/join prefix "lib" "janet"))
                  (stropt "--libpath" (path/join prefix "lib"))
                  "install")

        :install/cargo
        (do
          (set prefix "")
          (def crates (let [c (libc/glob "crates/*")] (if (nil? c) ["."] c)))
          (each crate crates
            (checkrun :move :cargo "install" "--force" "--offline" "--locked" "--no-track" "--root" destdir "--path" crate)))

        :install/pep517
        (utils/letsome wheels (libc/glob "dist/*.whl")
           (checkrun :post/python :python "-m" "installer" (stropt "--destdir" destdir) (stropt "--prefix" prefix) ;wheels)
           (errexit "No wheels present"))

        :install/setuptools
        (checkrun :post/python :python "setup.py" "install" (stropt "--root" destdir) (stropt "--prefix" prefix))


        :post/python
        (do
          (if (file/dir-exists? (path/join destdir prefix "local")) (set prefix (path/join target "local")))
          (set state :move))

        :move
        (let [log_file (file/open "./instowl.log" :a)
              installdir (path/join destdir prefix)]
          (if (file/dir-exists? installdir)
            (do
              (nftw/nftw installdir
                         (fn [file stat ftype info]
                           (if (= ftype :f)
                             (do
                               (def dst (path/join pkgdir (string/slice file (length installdir))))
                               (message state (string/format "MV: %s => %s" file dst) log_file)
                               (file/move-file file dst))) 0) 1024 :phys)
              (set state :stow))
            (errexit "The destination directory doesn't contain the prefix"))
          (file/close log_file))

        :stow
        (checkrun :done :stow "-v" "-d" stowdir "-t" target pkg)

        :error
        (do
          (set ret 1)
          (printf "\x1b[2K{%s}⸉!⸊→%s" state errormsg)
          (set state :cleanup))

        :done
        (do
          (printf "\x1b[2K{%s}⸉x⸊→Success" state)
          (set state :cleanup))

        :cleanup
        (do
          (file/rmrf (string/join [destdir]))
          (set state :exit))))
ret
)
