#!/usr/bin/env janet

(defn rotate
  [ch]
  (if (= ch "-") "\\" (if (= ch "\\") "|" (if (= ch "|") "/" "-"))))

(defn main
  [& args]
  ((def proc (os/spawn ["./configure"] : {:out :pipe}))
   (ev/gather
     (do
       (def buf @"")
       (var ch "-")
       (while (ev/read (proc :out) 1024 buf)
         (def lines (string/split "\n" buf))
         (def len (length lines))
         (if (> len 1) 
           (loop [[idx line] :pairs lines]
             (if (< idx (- len 1))
                 (do
                   (prinf "\x1b[2K\r[%s] %s" ch line)
                   (set ch (rotate ch))
                   (flush))
                 (buffer/blit buf line))))))
     (os/proc-wait proc))
   (os/proc-close proc)))


