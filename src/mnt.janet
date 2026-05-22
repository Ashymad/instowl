(def base_indent 2)

(defn inc_indent [x]
  (+ x base_indent))

(def mnt_peg
  (peg/compile
    ~{
      :main (* (only-tags (constant 0 :col)) :map)
      :key (+ :check_indent (<- (to ":")))
      :val (* " " (+ :check_key_start (* (<- (to (+ " \n" "\n" -1))) (+ :check_key_end true))))
      :pair (* :key ":" (+ (* :val (? "\n")) "\n"))
      :increase (only-tags (/ (backref :col) ,inc_indent :col))
      :indent (lenprefix (backref :col) " ")
      :map (any (group (unref (* :indent :pair :increase :map) :col)))
      :check_indent (error (* " " (constant "Invalid indent")))
      :check_key_start (error (* (+ " " "\n") (constant "Key starting with space")))
      :check_key_end (error (* " " (constant "Key ends with space")))
      }))
