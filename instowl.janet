#!/usr/bin/env janet

(def spinner "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

(defn rotate
  [ch]
  (def nxt (+ 3 (string/find ch spinner)))
  (if (= nxt (length spinner)) (string/slice spinner 0 3) (string/slice spinner nxt (+ nxt 3))))

(defn runp
  [& args]
  (def proc (os/spawn args : {:out :pipe}))
  (var ch (string/slice spinner 0 3))
  (ev/gather
    (do
      (def buf @"")
      (while (ev/read (proc :out) 1024 buf)
        (def lines (string/split "\n" buf))
        (def len (length lines))
        (if (> len 1) 
          (loop [[idx line] :pairs lines]
            (if (< idx (- len 1))
              (do
                (prinf "\x1b[2K\r⸉%s⸊→%s" ch line)
                (flush))
              (do (buffer/clear buf) (buffer/push-string buf line)))))))
    (os/proc-wait proc)
    (while (= (get proc :return-code) nil) (ev/sleep 0.1) (set ch (rotate ch))))
  (def code (get proc :return-code))
  (os/proc-close proc)
  code)

(defn main
  [& args]
  (if (= (runp "./configure")  0)
    (printf "\x1b[2K\r⸉x⸊→Done")
    (printf "\x1b[2K\r⸉!⸊→Error")))


