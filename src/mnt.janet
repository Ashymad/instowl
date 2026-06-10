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

      :check_indent (+ (error (* " " (% (* :location (constant "Invalid indent, try ") (backref :col))))) true)
      :check_empty (+ (error (* 1 (% (* :location (constant "Stray characters at the end"))))) true)
      :key_invalid (+ "- " "> " ": " "[" "{" "#")
      :check_key (+ (error (* (<- :key_invalid :invalid)
                              (% (* :location
                                    (constant "Keys cannot start with: '")
                                    (backref :invalid)
                                    (constant "'")))))
                    true)

      :check_nl (+ (error (* "\n" (% (* :location (constant "Keys can't contain newlines"))))) true)

      :setcol (only-tags (* (/ (column) ,dec :col) (constant false :firstcol)))
      :colprefix (lenprefix (backref :col) " ")
      :firstprefix (* (backmatch :firstcol) :colprefix (any " "))
      :resetfirst (only-tags (constant "" :firstcol))

      :indent (+ (* :firstprefix :setcol) :colprefix)

      :increase (only-tags (/ (backref :col) ,inc :col))

      :string (* :indent ">" :val)
      :strings (% (unref (* :resetfirst :string (any (+ :comment (* (constant "\n") :string))))))

      :list (* :indent "-" :val)
      :lists (group (unref (* :resetfirst :list (any (+ :comment :list)))))

      :val (* " " (<- (to (+ "\n" -1 ))) (+ -1 (some "\n")))
      :key (* :check_indent :check_key (<- (to (+ "\n" (* (any " ") ":")))) :check_nl (any " "))
      :map (group (* :indent :key ":" (+ (* -1 :nil) :val (unref (* (some "\n") :increase :all)))))
      :maps (/ (group (unref (* :resetfirst :map (any (+ :comment :map))))) ,from-pairs-check)

      :comment (* (any " ") "#" (to (+ "\n" -1)) (? "\n"))

      :nil (constant "")

      :all (* (any :comment) (+ :strings :lists :maps :nil))

      :init (only-tags (constant 0 :col))

      :main (* :init (any :comment) :maps :check_empty)
      }))

(defn parse [str] ((peg/match peg str) 0))

(defn parsefile [path] 
  (def f (file/open path :rn))
  (def p (parse (file/read f :all)))
  (file/close f)
  p)

