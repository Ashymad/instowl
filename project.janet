(declare-project
  :name "instow")

(declare-binscript
  :main "instow"
  :hardcode-syspath true
  :is-janet true)

(declare-native
  :name "instow/native/nftw"
  :source ["src/native/nftw.c"
           "src/native/os.c"])

(declare-source
  :prefix "instow"
  :source ["src/file.janet"
           "src/main.janet"
           "src/libc.janet"
           "src/tools.janet"
           "src/utils.janet"])

(def linkpath "src/native/nftw.so")
(def buildpath (string/join [(os/getenv "PWD") "/build/instow/native/nftw.so"]))
(def linkto (try (os/readlink linkpath) ([e f] nil)))

(if (not= linkto buildpath )
  (do
    (if (not (nil? linkto)) (os/rm linkpath))
    (os/symlink buildpath linkpath)))

(let [file (file/open "compile_flags.txt" :w)]
  (file/write file "-I" (os/getenv "HOME") "/.local/include\n")
  (file/close file))
