(import ./file)

(defn toolpath [tool]
  (case tool
    :make ["make" "gmake"]
    :qmake ["qmake" "qmake6"]
    :configure ["./configure"]
    :autoreconf ["autoreconf"]
    :go ["go"]
    :cargo ["cargo"]
    :stow ["stow" "xstow"]))

(defn gettool [tool]
  (var ret nil)
  (each path (toolpath tool)
    (let [fullpath (file/which path)]
      (if (not (nil? fullpath)) 
        (do
          (set ret fullpath)
          (break)))))
  ret)

