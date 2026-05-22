(def base_indent 2)

(defn inc_indent [x]
  (+ x base_indent))

(def mnt_peg
  (peg/compile
    ~{:main (* (only-tags (constant 0 :col)) :all :check_empty)
      :key (* :check_indent (<- (to (+ " :" ":"))) :check_end)
      :val (* " " :check_start (<- (to (+ " \n" "\n" -1 (* " " -1)))) :check_end)
      :increase (only-tags (/ (backref :col) ,inc_indent :col))
      :indent (lenprefix (backref :col) " ")
      :list (some (* :indent "-" :val (+ -1 (some "\n"))))
      :comment (some (* "#" (to (+ "\n" -1)) (? "\n")))
      :all (any (+ :comment :list :map))
      :map (some (unref (group (* :indent :key ":" (group (+ -1 (* :val (+ (some "\n") -1)) (* (some "\n") :increase :all))))) :col))
      :check_indent (+ (error (* " " (constant "Invalid indent"))) true)
      :check_start (+ (error (* (+ " " "\n" -1) (constant "Stray space at start"))) true)
      :check_end (+ (error (* " " (constant "Stray space at end"))) true)
      :check_empty (+ (error (* 1 (constant "Stray characters at the end"))) true)
      }))

