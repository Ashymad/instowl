(defmacro bind [name & types]
  (with-syms [$fn $sig]
    ~(let [,$fn (ffi/lookup (ffi/native) ,name)
           ,$sig (ffi/signature :default ,;types)]
       (fn [& args] (ffi/call ,$fn ,$sig ;args)))))

(defmacro defbind [name & types]
  ~(def ,name (bind ,(string/join [name]) ,;types)))

(defmacro bind/str [name]
  (with-syms [$fn $sig]
    ~(let [,$fn (ffi/lookup (ffi/native) ,name)
           ,$sig (ffi/signature :default :string :ptr)]
       (fn [arg] (ffi/call ,$fn ,$sig (string/join [arg]))))))

(defmacro defbind/str [name]
  ~(def ,name (bind/str ,(string/join [name]))))

(defbind get_nprocs :int)
(defbind/str dirname)
(defbind/str basename)
(defbind/str mkdtemp)

