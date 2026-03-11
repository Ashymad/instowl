(import ./file)

(defn toolpath [tool]
  (case tool
    :make ["make" "gmake"]
    :qmake ["qmake" "qmake6"]
    :configure ["./configure"]
    :autoreconf ["autoreconf"]
    :go ["go"]
    :python ["python" "python3"]
    :cargo ["cargo"]
    :stow ["stow" "xstow"]))

(defn gettool [tool]
  (var ret nil)
  (each path (array/concat @[(os/getenv (string/ascii-upper tool))] (toolpath tool))
    (if (not (nil? path))
      (let [fullpath (file/which path)]
        (if (not (nil? fullpath)) 
          (do
            (set ret fullpath)
            (break))))))
  ret)

