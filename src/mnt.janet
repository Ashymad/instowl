(defn- from-pairs-check [ps]
  (def ret @{})
  (each [k v] ps
    (if (has-key? ret k)
      (error (string/format "Duplicate key: '%s'" k))
      (put ret k v)))
  ret)

(def peg
  (peg/compile
    ~{:location (% (* (constant "at [") (line) (constant ":") (/ (column) ,dec) (constant "]: ")))

      :invalid_key_start (+ "- " "> " ": " "[" "{" "#")

      :check_indent (+ (error (* " " (% (* :location
                                           (constant "Invalid indentation, try ")
                                           (backref :indent)
                                           (constant " spaces"))))) true)
      :check_eof (+ (error (* 1 (% (* :location
                                      (constant "Stray characters at the end of file"))))) true)
      :check_key_start (+ (error (* (<- :invalid_key_start :key_start)
                                    (% (* :location
                                          (constant "Keys cannot start with: '")
                                          (backref :key_start)
                                          (constant "'"))))) true)
      :check_key_end (+ (error (* "\n" (% (* :location
                                             (constant "Keys can't contain newlines"))))) true)

      :indent_init (only-tags (constant 0 :indent))
      :indent_save (only-tags (* (/ (column) ,dec :indent) (constant false :indent_new)))
      :indent_saved (lenprefix (backref :indent) " ")
      :indent_if_new (* (backmatch :indent_new) :indent_saved)
      :indent_set_new (only-tags (constant "" :indent_new))
      :indent_inc (only-tags (/ (backref :indent) ,inc :indent))
      :indent (+ (* :indent_if_new (any " ") :indent_save) :indent_saved)

      :value (* " " (<- (to (+ "\n" -1 ))) (+ -1 (some "\n")))
      :key (* :check_indent :check_key_start (<- (to (+ "\n" (* (any " ") ":")))) :check_key_end (any " "))
      :map (group (* :indent :key ":" (+ (* -1 :empty) :value (unref (* (some "\n") :indent_inc :any)))))
      :maps (/ (group (unref (* :indent_set_new :map (any (+ :comment :map))))) ,from-pairs-check)

      :string (* :indent ">" :value)
      :strings (% (unref (* :indent_set_new :string (any (+ :comment (* (constant "\n") :string))))))

      :list (* :indent "-" :value)
      :lists (group (unref (* :indent_set_new :list (any (+ :comment :list)))))

      :comment (* (any " ") "#" (to (+ "\n" -1)) (? "\n"))
      :comments (any :comment) 

      :empty (constant "")

      :any (* :comments (+ :strings :lists :maps :empty))

      :main (* :indent_init :comments :maps :check_eof)
      }))

(defn parse [str]
  (if-let [matched (peg/match peg str)]
    (matched 0)
    (error "Unable to parse the string as minimal nested text")))

(defn parsefile [path] 
  (def f (file/open path :rn))
  (def p (parse (file/read f :all)))
  (file/close f)
  p)

(defn- print_mnt [buf indent &opt key sep value]
  (buffer/push-string buf (string
                 (string/repeat " " indent)
                 (if (nil? key) "" key)
                 (if (nil? sep) ":" sep)
                 ;(if (nil? value) [] [" " value])
                 "\n")))

(defn unparse [dict &opt opt_dif opt_cur]
  (if (not (dictionary? dict))
    (error "The first argument to unparse must be a table"))

  (def cur (if (nil? opt_cur) 0 opt_cur))
  (def dif (if (nil? opt_dif) 2 opt_dif))
  (def nxt (+ cur dif))
  (def buf @"")
  (loop [[key val] :pairs dict]
    (if (not (string? key))
      (error "The keys in the table can only be strings"))
    (cond
      (dictionary? val)
      (do
        (print_mnt buf cur key)
        (buffer/push-string buf (unparse val dif nxt)))
      (array? val)
      (do
        (print_mnt buf cur key)
        (each el val
          (print_mnt buf nxt nil "-" el)))
      (string? val)
      (if (nil? (string/find "\n" val))
        (print_mnt buf cur key ":" val)
        (do
          (print_mnt buf cur key)
          (each el (string/split "\n" val)
            (print_mnt buf nxt nil ">" el))))
      (error "The table can only contain strings, arrays and tables")))
  (buffer/popn buf 1))
