This document drafts a high level design of what the language _should_ look
like. This document serves as my scratchpad for what features I want to
implement and experiment with. It is an ongoing process and nothing is
finalized. I've tried to format it similar to
[Learn X in Y minutes](https://learnxinyminutes.com) where X=Miru!

---

Miru is a strictly evaluated functional language that borrows much of its syntax
from languages like Clojure, Carp et al. while implementing the semantics of
languages like OCaml and Haskell with great premise on Algebraic Effects and
Effect tracking. It's designed to be pragmatic and useful for day to day general
purpose tasks while also being a great fit for doing math and science.

It is strongly and statically typed, but instead of using manually written type
annotations, it infers types of expressions using the Hindley-Milner algorithm.

```clojure
;; This is a standalone comment.

;; Variables and functions are both defined using the let keyword.
(let name "Miru") ; Inline comments use a single ";"

;;; This is a documentation comment for the greet function that takes an
;;; argument name inferred as string.
(let greet [name]
  (println (String/concat "Hello, " name)))

;; You can specify the types explicitly if you want.
;; The type unit is special because Miru doesn't have an equivalent of nil as
;; a primitive.
;; Additionally, like most functional languages Miru lacks procedures. Every
;; function must return something even if it's an unit.
(let greet [name : string] : unit
  (println (String/concat "Hello, " name)))

;; You can also separate the type definition into a (: ...) expression.
;; The type signature are written in curried form.
;; Type signatures use infix forms which is how you would define them
;; in mathematics.
(: greet string -> unit)
(let greet [name]
  (open String/Implicits) ; Brings handy modular implicits into scope!
  ;; Modular implicit allow locally-resolved typeclass-like features.
  (println "I've been greeting a lot today, isn't it {}?" name))

;; Recursive functions need to be marked with a "rec" specifier.
;; Specifiers are special positional properties attached to labels.
(let (rec factorial) [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

;; Every function must have at least one argument.
;; Some functions naturally don't take any arguments, so there's "unit" type for
;; it that has only one value written as "()".
(let greet-morning [()]
  (println "Good morning!"))

;; Unlike most Lisps, you must specify "()" when calling a function just for its
;; side-effect.
(greet-morning ())
;; This makes the next expression syntactically valid, but sementically illegal.
(greet-morning)

;; Functions are automatically curried.
(let make-inc [x y] (+ x y)) ; int -> int -> int
(let inc-2 (make-inc 2)) ; int -> int
(inc-2 3) ; 5

;; You can use (block ...) to group multiples expressions in a single block.
(let print-and-return [x]
  (block
    (println (int-to-string x))
    x))

;; You can use let to create scoped expressions too.
;; let uses sequential binding, similar to let* in Scheme.
(let [x 10
      y (+ x 10)]
       (+ x y)) ; 30

;; You can utilize (and ...) for parallel bindings.
;; Seperating "block", "let" and "and" keeps composition cleaner.
(block
  (let a 1)
  (and
    (let b (+ a 1)) ; b sees a, but not c.
    (let c (+ a 2))) ; c sees a, but not b.
  (let d (+ b c)) ; Sequential again! d sees both b and c.
  (+ a b c d)) ; Return the final expression!

;; This is especially useful to implement mutually recursive functions so the
;; compiler can track value bounds. No need for pre-defined symbol!
(and
  (let (rec is-even?) [n]
    (match n
      (0 true)
      (n (is-odd? (- n 1)))))
  (let (rec is-odd?) [n]
    (match n
      (0 false)
      (n (is-even? (- n 1))))))

;; Since functions are first-class you can always use lambdas.
(let square (fn [x] (* x x)))

;; Symbolic functions are completely valid!
(let (~/) [x] (/ 1.0 x)) ; / uses the same modular implicits!
(~/ 4.0) ; 0.25

;; Miru has a lot of data structures but the most fundamental ones include:

;; Lists are immutable, ordered, homogeneous singly linked lists.
'(1 2 3)
;; or
(list 1 2 3)

;; Tuples are immutable, fixed-sized collections of heterogeneous elements.
;; They are also a product type!
[1, 2.0 "Hello World"] ; commas are the same as whitespace.
;; or
(tuple 1 2.0 "Hello World")

;; Arrays are immutable, fixed-sized, contiguous, homogeneous collections.
#a[1 2 3] ; #a is a tagged dispatch macro! More on it later.
;; or
(array 1 2 3)

;; Dynamic arrays are the mutable version of arrays.
;; In Miru, mutability is a property of data structures. Thus, Miru has no
;; concept of a mutable pointer.
#da[1 2 3]
;; or
(dynamic-array 1 2 3)

;; Sets are immutable, purely applicative, unordered, homogeneous collections
;; that enforce unique elements.
#s[1 2 3]
;; or
(set 1 2 3)

;; Records are product types just like tuples. They are nominal by default but
;; can be made structural to explicitly enable row polymorphism.
(type session
  { id string
    name string })

;; This will be inferred as session. Anonymous definitions are illegal here due
;; to the fundamental limitations of a nominal type.
(let s1 { id "MIRU" name "Miru Session" })

;; To opt into structural typing, append the anonymous row operator `| _`.
;; This forces the compiler to treat the record as an open, anonymous shape
;; instead of binding it to a nominal definition.
(let s2 { id "MIRU" name "Miru Session" | _ })

;; This enables a powerful feature called field-level row-polymorphism.
;; For example, let's define a function to print the id of a session.
;; We'll take any record as input that has an "id" field.
(let print-id [record : { id string | _ }] ; "_" is a row variable we ignored.
  (println (.id record))) ; Nominal types can seamlessly fit here!

;; Both of these work!
(print-id s1) ; s1 is nominal.
(print-id s2) ; s2 is structural.

;; While expressive, structural records come with their own set of performance
;; penalties. Nominal records can be represented as a single block of memory with
;; field access mapped to offset lookups. Structural records make use of VTables
;; which equate to extra pointer chasing and loss of contiguity.

;; Records can have mutable fields.
(type person
  { name string
    (mutable age) int }) ; mutable is also a specifier but for fields!

(let p1 { name "John Doe" age 30 })
(.age! 31 p1) ; an special setter is generated with a "!" suffix to allow mutation.
;; This is also valid. Fully qualified setters are easier to optimize since the
;; nominal type is known before-hand.
(person.age! 31 p1)

;; These setters boil down to a "<-" (mutating) primitive operation.
;; All these operations are data-last.
(<- person.age 31 p1)

;; We can use this property to build a ref cell around records.
(type (ref a) ; "a" is a type variable.
  { mutable contents a })

;; We can use ref cells to simulate mutable bindings.
(let name (ref "Miru"))
(println name.contents) ; Miru

(ref.contents! "MIRU" name)
(println name.contents) ; MIRU

(<- ref.contents "MirU" name)
(println name.contents) ; MirU

;; This is a very useful construct and the stdlib will provide it by default.
;; Mutating and de-referencing is common enough that Miru has a built-in
;; reader for references, and a symbolic function for mutation.
(@<- "Miru" name)
(println @name) ; Miru

;; The "@<-" function is implemented as follows:
(let (@<- a) [value : a, container : (ref a)]
  (<- ref.contents value container))

;; We can also use the type expression to define sum or variant types.
(type (shape r1 r2) ; r1 and r2 are type variables turned row variables.
  (Circle { radius float | r1 }) ; Variant constructors must be capitalized!
  (Rectangle { width float, height float | r2 })) ;

(let [basic-circle { radius 5.0 | _ }
      fancy-circle { radius 10.0, color "red" | _ }
      shape-1 (Circle basic-circle)
      shape-2 (Circle fancy-circle)]) ; Both are valid!

;; Let's look at more examples of variant types:
(type colors
  (White) ; Constructors with no payload.
  (Gray)
  (Black)
  (RGB [int int int]) ; Tuple variants are also allowed!
  (HSL { h int, s int, l int })) ; Record variants as usual.

(let a White)
(let b (RGB 240 80 40)) ; This uses the same [1 2 3] -> (tuple 1 2 3) convention.
(let c (HSL { h 240, s 80, l 40 }))

;; Tuples variants are strictly nominal even though tuples are structural.
;; Record variants are strictly normial even though records can be structural.
;; Match expressions are really handy when it comes to ADTs.
(match a
  ((or (White) (Gray) (Black))
    (println "Got constructors with no payload!"))
  ((RGB t)
    (open Int/Implicits)
    ;; The tuple t is refined in this scope, so we can use .<prop> syntax!
    (println "Got: {} * {} * {}" (.0 t) (.1 t) (.2 t)))
  ((HSL r)
    (open Int/Implicits)
    ;; Same goes for the record r!
    ;; The compiler is smart enough to optimize .<prop> into offsets instead of
    ;; using a VTable!
    (println "Got: {{ h {}, s {}, l {} }" (.h r) (.s r) (.l r))))
    ;;             ^ double braces to escape!
  
;; We use the "alias" specifier to create type aliases.
(type (alias word) (option int)) ; Why would anyone want an optional word :}

;; We can also use (and ...) for mutually recursive types!
;; Types don't require the "rec" specifier because they are recursive by default!
(and
  (type expression
    (Literal  [int])
    (Variable [string])
    (Block    [(list statement)]))
  (type statement
    (Assignment     [string expression])
    (IfThenElse     [expression statement statement])
    (VoidExpression [expression])))

;; Let's build a tree for an example!
(type (tree a)
  (Empty)
  (Node [(tree a) a (tree a)]))

(let example-tree
  (Node [
    (Node [Empty 7 Empty])
    5
    (Node [Empty 9 Empty])
  ]))
```

TODO!
