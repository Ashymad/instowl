(def- base_indent 4)

(defn- inc_indent [x]
  (+ x base_indent))

(def peg
  (peg/compile
    ~{:main (* (only-tags (constant 0 :col)) :all :check_empty)
      :key (* :check_indent (<- (to (+ " :" ":"))) :check_end)
      :val (* " " :check_start (<- (to (+ " \n" "\n" -1 (* " " -1)))) :check_end)
      :increase (only-tags (/ (backref :col) ,inc_indent :col))
      :indent (lenprefix (backref :col) " ")
      :list (some (* :indent "-" :val (+ -1 (some "\n"))))
      :comment (some (* (any " ") "#" (to (+ "\n" -1)) (? "\n")))
      :all (* (any :comment) (+ :lists :maps :nil))
      :map (some (unref (group (* :indent :key ":" (+ (* -1 :nil) (* :val (+ (some "\n") -1)) (* (some "\n") :increase :all)))) :col))
      :maps (/ (group (* :map (any (+ :comment :map)))) ,from-pairs)
      :lists (group (* :list (any (+ :comment :list))))
      :check_indent (+ (error (* " " (% (* :location (constant "Invalid indent"))))) true)
      :check_start (+ (error (* (+ " " "\n" -1) (% (* :location (constant "Stray space at start"))))) true)
      :check_end (+ (error (* " " (% (* :location (constant "Stray space at end"))))) true)
      :check_empty (+ (error (* 1 (% (* :location (constant "Stray characters at the end"))))) true)
      :location (% (* (constant "at [") (line) (constant ":") (column) (constant "]: ")))
      :nil (constant :nil)
      }))

(defn parse [str] ((peg/match peg str) 0))

(defn parsefile [path] 
  (def f (file/open path :rn))
  (def p (parse (file/read f :all)))
  (file/close f)
  p)

