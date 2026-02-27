(import ./file)

(defn toolpath [tool]
  (case tool
    :make ["make" "gmake"]
    :configure ["./configure"]
    :autoreconf ["autoreconf"]
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

