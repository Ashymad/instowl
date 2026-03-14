(declare-project
  :name "instowl")

(declare-binscript
  :main "instowl"
  :is-janet true)

(declare-native
  :name "instowl/native/nftw"
  :source ["src/native/nftw.c"])

(declare-source
  :prefix "instowl"
  :source ["src/file.janet"
           "src/main.janet"
           "src/libc.janet"
           "src/tools.janet"
           "src/utils.janet"])
