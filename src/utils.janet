(defn some? [val]
  (not (nil? val)))

(defmacro letsome [name val ifsome &opt ifnil]
  ~(let [,name ,val]
     (if (not (nil? ,name)) ,ifsome ,ifnil)))

(defn rotate [ch str sz]
  (def nxt (+ sz (string/find ch str)))
  (if (= nxt (length str))
    (string/slice str 0 sz)
    (string/slice str nxt (+ nxt sz))))


