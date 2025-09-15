#!/usr/bin/env janet

(defn main
  [& args]
  ((def proc (os/spawn ["echo" "1234567890"] :p {:out :pipe}))
   (ev/gather
     (do
       (var buf @"")
       (while (ev/read (proc :out) 1 buf) (print buf) (set buf @"")))
     (os/proc-wait proc))
   (os/proc-close proc)))
