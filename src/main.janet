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

(defn runp [state & args]
  (def proc (os/spawn args : {:out :pipe :err :pipe}))
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

(defmacro checkrun [newstate & args]
  ~(if (= (runp state ,;args) 0)
     (set state ,newstate)
     (set state :error)))

(defmacro iff [&opt condition iftrue & rest]
  (if (nil? iftrue) condition ~(if ,condition ,iftrue (iff ,;rest))))

(defn main [& args]
  (do
    (def target (string/join [(os/getenv "HOME") "/.local"]))
    (def stowdir (string/join [target "/pkg"]))
    (def pkg (libc/basename (os/getenv "PWD")))
    (def pkgdir (string/join [stowdir "/" pkg]))
    (def destdir (libc/mkdtemp "/tmp/instowl.XXXXXX"))
    (sh/rm "./instowl.log")

    (var prefix target)
    (var state :init)

    (while (not= state :exit)
      (case state
        :init
        (iff
          (file/file-exists? "configure") (set state :conf/configure)
          (file/file-exists? "configure.ac") (set state :conf/autotools)
          (file/file-exists? "Makefile") (set state :build/make)
          (set state :error))

        :conf/autotools
        (checkrun :conf/configure "/usr/bin/autoreconf" "-vi") 

        :conf/configure
        (checkrun :build/make "./configure" (string/join ["--prefix=" prefix]))

        :build/make
        (checkrun :install/pre "/usr/bin/make" (string/format "-j%d" (libc/get_nprocs)))

        :install/pre
        (do
          (set state :install/make))

        :install/make
        (checkrun :install/post
                  "/usr/bin/make"
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
            (set state :error)))

        :stow
        (checkrun :done "/usr/bin/stow" "-vv" "-d" stowdir "-t" target pkg)

        :error
        (do
          (sh/rm (string/join [destdir]))
          (printf "\x1b[2K⸉!⸊→Error")
          (set state :exit))

        :done
        (do
          (sh/rm (string/join [destdir]))
          (printf "\x1b[2K⸉x⸊→Done")
          (set state :exit))))))
