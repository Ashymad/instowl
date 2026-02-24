#!/usr/bin/env janet

(import jpm/shutil)

(ffi/context nil)
(ffi/defbind mkdtemp :ptr [template :ptr])
(ffi/defbind get_nprocs :int [])

(def spinner "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
(var ch (string/slice spinner 0 3))

(defn rotate
  [ch]
  (def nxt (+ 3 (string/find ch spinner)))
  (if (= nxt (length spinner)) (string/slice spinner 0 3) (string/slice spinner nxt (+ nxt 3))))

(defn file-exists? [path]
  (not (nil? (os/stat path))))

(defn prinfer [state pipe]
  (do
    (def buf @"")
    (while (ev/read pipe 1024 buf)
      (def lines (string/split "\n" buf))
      (def len (length lines))
      (if (> len 1)
        (loop [[idx line] :pairs lines]
          (if (< idx (- len 1))
            (do
              (prinf "\x1b[2K{%s}⸉%s⸊→%s\r" state ch (string/slice line 0 (min 80 (length line))))
              (flush))
            (do (buffer/clear buf) (buffer/push-string buf line))))))))

(defn runp
  [state & args]
  (def proc (os/spawn args : {:out :pipe :err :pipe}))
  (ev/gather
    (prinfer state (proc :out))
    (prinfer state (proc :err))
    (os/proc-wait proc)
    (while (= (get proc :return-code) nil) (ev/sleep 0.2) (do
                                                            (set ch (rotate ch))
                                                            (prinf "{%s}⸉%s⸊\r" state ch)
                                                            (flush))))
  (def code (get proc :return-code))
  (os/proc-close proc)
  code)

(defn main
  [& args]
  (do
    (def target (string/join [(os/getenv "HOME") "/.local"]))
    (def stowdir (string/join [target "/pkg"]))
    (def pkg (shutil/basename (os/getenv "PWD")))
    (def pkgdir (string/join [stowdir pkg]))
    (def destdir @"/tmp/instowl.XXXXXX")

    (var prefix target)
    (var state :init)

    (while (not= state :exit)
      (case state
        :init (if (file-exists? "configure.ac") (set state :conf/autotools) (set state :conf/configure))
        :conf/autotools (if (= (runp state "/usr/bin/autoreconf" "-vi") 0) (set state :conf/configure) (set state :error))
        :conf/configure (if (= (runp state "./configure" "--prefix" prefix) 0) (set state :build/make) (set state :error))
        :build/make (if (= (runp state "/usr/bin/make") 0) (set state :install/pre) (set state :error))
        :install/pre (do (shutil/create-dirs pkgdir) (mkdtemp destdir) (set state :install/make))
        :install/make (if (= (runp state "/usr/bin/make" "install" (string/format "-j%d" (get_nprocs)) (string/join ["DESTDIR=" destdir])) 0) (set state :install/post))
        :install/post (set state :done)
        :error (do (printf "\x1b[2K⸉!⸊→Error") (set state :exit))
        :done (do (printf "\x1b[2K⸉x⸊→Done") (set state :exit))))))
