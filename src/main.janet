(import spork/sh)
(import ./libc)
(import ./file)

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

(defn runp [state & args]
  (def proc (os/spawn args :p {:out :pipe :err :pipe}))
  (def logfile (file/open "./instowl.log" :a))
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
  (with-syms [$ret]
    ~(let [,$ret (runp state ,cmd ,;args)]
       (if (= ,$ret 0)
         (set state ,newstate)
         (errexit (string/format "Command '%s' failed with code: %d" ,cmd ,$ret))))))

(defmacro iff [&opt condition iftrue & rest]
  (if (nil? iftrue) condition ~(if ,condition ,iftrue (iff ,;rest))))

(defn main [& args]
  (do
    (def target (string/join [(os/getenv "HOME") "/.local"]))
    (def stowdir (string/join [target "/pkg"]))
    (def pkg (libc/basename (os/getenv "PWD")))
    (def pkgdir (string/join [stowdir "/" pkg]))
    (def destdir (libc/mkdtemp "/tmp/instowl.XXXXXX"))

    (var state :init)
    (var errormsg "Unknown")
    (var prefix target)

    (sh/rm "./instowl.log")

    (while (not= state :exit)
      (case state
        :init
        (iff
          (file/file-exists? "configure") (set state :conf/configure)
          (file/file-exists? "configure.ac") (set state :conf/autotools)
          (file/file-exists? "Makefile") (set state :build/make)
          (errexit "Unable to auto-detect the build system"))

        :conf/autotools
        (checkrun :conf/configure "autoreconf" "-vi") 

        :conf/configure
        (checkrun :build/make "./configure" (string/join ["--prefix=" prefix]))

        :build/make
        (checkrun :install/pre "make" (string/format "-j%d" (libc/get_nprocs)))

        :install/pre
        (do
          (set state :install/make))

        :install/make
        (checkrun :install/post
                  "make"
                  "install"
                  (string/join ["DESTDIR=" destdir])
                  (string/join ["PREFIX=" prefix]))

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
        (checkrun :done "stow" "-vv" "-d" stowdir "-t" target pkg)

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
