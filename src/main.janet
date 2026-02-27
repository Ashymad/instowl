(import spork/sh)
(import ./libc)
(import ./file)
(import ./tools)

(def spinner "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
(var ch (string/slice spinner 0 3))

(defn rotate [ch]
  (def nxt (+ 3 (string/find ch spinner)))
  (if (= nxt (length spinner))
    (string/slice spinner 0 3)
    (string/slice spinner nxt (+ nxt 3))))

(defn msg [state line logfile]
  (file/write logfile line "\n")
  (prinf "\x1b[2K{%s}⸉%s⸊→%s\r" state ch (string/slice line 0 (min 80 (length line))))
  (flush))

(defn prinfer [state logfile pipe]
  (def buf @"")
  (while (ev/read pipe 1024 buf)
    (def lines (string/split "\n" buf))
    (def len (length lines))
    (if (> len 1)
      (loop [[idx line] :pairs lines]
        (if (< idx (- len 1))
          (msg state line logfile)
          (do
            (buffer/clear buf)
            (buffer/push-string buf line)))))))

(defmacro errexit [msg]
  ~(do
     (set errormsg ,msg)
     (set state :error)))

(defn runp [state env & args]
  (def logfile (file/open "./instowl.log" :a))
  (file/write logfile (string/join ["RUN" ;args "\n"] " "))
  (def proc (os/spawn args :e (table :err :pipe :out :pipe ;env)))
  (ev/gather
    (prinfer state logfile (proc :out))
    (prinfer state logfile (proc :err))
    (os/proc-wait proc)
    (while (= (get proc :return-code) nil)
      (ev/sleep 0.2) 
      (set ch (rotate ch))
      (prinf "{%s}⸉%s⸊\r" state ch)
      (flush)))
  (def code (get proc :return-code))
  (os/proc-close proc)
  (file/close logfile)
  code)

(defmacro checkrun [newstate cmd & args]
  (with-syms [$ret $cmd]
    ~(let [,$cmd (tools/gettool ,cmd)]
       (if (nil? ,$cmd)
         (errexit (string/format "Unable to find the tool '%s'" ,cmd))
         (let [,$ret (runp state env ,$cmd ,;args)]
           (if (= ,$ret 0)
             (set state ,newstate)
             (errexit (string/format "Command '%s' failed with code: %d" ,$cmd ,$ret))))))))

(defn path/join [& args]
  (string/join [;args] "/"))

(defn main [& args]
  (do
    (def home (os/getenv "HOME"))
    (def target (path/join home ".local"))
    (def stowdir (path/join target "pkg"))
    (def pkg (libc/basename (os/getenv "PWD")))
    (def pkgdir (path/join stowdir pkg))
    (def destdir (libc/mkdtemp "/tmp/instowl.XXXXXX"))

    (def env ["PATH" (string/join [(os/getenv "PATH") (path/join target "bin")] ":")
              "PKG_CONFIG_PATH" (path/join target "lib" "pkgconfig")
              "CFLAGS" (string/join ["-idirafter" (path/join target "include")] " ")
              "PERL5LIB" (path/join target "lib" "perl5")
              "GOPATH" destdir
              "HOME" home])

    (var state :init)
    (var errormsg "Unknown")
    (var prefix target)

    (sh/rm "./instowl.log")

    (while (not= state :exit)
      (case state
        :init
        (cond
          (file/file-exists? "go.mod") (set state :build/go)
          (file/file-exists? "Cargo.toml") (set state :build/cargo)
          (file/file-exists? "configure") (set state :conf/configure)
          (file/file-exists? "configure.ac") (set state :conf/autotools)
          (file/file-exists? "Makefile") (set state :build/make)
          (errexit "Unable to auto-detect the build system"))

        :conf/autotools
        (checkrun :conf/configure :autoreconf "-vi") 

        :conf/configure
        (checkrun :build/make :configure (string/join ["--prefix=" prefix]))

        :build/make
        (checkrun :install/make :make (string/format "-j%d" (libc/get_nprocs)))

        :build/go
        (checkrun :install/go :go "build" "-v")

        :build/cargo
        (checkrun :install/cargo :cargo "build" "--locked" "--release")

        :install/make
        (checkrun :install/post
                  :make
                  "install"
                  (string/join ["DESTDIR=" destdir])
                  (string/join ["PREFIX=" prefix]))

        :install/go
        (do
          (set prefix "")
          (checkrun :install/go :go "install" "-v")
          (checkrun :install/post :go "clean" "-modcache"))

        :install/cargo
        (do
          (set prefix "")
          (checkrun :install/post :cargo "install" "--force" "--offline" "--locked" "--no-track" "--root" destdir "--path" "."))

        :install/post
        (do
          (def logfile (file/open "./instowl.log" :a))
          (def installdir (string/join [destdir prefix]))
          (if (file/dir-exists? installdir)
            (do
              (loop [file :in (sh/list-all-files installdir)]
                (def dst (string/replace installdir pkgdir file))
                (msg state (string/format "INST %s" dst) logfile)
                (file/move-file file dst))
              (file/close logfile)
              (set state :stow))
            (errexit "The destination directory doesn't contain the prefix")))

        :stow
        (checkrun :done :stow "-v" "-d" stowdir "-t" target pkg)

        :error
        (do
          (sh/rm (string/join [destdir]))
          (printf "\x1b[2K{%s}⸉!⸊→%s" state errormsg)
          (set state :exit))

        :done
        (do
          (sh/rm (string/join [destdir]))
          (printf "\x1b[2K{%s}⸉x⸊→Success" state)
          (set state :exit))))))
