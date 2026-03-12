(import ./utils)

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

(def c/glob :private (bind "glob" :int :string :int :ptr :ptr))
(def c/globfree :private (bind "globfree" :void :ptr))
(def c/glob_t :private (ffi/struct :size :ptr :size))

(defn glob [pattern]
  (def globbed (ffi/write c/glob_t [0 nil 0]))
  (if (= 0 (c/glob pattern 0 nil globbed))
    (let [returned (ffi/read c/glob_t globbed)
          globlen (int/to-number (returned 0))
          paths (ffi/read @[:string globlen] (returned 1))]
      (c/globfree globbed)
      paths)))

(def c/ioctl :private (bind "ioctl" :int :int :ulong :ptr))
(def c/winsize :private (ffi/struct :short :short :short :short))
(def c/ioctl/args :private
  @{:TIOCGWINSZ [21523 c/winsize [0 0 0 0]]})

(defn ioctl [fd op]
  (utils/letsome args (c/ioctl/args op)
    (let [arg (ffi/write (args 1) (args 2))]
      (c/ioctl fd (args 0) arg)
      (ffi/read (args 1) arg))))

(defbind get_nprocs :int)
(defbind/str dirname)
(defbind/str basename)
(defbind/str mkdtemp)

