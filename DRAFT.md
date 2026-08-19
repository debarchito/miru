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
annotations, it infers types of expressions using an Hindley-Milner foundation
extended with OutsideIn(X) constraint-solving engine and bi-directional
type-checking strategies.

```clojure
;; This is a standalone comment.

;; Variables and functions are both defined using the let keyword.
(let name "Miru") ; Inline comments use a single ";"

;;; This is a documentation comment for the greet function that takes an
;;; argument name inferred as string.
(let greet [name]
  (println (String/concat "Hello, " name)))

;; You can specify the type definition using a (val ...) expression.
;; The type signature are written in curried form. Type signatures use infix
;; forms which is how you would define them in mathematics. The type unit is
;; special because Miru doesn't have an equivalent of nil as a primitive.
;; Additionally, like most functional languages Miru lacks procedures. Every
;; function must return something even if it's an unit.
(val greet : string -> unit)
(let greet [name]
  ;; f-strings are special format strings! They are desugared into
  ;; GADT-powered contexts, very similar to OCaml and Haskell!
  ;; "<>" is a semigroup append function. Since string concatenation forms a
  ;; free semigroup, it behaves the same as String/concat!
  (println f"{}" (<> "Hello, " name))
  ;; Modular implicits allow locally-resolved typeclass-like features.
  ;; You can also insert the value inside the {...}!
  (println f"I've been greeting a lot today, isn't it {name}?"))

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
;; This makes this expression invalid:
(greet-morning)
;; If you want to alias functions, you can simply:
(let aliased-greet-morning greet-morning)

;; Functions are automatically curried.
(let make-inc [x y] (+ x y)) ; int -> int -> int
(let inc-2 (make-inc 2)) ; int -> int
(inc-2 3) ; 5

;; This makes composition really clean.
(let new-list (map (* 2) [1 2 3 4])) ; [2 4 6 8]

;; You can use (block ...) to group multiples expressions in a single block.
;; let uses sequential binding, similar to let* in Scheme. They are similar to
;; let ... in ... expressions in OCaml.
(block
  (let [x 10
        y (+ x 10)])
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
;; compiler can track value bounds. No need for pre-defined symbols!
(and
  (let (rec is-even?) [n]
    (match n
      0 true
      n (is-odd? (- n 1))))
  (let (rec is-odd?) [n]
    (match n
      0 false
      n (is-even? (- n 1)))))

;; Additionaly, let can also be used for destructuring.
;; Almost all data structures can be destuctured!
(let [x y z] [1 2.3 "hello!"])
(println "{} {} {}" x y z) ; 1 2.3 hello!

;; Since functions are first-class you can always use lambdas.
(let square (fn [x] (* x x)))

;; Symbolic functions are completely valid!
;; They must be defined inside a (...)
(let (~/) [x] (/ 1.0 x))
(~/ 4.0) ; 0.25

;; Miru has a lot of data structures. Let's take a look at some of them:

;; Tuples are immutable, fixed-sized collections of heterogeneous elements.
;; Tuples are both persistent and a product type!
[ 1, 2.0 "Hello World" ] ; commas are the same as whitespace.

;; Lists are dynamic, ordered, homogeneous singly linked lists.
;; Lists are persistent data structures.
;; Miru doesn't have '(...) for quote blocks so we can't really
;; use them here. We instead utilize a special :(...) to signify
;; a linked list!
:( 1 2 3 )

;; Arrays are fixed-sized, contiguous, homogeneous collections.
;; Unlike OCaml, Miru arrays are immutable.
[| 1 2 3 |]

;; Mutable arrays are the mutable version of arrays. They allow in-place
;; mutaiton. In Miru, mutability is a property of data structures. Thus,
;; Miru has no concept of a mutable pointer.
[! 1 2 3 !]

;; Dynamic arrays are the resizable version of mutable arrays.
;; They are also known as vectors in other languages.
[~ 1 2 3 ~]

;; Miru is also an array language, which means it has native support for
;; N-dimentional tensors, both immutable and mutable but non-resizable.
;; Miru is column-major and 0-indexed.
[| 1 4 7 |  ; Pipes to used to segment dimensions.
   2 5 8 |  ; Rule of thumb: tensor dimension = (no. of pipes) + 1
   3 6 9 |] ; This is a 3x3 matrix!

;; The mutable version being:
[! 1 4 7 |
   2 5 8 |
   3 6 9 !]

;; What about a 3D tensor?
[| 1 5 9  |
   2 6 10 ||
   3 7 11 |
   4 8 12 |] ; This is a 2x2x3 tensor!

;; Tensors are special because they are NOT arrays of arrays. The elements
;; are stored contiguosly in memory and queried via pre-calculated offsets
;; making them ideal for anything that need high-dimensional tensors.

;; Unlike the fixed variants, dynamic arrays are strictly 1-dimentional.
;; Hence, there is no *intrinsic* way to build dynamic dimention-reshaping
;; tensors. Instead, you can use a 1D dynamic array ([~ ... ~]) to handle
;; runtime growth/dynamism, and then perform a zero-copy cast into a
;; fixed N-dimensional tensor as long as the total element count matches
;; the target shape!

(let dyn-arr [~ 1 2 3 4 5 6 7 8 9 ~])
(let result (Tensor/from-dynamic [3 3] dyn-arr))

;; You get static guarentees about the shape of the data at compiler time
;; because Miru supports liquid types for compile-time dimension checking.
;; More on them later!

;; Sets are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous collections that enforce unique elements. Uses list delimiters
;; :(...) in the reader phase to signal a heap-allocated tree layout.
#set :(1 2 3) ; #set is a tagged template reader! More on them later.
;; or
(Base/Collections/Set/from-array [| 1 2 3 |])

;; Hashsets are mutable, non-persistent, unordered (hash-based) linear
;; collections. Uses flat vector delimiters [| ... |] to signify a contiguous
;; memory layout (Swiss Table!).
#hash-set [| 1 2 3 |]
;; or
(Base/Collections/Set/Hash/from-array [| 1 2 3 |])

;; Sorted sets are immutable, persistent, value-ordered (Persistent B-Tree)
;; collections.
#sorted-set :(1 2 3)
;; or
(Base/Collections/Set/Sorted/from-array [| 1 2 3 |])

;; Ordered sets are immutable, persistent, insertion-ordered (Linked CHAMP)
;; collections.
#ordered-set :(1 2 3)
;; or
(Base/Collections/Set/Ordered/from-array [| 1 2 3 |])

;; Bit sets are mutable or unboxed, bitwise-packed sets of non-negative
;; integers.
#bit-set [| 0 1 64 128 |]
;; or
(Base/Collections/Set/Bit/from-array [| 0 1 64 128 |])

;; Maps are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous key-value collections.
#map { id 1 } ; Borrows the struct body form.
;; or
(Base/Collections/Map/from-array [| ["id" 1] |])

;; Hashmaps are mutable, non-persistent, unordered (hash-based) linear
;; key-value maps.
#hash-map { id 1 }
;; or
(Base/Collections/Map/Hash/from-array [| ["id" 1] |])

;; Sorted maps are immutable, persistent, value-ordered (Persistent B-Tree)
;; key-value maps. Orders entries by key comparison to enable range queries
;; and bounds slicing.
#sorted-map { id 1 }
;; or
(Base/Collections/Map/Sorted/from-array [| ["id" 1] |])

;; Ordered maps are immutable, persistent, insertion-ordered (Linked CHAMP)
;; key-value maps.
#ordered-map { id 1 }
;; or
(Base/Collections/Map/Ordered/from-array [| ["id" 1] |])

;; The mutable hash-sets and hash-maps function as accumulators for the
;; persistent variants just like dynamic arrays function for tensors. That
;; said, unlike dynamic arrays <-> tensors, hash-* <-> persisted-* is NOT
;; zero-copy and will allocate due to layout differences.

;; Records are product types just like tuples. They are nominal by default but
;; can be made structural to explicitly enable row polymorphism.
(type session
  { id   : string ; The keys are untagged symbols!
    name : string })

;; This will be inferred as session. Anonymous definitions are illegal due
;; to the fundamental limitations of a nominal type.
(let s1 { id "MIRU" name "Miru Session" })

;; To opt into structural typing, append the row operator `..`.
;; This forces the compiler to treat the record as an open, anonymous shape
;; instead of binding it to a nominal definition.
(let s2 { id "MIRU", name "Miru Session" .. }) ; Commas are whitespaces!

;; This enables a powerful feature called field-level row-polymorphism.
;; For example, let's define a function to print the id of a session.
;; We'll take any record as input that has an "id" field. < ... > are rows!
(val print-id : < id : string | _ > -> unit
(let print-id [record]
  (println (.id record))) ; Nominal types can seamlessly fit here!

;; Both of these work!
(print-id s1) ; s1 is nominal.
(print-id s2) ; s2 is structural.

;; .. is an alias for | _ at the type level; so you could write it as:
(val print-id : < id : string .. > -> unit) 

;; While expressive, structural records come with their own set of performance
;; penalties. Nominal records can be represented as a single block of memory with
;; field access mapped to offset lookups. Instead of using VTables, this
;; implementation uses evidence passing, passing field offsets dynamically via
;; registers. The performance tax here shifts from pointer-chasing cache misses
;; to register pressure, minor function-call overhead, and the loss of specific
;; static optimizations (like vectorization) at compilation boundaries.

;; Records can have mutable fields.
(type person
  { name      : string
    (mut age) : int }) ; "mut" is also a specifier but for fields!

(let p1 { name "John Doe" age 30 })

;; Miru has a single "<-" (mutating) primitive function.
;; All operations are data-last.
(<- person.age 31 p1)

(person.age p1) ; 31

;; We can use this property to build a ref cell around records.
(type (ref 'a) ; 'a is also known as alpha; a unification variable.
  { (mut contents) : 'a })

;; We can use ref cells to simulate mutable bindings.
(let name (ref "Miru"))
(println (ref.contents name)) ; Miru

(<- ref.contents "MIRU" name)
;; This also works.
(println (.contents name)) ; MIRU

;; This is a very useful construct and the base will provide it by default.
;; Mutating and de-referencing is common enough that Miru has a built-in
;; functions for references, and a symbolic function for mutation. This is
;; similar to OCaml and Koka. !<id> is implemented as a special reader.
(:= "Miru" name)
(println !name) ; Miru

;; The := function is implemented as follows:
(val (:=) : 'a -> (ref 'a) -> unit)
(let (:=) [value container]
  (<- ref.contents value container))

;; We can also use the type expression to define sum or variant types.
;; '<id> is reserved for type variables in Miru not quoting.
;; Infact, Miru only supports *typed* quasi-quoting using `(...) which
;; evaluate to an (expr 't) data-structure. More on them later!
(type shape
  (Circle < radius : float .. >)) ; Variant constructors must be capitalized!

(let [basic-circle { radius 5.0 .. }
      fancy-circle { radius 10.0 color "red" .. }
      shape-1 (Circle basic-circle)
      shape-2 (Circle fancy-circle)]) ; Both are valid!

;; Let's look at more examples of variant types:
(type colors
  (White)
  Gray ; Parens are optional for constructors with no payload.
  (Black)
  (RGB [int int int]) ; Tuple variants are also allowed!
  (HSL { h int, s int, l int })) ; Record variants as usual.

;; The constructors are made available in the global space.
(let a White)
(let b (RGB [240 80 40]))
(let c (HSL { h 240, s 80, l 40 }))

;; Tuples variants are strictly nominal even though tuples are structural.
;; Record variants are strictly normial even though records can be structural.
;; Match expressions are really handy when it comes to ADTs.
(match a
  ;; Just like (and ...), (or ...) are special context-resolvers.
  ;; Here, they together with "match" replace the need of a "|" operator.
  (or White Gray Black)
    (println "Got constructors with no payload!")

  (RGB t)
    ;; The tuple t is refined in this scope, so we can use .<prop> syntax!
    (println "Got: {} * {} * {}" (.0 t) (.1 t) (.2 t))

  (HSL r)
    ;; Same goes for the record r!
    ;; The compiler is smart enough to optimize .<prop> into offsets instead of
    ;; using evidence passing!
    (println "Got: {{ h {}, s {}, l {} }}" (.h r) (.s r) (.l r)))
    ;;             ^        <->        ^ double braces to escape!
  
;; We use the "alias" specifier to create type aliases.
(type (alias word) (option int)) ; Why would anyone want an optional word :}

;; We can also use (and ...) for mutually recursive types!
;; Types also require the "rec" specifier. Implicit recursion is not allowed
;; anywhere.
(and
  (type (rec expression)
    (Literal  int)
    (Variable string)
    (Block    (list statement)))
  (type (rec statement)
    (Assignment      [string expression])
    (If-then-else    [expression statement statement])
    (Void-expression expression)))

;; Let's build a tree for an example!
(type (tree 'a)
  Empty
  (Node [(tree 'a) 'a (tree 'a)]))

;; And use it.
(let example-tree
  (Node [
    (Node [Empty 7 Empty])
    5
    (Node [Empty 9 Empty])]))

;; Variants are closed by nature. You can't extend them. This is where
;; structural variants come into picture! They operate the same way
;; you would expect them to behave in OCaml! This is also powered using
;; row-polymorphism but extended to variants. They are open and can form
;; a structural union.
(type small < :A :B >)
(type large < :A :B :C (:D string) .. >) ; They can have payloads!

;; They look a lot like keywords in Clojure but statically typed. Infact,
;; they are a drop-in replacement for a lot of cases where you'd
;; traditionally use keywords. Hence, the similar syntax.
(let process-large [x]
  (match x
    :A           "Alpha"
    :B           "Beta"
    :C           "Gamma"
    (:D payload) payload
    _            "?")))

(let (item : small) :A)
(let (process-large item)) ; ERROR! small is not compatible with large.
(let (process-large (:> item large))) ; Works!
;; Type coercion is explicit in Miru! ":>" is the coercion operator.

;; The colors variant e.g. but with structural variants:
(type colors
  < :White
    :Gray
    :Black
    (:RGB [int int int])
    (:HSL { h int, s int, l int }) >)

;; Time to introduce GADTs!
;; For this e.g., let's model an expresssion evaluator.
(type (exp _) ; The type variable we'll specialize.
  ;; Notice the ":" after the constructor. You MUST specify the returning
  ;; type. Specialization is explicit!
  (Int     : int                   -> (exp int))
  (Bool    : bool                  -> (exp bool))
  (Add     : [(exp int) (exp int)] -> (exp int))
  (Is-zero : (exp int)             -> (exp bool)))

;; (type a) introduces a locally abstract type called "a." They are NOT
;; type variables! A type variable is a flexible placeholder that can unify
;; with any type, while a locally abstract type creates a rigid, newly
;; minted type identity scoped strictly inside that function. They are what
;; enable local type refinement which is crucial to make GADTs work!
(val eval : (type a) . (exp a) -> a)
(let (rec eval) [e] ; The "rec" specifier is a property of the binding!
  ;; The abstract type "a" is refined in the branches!
  (match e
    (Int n)     n
    (Bool b)    b
    (Add [x y]) (+ (eval x) (eval y))
    (Is-zero x) (= (eval x) 0)))

(let safe-exp (Add (Int 5) (Int 10)))
(eval safe-exp) ; 15

(let bad-exp (Add (Int 5) (Bool true))) 
;;                        ^^^^^^^^^^^ Expected (exp int), got (exp bool)

;; Let me introduce you the crown jewel: effects. We define a simple
;; effect with two distinct effect operations. There are different kinds of
;; effect operation types: direct operations, one-shot controls, tail-resuming
;; one-shot controls, and muli-shot controls.
(effect (state 'a)
  ;; These are examples of direct operations. They are used when you want to
  ;; perform an operation and return a value directly back to the perform site.
  ;; They can resume exactly once and have no access to a continuation. They read
  ;; and are typed exactly like functions.
  (val get : unit -> 'a) 
  (val set : 'a -> unit))

;; Now, we define a function that performs the console effect.
;; Miru tracks the set of effect types as effect rows. They support row-polymorphism.
(val increment-by : int -> int / < (state int) .. >)
(let increment-by [amount]
  (let current (get ()))
  (set (+ current amount))
  (get ()))

;; Now, let's write a handle for the function. It reduces the state effect
;; from the row using row variables.
(val run-state : (int -> int / < (state int) | 'e>) -> int / < 'e >)
(let run-state [init action]
  (let state (ref init))

  ;; with-expressions allow us to eliminate deeply nested code blocks caused
  ;; by trailing closures, etc. More concrete examples will follow soon.
  (with
    (handle
      (get ()) !state
      (set x)  (:= x state))))

  ;; Now we can call the function without fear!
  (action ()))

;; #(...) are anonymous functions.
(let res (run-state 10 #(increment-by 5)))
(println "{}" res) ; 15

;; Control operations capture the delimited continuation `k` at the perform site.
;; Like Koka, control operations default to one-shot resumptions: `k` can be
;; called at MOST ONCE (0 times to abort, or 1 time to resume).

;; Lets model generators!
(effect (gen 'a)
  (control yield : 'a -> unit))

;; A function that performs the generator effect.
(val range : int -> int -> unit / < (gen int) .. >)
(let range [start end]
  (if (<= start end)
    (block
      (yield start)
      (range (+ start 1) end))
    ()))

(val run-print-gen : (unit -> unit / < (gen int) | 'e >) -> unit / < 'e >)
(let run-print-gen [action]
  (with (yield item) ; Syntactic sugar for a single-operation effect handle!
    (println "Yielded: {}" item)
    (resume ()))
 
  (action ()))

(run-print-gen #(range 1 3))
;; Output:
;; Yielded: 1
;; Yielded: 2
;; Yielded: 3

;; A final control is explicitly non-resumptive; invoking resume inside its handle
;; causes a compile-time error. This allows the compiler to optimize the operation
;; as a non-local jump.

;; For example, we can model exceptions using final controls.
(effect (exn 'e)
  (final throw : 'e -> 'a))

(val parse-age : int -> int / < (exn string) .. >)
(let parse-age [age]
  (if (< age 0)
    (throw "Age cannot be negative")
    age))

;; A simple example to turn exceptions into options.
(val run-exn : (unit -> 'a / < (exn string) | 'e >) -> (option 'a) / < 'e >)
(let run-exn [action]
  (with (throw err)
    (println "Caught error: {}" err)
    None) ; We cannot use resume here.
  
  (Some (action ())))

(let res1 (run-exn #(+ (parse-age -5) 100)))
(println "{}" res1) ; None

;; Multi-shot effects are opt-in at the effect level using the `multi` modifier.
;; Because multi-shot operations clone stack frames and data contexts to preserve 
;; purity across branches, marking the entire effect as `multi` signals to the compiler
;; that stack-cloning machinery is required.
(effect (multi amb)
  ;; Now this control has multi-shot capabilities.
  (control flip : unit -> bool))

;; Because it performs a multi-shot effect, this branch will evaluate and
;; return multiple times during handling.
(val choices : int -> int / < amb .. >)
(let choices [x]
  (if (flip ())
    (+ x 10)
    (+ x 0)))

;; Handler for non-deterministic choice using `with`.
;; Handlers handling multi-shot effects require a `return` clause (value clause)
;; to wrap the base leaf results into a collection.
(val handle-amb : (unit -> 'a / < amb | 'e >) -> (list 'a) / < 'e >)
(let handle-amb [action]
  (with
    (handle
      ;; Wrap the normal completion result in a list. This is special, and also
      ;; known as the value clause.
      (return v)
        :(v)

      (flip ())
        ;; Combine the results of both forks.
        (<> (resume true) (resume false))))

  (action ()))

(let res (handle-amb #(choices 5)))
(println "{}" res) ; :(15 5)

;; Let's take a bit of time to understand the with-expression. Here are some
;; cases. First is the case for a scoped resource manager.
(let count-steps [()]
  (scoped 0
    #(block
      (:= (+ !% 1) %)
      (:= (+ !% 2) %)
      !%)))

;; That's a lot of nesting. Now let's rewrite it with with-expression.
;; This makes the code very linear. with-expression takes advantage of the
;; fact that Miru functions auto-curry and rewrite the scope for you.
(let count-steps [()]
  (with s (scoped 0))
  (:= (+ !s 1) s)
  (:= (+ !s 2) s)
  !s)

;; This is also the property that makes handles much easier to write.
(with
  (handle
    (emit msg)
      (block
        (println "{}" msg)
        (resume ()))))

(emit "1st!")
(emit "2nd")

;; Would otherwise be something closer to:
(handle
  (emit msg)
    (block
      (println "{}" msg)
      (resume ()))
  #(block
    (emit "1st!")
    (emit "2nd"))) ;; This will get very tedious with nested handles.

;; While algebraic effects track what a computation does downstream (outputs), 
;; Miru uses coeffects to track what a computation demands upstream (inputs). 
;; Instead of bubbling up to a handle, coeffects represent dynamic contexts 
;; injected down into the function before it can execute. 

;; Miru tracks coeffect rows using a backslash `\`. Just like effect, coeffects also
;; support row-polymorphism.
(val fetch-user-data : string \ < api-key : string, timeout : int .. > -> string)
(let fetch-user-data [user-id]
  (let key \api-key) ; \<token> is how you read from a coeffect!
  (let delay \timeout) ; This also helps the inference engine to infer coeffects.
  (format "https://api.example.com/{}?key={}&delay={}" user-id key delay))

;; To discharge coeffects, we use a provide block instead of a handle block.
(let mock [action]
  ;; The same ergonomics as with handle!
  (with (provide { api-key "KEY123", delay 5000 .. }))
  (with (provide { delay 10000 .. })) ; Overwrites the 5000 timeout!
  (action ()))

(mock #(fetch-user-data "user_miru")) ; Simple as that!

;; It's nice to think it in terms of: you handle effects and provide contexts.
;; Effects capture dynamic control flow operations that bubble up the stack,
;; but are structurally wrong for passive requirements. Coeffects exist to
;; track the opposite direction: what a function demands down from its
;; environment before executing. Coeffects are really useful to enable
;; compile-time safety constraints.

;; Miru's tagged template readers provide the same expression power as
;; OCaml PPX transformers. This also mean, they come with their own set
;; of downsides: fragility, hygiene and most importantly they are untyped!
;; While they are very powerful compiler extensions, a typed subset makes
;; day-to-day utilities feel less like a chore. Miru takes a lot of
;; inspiration from MetaOCaml to implement expression values, and the two
;; basic constructs to build them: quoting and splicing.

;; These are just normal Miru functions that modify (expr 'a) just like any
;; other data structure! It is also known as multi-stage expansion.
(val unroll : int -> (expr int) -> (expr int))
(let (rec unroll) [n x] 
  (match n
    0 `1 ; Quoting!
    1 x
    _ `(* $x $(unroll (-n 1) x)))) ; Both $(<token>) and $<token> are splices!

;; (expand ...) is a special form that evaluates ANY (expr 'a) and inlines it at
;; compile-time.
(let value (expand (unroll 4 `3))) ; (* 3 (* 3 (* 3 (* 3 1))))

;; Miru integrates SMT solvers to provide native support for Liquid Refinement
;; types! A rather common runtime check is array bounds but with liquid types,
;; you can prove that an index never leaves the array's bounds at compile-time!

;; Parameterizing length directly in the array type:
(val get-at : (arr : (array 'a)) -> (i : int | (&& (>= i 0) (< i (Array/length arr)))) -> 'a)
;; Refinement uses the pipe (|) operator.
;; (Array/length arr) here works as a reflected measure! More on measures and reflections later.

;; The compiler will ensure that 0 <= i < length(arr) always holds true.
(let get-at [arr i]
  ;; The refinement allows us to remove runtime checks from this get call!
  (Array/get arr i))

;; You can also move the predicates into claims! Very similar to LiquidHaskell's predicates.
(claim in-bounds [i arr]
  (&& (>= i 0) (< i (Array/length arr))))

;; And use it in the predicate position:
(val get-at : (arr : (array 'a)) -> (i : int | (in-bounds i arr)) -> 'a)
```

TODO!
