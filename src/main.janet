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

(defn procout [& args]
  (def proc (os/spawn args :px {:out :pipe}))
  (def buf @"")
  (ev/gather
    (ev/read (proc :out) :all buf)
    (os/proc-wait proc))
  (os/proc-close proc)
  buf)

(defn runp [state env & args]
  (def log_file (file/open "./instow.log" :a))
  (file/write log_file (string "RUN: '" (string/join args "' '") "'\n"))
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
    (def target (path/join home ".usr" "local"))
    (def bindir (path/join target "bin"))
    (def mandir (path/join target "share" "man"))
    (def headerdir (path/join target "include"))
    (def libdir (path/join target "lib"))
    (def triplet (string/slice (procout "gcc" "-dumpmachine") 0 -2))
    (def syslibdir (path/join libdir triplet))
    (def stowdir (path/join target "stow"))
    (def pkg (libc/basename (os/getenv "PWD")))
    (def pkgdir (path/join stowdir pkg))
    (def destdir (libc/mkdtemp "/tmp/instow.XXXXXX"))

    (def env (os/environ))
    (merge-into env {:err :pipe
                     :out :pipe
                     "PATH" (string/join [(os/getenv "PATH") bindir] ":")
                     "PKG_CONFIG_PATH" (string/join
                                         [(path/join libdir "pkgconfig")
                                          (path/join syslibdir "pkgconfig")] ":")
                     "CFLAGS" (string/join
                                [(stropt "--include-directory-after" headerdir)
                                (stropt "-Wl,-rpath" libdir)
                                (stropt "-Wl,-rpath" syslibdir)
                                (string "-L" libdir)
                                (string "-L" syslibdir)] " ")
                     "CXXFLAGS" (string/join
                                  [(stropt "--include-directory-after" headerdir)
                                   (stropt "-Wl,-rpath" libdir)
                                   (stropt "-Wl,-rpath" syslibdir)
                                   (string "-L" libdir)
                                   (string "-L" syslibdir)] " ")
                     "RUSTFLAGS" (string/join
                                   ["-C" (string "link-args=-Wl,-rpath," libdir)
                                    "-C" (string "link-args=-Wl,-rpath," syslibdir)] " ")
                     "PERL5LIB" (path/join libdir "perl5")
                     "GOPATH" destdir})

    (var ret 0)
    (var state (if-let [st (get args 1)] (keyword st) :init))
    (var errormsg "Unknown")
    (var prefix target)
    (var builddir ".")

    (if (file/file-exists? "./instow.log") (os/rm "./instow.log"))

    (while (not= state :exit)
      (let [log_file (file/open "./instow.log" :a)]
        (file/write log_file (string/join ["STATE:" state "\n"] " "))
        (file/close log_file))
      (case state
        :init
        (cond
          (file/file-exists? "configure") (set state :conf/configure)
          (file/file-exists? "Makefile") (set state :build/make)
          (file/file-exists? "go.mod") (set state :build/go)
          (file/file-exists? "Cargo.toml") (set state :build/cargo)
          (or (file/file-exists? "setup.py")
              (file/file-exists? "pyproject.toml")) (set state :build/pip)
          (file/file-exists? "project.janet") (set state :build/jpm)
          (utils/some? (libc/glob "*.pro")) (set state :conf/qmake)
          (file/file-exists? "CMakeLists.txt") (set state :conf/cmake)
          (file/file-exists? "autogen.sh") (set state :conf/autogen)
          (file/file-exists? "configure.ac") (set state :conf/autoreconf)
          (file/file-exists? "meson.build") (set state :conf/meson)
          (errexit "Unable to auto-detect the build system"))

        :conf/autoreconf
        (checkrun :conf/configure :autoreconf "-vi") 

        :conf/autogen
        (checkrun :conf/configure :autogen) 

        :conf/configure
        (checkrun :build/make :configure (stropt "--prefix" prefix))

        :conf/qmake
        (do
          (set builddir "build")
          (set prefix "/usr/")
          (checkrun :build/make
                    :qmake
                    (stropt "QMAKE_CXXFLAGS" (env "CXXFLAGS"))
                    (stropt "QMAKE_CFLAGS" (env "CFLAGS"))
                    (string "QMAKE_LIBDIR+=" libdir " " syslibdir)
                    (string "QMAKE_RPATHDIR+=" libdir " " syslibdir)
                    "-o" (path/join builddir "Makefile")
                    ))

        :conf/meson
        (do
          (set builddir "build")
          (checkrun :build/meson :meson "setup" builddir (stropt "--prefix" prefix)))

        :conf/cmake
        (do
          (set builddir "build")
          (checkrun :build/make :cmake "-B" builddir "-S" "." (stropt "-DCMAKE_INSTALL_PREFIX" prefix)))

        :build/make
        (checkrun :install/make
                  :make
                  "-C" builddir
                  (string/format "-j%d" (libc/get_nprocs))
                  ;(if-let [cc (os/getenv "CC")] [(stropt "CC" cc)] [])
                  ;(if-let[cxx (os/getenv "CXX")] [(stropt "CXX" cxx)] [])
                  "--"
                  ;(if-let [m (os/getenv "MAKETARGETS")] (string/split " " m) []))

        :build/go
        (checkrun :install/go :go "build" "-v")

        :build/cargo
        (do
          (checkrun :install/cargo :cargo "rustc" "--locked" "--release")
          (if (file/file-exists? "install.yml") (set state :install/rinstall)))

        :build/pip
        (do
          (set builddir "build")
          (checkrun :install/pip :pip "wheel" "." "-w" builddir "--no-build-isolation" "--no-deps"))


        :build/meson
        (checkrun :install/meson :meson "compile" "-C" builddir)

        :build/jpm
        (checkrun :install/jpm :jpm "build")

        :install/make
        (checkrun :post/detectprefix
                  :make
                  "-C" builddir
                  "install"
                  (stropt "PREFIX" prefix)
                  (stropt "prefix" prefix)
                  (stropt "CMAKE_INSTALL_PREFIX" prefix)
                  (stropt "DESTDIR" destdir)
                  (stropt "INSTALL_ROOT" destdir))

        :install/meson
        (checkrun :move :meson "install" "-C" builddir (stropt "--destdir" destdir))

        :install/go
        (do
          (set prefix "")
          (checkrun :install/go :go "install" "-v")
          (checkrun :move :go "clean" "-modcache"))

        :install/jpm
        (checkrun :move
                  :jpm
                  (stropt "--dest-dir" destdir)
                  (stropt "--binpath" bindir)
                  (stropt "--manpath" (path/join mandir "man1"))
                  (stropt "--modpath" (path/join libdir "janet"))
                  (stropt "--libpath" libdir)
                  (stropt "--headerpath" (path/join headerdir "janet"))
                  "install")
        :install/rinstall
        (checkrun :move :rinstall "install" "-y" "--destdir" destdir "--packaging" "--prefix" prefix)

        :install/cargo
        (do
          (set prefix "")
          (checkrun :move :cargo "install" "--force" "--frozen" "--no-track" "--root" destdir "--path" "."))

        :install/pip
        (utils/letsome wheels (libc/glob (path/join builddir "*.whl"))
           (checkrun :post/detectprefix
                     :pip "install"
                     (stropt "--root" destdir)
                     (stropt "--prefix" prefix)
                     "--no-build-isolation"
                     "--no-deps"
                     "--force-reinstall"
                     ;wheels)
           (errexit "No wheels present"))

        :post/detectprefix
        (do
          (if (file/dir-exists? (path/join destdir prefix "local")) (set prefix (path/join prefix "local")))
          (set state :move))

        :move
        (let [log_file (file/open "./instow.log" :a)
              installdir (path/join destdir prefix)]
          (if (file/dir-exists? installdir)
            (do
              (if (file/dir-exists? pkgdir)
                (do
                  (checkrun :stow :stow "-v" "-d" stowdir "-t" target "-D" pkg)
                  (file/rmrf pkgdir)))
              (set state (if (nil? (libc/glob (path/join installdir "lib" "*.so.*"))) :stow :ldconfig))
              (if (not= state :error)
                (nftw/nftw installdir
                           (fn [file stat ftype info]
                             (if (or (= ftype :f) (= ftype :sl))
                               (do
                                 (def dst (path/join pkgdir (string/slice file (length installdir))))
                                 (message state (string/format "MV: %s => %s" file dst) log_file)
                                 (file/move-file file dst))) 0) 1024 :phys)))
            (errexit "The destination directory doesn't contain the prefix"))
          (file/close log_file))

        :ldconfig
        (checkrun :stow :ldconfig "-vNn" (path/join pkgdir "lib"))

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
          (set state :exit))
        
        #default
        (errexit (string "Unknown state: " state))))
ret
)
