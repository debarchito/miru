This document drafts a high level design of what the language _should_ look
like. This document serves as my scratchpad for what features I want to
implement and experiment with. It is an ongoing process and nothing is
finalized. I've tried to format it similar to
[Learn X in Y minutes](https://learnxinyminutes.com) where X=Miru!

---

Miru is a strictly evaluated functional language that borrows much of its syntax
from languages like Clojure, Carp et al. while implementing the semantics of
languages like OCaml and Koka with great premise on Algebraic Effects and Effect
tracking. It's designed to be pragmatic and useful for day to day general
purpose tasks while also being a great fit for doing math and science.

It is strongly and statically typed, but instead of using manually written type
annotations, it infers types of expressions using an Hindley-Milner foundation
extended with OutsideIn(X) constraint-solving engine and bi-directional
type-checking strategies.

```clojure
;; This is a standalone comment.

;; Bindings defined using the let keyword.
(let name "Miru") ; Inline comments use a single ";" by convention.

;;; This is a documentation comment for the greet function that takes an
;;; argument name inferred as string.
(let greet [name]
  ;; f-strings are special format strings. They are desugared into
  ;; GADT-powered contexts, very similar to OCaml.
  (println (f"{}" (String/concat "Hello, " name))))

;; You can specify the type of a binding using a (val ...) expression.
;; The type signatures are written in curried form while using infix
;; applications (->). The type unit is special because Miru doesn't have
;; an equivalent of nil as a primitive. Additionally, like most functional
;; languages Miru lacks procedures. Every function must return something
;; even if it's an unit.
(val greet : string
          -> unit)
(let greet [name]
  ;; "<>" is a semigroup append function. Since string concatenation forms a
  ;; free semigroup, it behaves the same as String/concat.
  (println (f"{}" (<> "Hello, " name)))
  ;; You can also interpolate a value using {...}.
  (let msg (<> "Hello, " name))
  (println f"{msg}") ; println MUST take an f-string!
  (println f"I've been greeting a lot today, isn't it {name}?"))
  ;; Implicit module resolution allow various scope-resolved typeclass-like
  ;; features you often find in Rust and Haskell.

;; Miru has support for raw strings and string tags.

"I'm a normal string"
(json)"{"name":"miru"}"(json) ; Tagged strings.

r"This is a raw \n string"
r(json)"{"name":"miru"}"(json) ; Raw strings can also be tagged!

(let interpolate "perform interpolation!")
rf"This is a raw string but can {interpolate}"

;; The "f" suffix can be repeated to change evaluation sementics:
(let value "Miru")
rff(json)"{"name":"{{value}}"}"(json)

;; Rule of thumb:
;; f -> {...}
;; ff -> {{...}}
;;; fff -> {{{...}}} and so on.

;; Recursive functions need to be marked with a "rec" specifier.
;; Specifiers are special positional properties attached to labels that can also
;; be propagated when composed with certain forms.
(let (rec factorial) [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

;; Every function must have at least one argument. Some functions naturally don't
;; take any arguments, so there's "unit" type for it that has only one value
;; written as "()".
(let greet-morning [()]
  (println f"Good morning!"))

;; Unlike most Lisps, you must specify "()" when calling a function just for its
;; side-effect.
(greet-morning ())
;; This makes this expression invalid:
(greet-morning)
;; If you want to alias functions, you can simply:
(let aliased-greet-morning greet-morning)

;; Functions are automatically curried.
(let make-inc [x y] (+ x y)) ; - int -> int -> int = function
(let inc-2 (make-inc 2)) ; - int -> int = function
(inc-2 3) ; - int = 5

;; This makes composition really clean. :(...) are lists.
(let new-list (map (* 2) :(1 2 3 4))) ; :(2 4 6 8)

;; You can use (begin ...) to group multiples expressions in a sequential scope.
;; let uses sequential binding, similar to let* in Scheme. They are similar to
;; let ... in ... expressions in OCaml.
(begin
  (let x 10)
  (let y (+ x 10))
  (+ x y)) ; 30

;; You can utilize tuple unpacking for parallel bindings. It keeps composition
;; cleaner.
(begin
  (let a 1)
  (let [b c] [(+ a 1) (+ a 2)]) ; b and c are not aware of each other.
  (let d (+ b c)) ; Sequential again: d sees both b and c.
  (reduce + 0 :(a b c d))) ; Return the final expression.

;; You can use (and ...) alongside (let ...) for parallel bindings too.
(let (rec is-even?) [n]
  (match n
    0 true
    n (is-odd? (- n 1))))

(and is-odd? [n]
  (match n
    0 false
    n (is-even? (- n 1))))

;; To note, "rec" is viral when composed with (and ...). Similar to OCaml,
;; let ... and ... are non-recursive parallel bindings while let rec ...
;; and ... are recursive parallel bindings. You CANT mix recursive and
;; non-recursive bindings in such cases. Aditionally, functions are closures,
;; and delayed evaluation allows them to reference each other unlike the
;; previous case which was eager.

;; This means, the first parallel binding example can also be written as:
(begin
  (let a 1)
  (let b (+ a 1))
  (and c (+ a 2))
  (let d (+ b c))
  (reduce + 0 :(a b c d)))

;; Another unpacking example:
(let [x y z] [1 2.3 "hello!"])
(println f"{x} {y} {z}") ; 1 2.3 hello!

;; Since functions are first-class, you can always use lambdas.
(let square (fn [x] (* x x)))

;; Symbolic functions are completely valid, although must be defined inside
;; a (...).
(let (~/) [x] (/ 1.0 x))
(~/ 4.0) ; 0.25

;; Miru has a lot of data structures. Let's take a look at some of them:

;; Tuples are immutable, fixed-sized collections of heterogeneous elements.
;; Tuples are both persistent and a product type.
[ 1, 2.0 "Hello World" ] ; commas are the same as whitespace.

;; Lists are dynamic, ordered, homogeneous singly linked lists. Lists are
;; persistent data structures.
:( 1 2 3 )

;; Arrays are fixed-sized, contiguous, homogeneous collections. Unlike OCaml,
;; Miru arrays are immutable.
[| 1 2 3 |]

;; Mutable arrays are the mutable version of arrays. They allow in-place
;; mutation. In Miru, mutability is a property of data structures. Thus,
;; Miru has no concept of a mutable pointer (but we can emulate one later).
[! 1 2 3 !]

;; Dynamic arrays are the resizable version of mutable arrays. They are also
;; known as vectors in other languages.
[~ 1 2 3 ~]

;; Miru is an array language, which means it has native support for
;; N-dimentional tensors, both immutable and mutable but non-resizable. Miru
;; is column-major and 0-indexed.
[| 1 4 7 |  ; Pipes to used to segment dimensions.
   2 5 8 |  ; Rule of thumb: tensor dimension = (no. of pipes) + 1
   3 6 9 |] ; This is a 3x3 matrix.

;; The mutable version being:
[! 1 4 7 |
   2 5 8 |
   3 6 9 !]

;; What about a 3D tensor?
[| 1 5 9  |
   2 6 10 ||
   3 7 11 |
   4 8 12 |] ; This is a 2x2x3 tensor.

;; Tensors are special because they are NOT arrays of arrays. The elements
;; are stored contiguosly in memory and queried via pre-calculated offsets
;; making them ideal for anything that need high-dimensional tensors.

;; Unlike the fixed variants, dynamic arrays are strictly 1-dimentional.
;; Hence, there is no *intrinsic* way to build dynamic dimention-reshaping
;; tensors. Instead, you can use a 1D dynamic array ([~ ... ~]) to handle
;; runtime growth/dynamism, and then perform a zero-copy cast into a
;; fixed N-dimensional tensor as long as the total element count matches
;; the target shape.

(let dyn-arr [~ 1 2 3 4 5 6 7 8 9 ~])
(let result (Tensor/from-dynamic [3 3] dyn-arr))

;; You get static guarentees about the shape of the data at compiler time
;; because Miru supports liquid types for compile-time dimension checking.
;; More on them later.

;; Sets are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous collections that enforce unique elements. Uses list delimiters
(#set 1 2 3) ; #set is a procedural macro. More on them later.
;; or
(Base/Collections/Set/from-array [| 1 2 3 |])

;; Hashsets are mutable, non-persistent, unordered (hash-based) linear
;; collections.
(#hash-set 1 2 3)
;; or
(Base/Collections/Set/Hash/from-array [| 1 2 3 |])

;; Sorted sets are immutable, persistent, value-ordered (Persistent B-Tree)
;; collections.
(#sorted-set 1 2 3)
;; or
(Base/Collections/Set/Sorted/from-array [| 1 2 3 |])

;; Ordered sets are immutable, persistent, insertion-ordered (Linked CHAMP)
;; collections.
(#ordered-set 1 2 3)
;; or
(Base/Collections/Set/Ordered/from-array [| 1 2 3 |])

;; Bit sets are mutable or unboxed, bitwise-packed sets of non-negative
;; integers.
(#bit-set 0 1 64 128)
;; or
(Base/Collections/Set/Bit/from-array [| 0 1 64 128 |])

;; Maps are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous key-value collections. It's common to use [x y] as a pair.
(#map [id 1])
;; or
(Base/Collections/Map/from-array [| ["id" 1] |])

;; Hashmaps are mutable, non-persistent, unordered (hash-based) linear
;; key-value maps.
(#hash-map [id 1])
;; or
(Base/Collections/Map/Hash/from-array [| ["id" 1] |])

;; Sorted maps are immutable, persistent, value-ordered (Persistent B-Tree)
;; key-value maps. Orders entries by key comparison to enable range queries
;; and bounds slicing.
(#sorted-map [id 1])
;; or
(Base/Collections/Map/Sorted/from-array [| ["id" 1] |])

;; Ordered maps are immutable, persistent, insertion-ordered (Linked CHAMP)
;; key-value maps.
(#ordered-map [id 1])
;; or
(Base/Collections/Map/Ordered/from-array [| ["id" 1] |])

;; The mutable hash-sets and hash-maps function as accumulators for the
;; persistent variants just like dynamic arrays function for tensors. That
;; said, unlike dynamic arrays <-> tensors, hash-* <-> persisted-* is NOT
;; zero-copy and will allocate due to layout differences.

;; Records are product types just like tuples. They are nominal by default but
;; can be made structural to explicitly enable row polymorphism.
(type session
  { id   : string ; The keys are untagged symbols.
    name : string })

;; This will be inferred as session. Anonymous definitions are illegal due
;; to the fundamental limitations of a nominal type.
(let s1 { id "MIRU" name "Miru Session" })

;; To opt into structural typing, append the row operator `..`.
;; This forces the compiler to treat the record as an open, anonymous shape
;; instead of binding it to a nominal definition.
(let s2 { id "MIRU", name "Miru Session", .. }) ;; comma are spaces.

;; This enables a powerful feature called field-level row-polymorphism.
;; For example, let's define a function to print the id of a session.
;; We'll take any record as input that has an "id" field. { ... } are rows
;; and yes they track their lineage to records!
(val print-id : { id : string, .. }
             -> unit)
(let print-id [record]
  (println (f"{}" (.id record)))) ; Nominal types can seamlessly fit here.

;; Both of these work:
(print-id s1) ; s1 is nominal.
(print-id s2) ; s2 is structural.

;; ..<id> can be used when the row variable needs a name. r is a unification
;; variable by default not an abstract type.
(val print-id : { id : string, ..r } -> unit)

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
    (mut age) : int }) ; "mut" is also a specifier but for fields.

(let p1 { name "John Doe", age 30 })

;; Miru has a single "<-" (mutating) primitive function. All operations are
;; data-last.
(<- person.age 31 p1)

(person.age p1) ; 31

;; We can use this property to build a ref cell around records.
(type (ref a) ; a is also an unification variable here.
  { (mut contents) : a })

;; We can use ref cells to simulate mutable bindings.
(let name (ref "Miru"))
(println (f"{}" (ref.contents name))) ; Miru

(<- ref.contents "MIRU" name)
;; This naturally works.
(println (f"{}" (.contents name))) ; MIRU

;; This is a very useful construct and the Base will provide it by default.
;; Mutating and de-referencing is common enough that Miru has a built-in
;; reader (!<id>) for references, and a symbolic function for mutation. This
;; is similar to OCaml.
(:= "Miru" name)
(println (f"{}" !name)) ; Miru

;; The := function is implemented as follows:
(val (:=) : a
         -> (ref a)
         -> unit)
(let (:=) [value container]
  (<- ref.contents value container))

;; We can also use the type expression to define sum or variant types.
(type shape
  (Circle { radius : float, .. })) ; Variant constructors must be capitalized.

(let [basic-circle { radius 5.0, .. }
      fancy-circle { radius 10.0, color "red", .. }
      shape-1 (Circle basic-circle)
      shape-2 (Circle fancy-circle)]) ; Both are valid.

;; Let's look at more examples of variant types:
(type colors
  (White)
  Gray ; Parens are optional for constructors with no payload.
  (Black)
  (RGB [int int int]) ; Tuple variants are also allowed.
  (HSL { h int, s int, l int })) ; Record variants as usual.

;; The constructors are made available in the global scope.
(let a White)
(let b (RGB [240 80 40]))
(let c (HSL { h 240, s 80, l 40 }))

;; Tuples variants are strictly nominal even though tuples are structural.
;; Record variants are strictly normial even though records can be structural.
;; Match expressions are really handy when it comes to ADTs.
(match a
  ;; (or ...) is a special form inside a match expression forming a union.
  (or White Gray Black)
    (println f"Got constructors with no payload!")

  (RGB t)
    ;; The tuple t is refined in this scope, so we can use .<prop> syntax.
    (println (f"Got: {} * {} * {}" (.0 t) (.1 t) (.2 t)))

  (HSL r)
    ;; Same goes for the record r. The compiler is smart enough to optimize
    ;; .<prop> into offsets instead of using evidence passing.
    (println (f"Got: {{ h {}, s {}, l {} }}" (.h r) (.s r) (.l r)))
    ;;               ^        <->        ^ {{ or }} to escape interpolation.
    ;; or just:
    (println (ff"Got: { h {{}}, s {{}}, l {{}} }" (.h r) (.s r) (.l r))))
    ;; Any of these work.
  
;; We use the "alias" specifier to create type aliases.
(type (alias word) (option int)) ; Why would anyone want an optional word :O?

;; We can also use (and ...) for mutually recursive types! Unlike OCaml, types
;; require the "rec" specifier. Implicit recursion is not allowed anywhere in
;; Miru.
(type (rec expression)
  (Literal  int)
  (Variable string)
  (Block    (list statement)))

(and statement
  (Assignment      [string expression])
  (If-then-else    [expression statement statement])
  (Void-expression expression)))

;; Let's build a tree for an example.
(type (tree 'a)
  Empty
  (Node [(tree 'a) 'a (tree 'a)]))

;; And use it:
(let example-tree
  (Node [
    (Node [Empty 7 Empty])
    5
    (Node [Empty 9 Empty])]))

;; Variants are closed by nature. You can't extend them. This is where
;; structural variants come into picture; they operate the same way
;; you would expect them to behave in OCaml. This is also powered using
;; row-polymorphism but extended to variants. They are open and can form
;; a structural union.
(type small { :A :B }) ; This is not row polymorphic.
(type large { :A :B :C (:D string) .. }) ; They can have payloads as usual.

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
(let (process-large item)) ; ERROR: small is not compatible with large.
(let (process-large (:> item large))) ; This works.
;; Type coercion is explicit in Miru where ":>" is the coercion special form.

;; The colors variant example but with structural variants:
(type colors
  { :White
    :Gray
    :Black
    (:RGB [int int int])
    (:HSL { h int, s int, l int }) })

;; Let's introduce GADTs. For this example, let's model an expresssion
;; evaluator.
(type (exp _) ; The type variable we'll specialize.
  ;; Notice the ":" after the constructor. You MUST specify the returning
  ;; type. Specialization is explicit.
  (Int     : int                   -> (exp int))
  (Bool    : bool                  -> (exp bool))
  (Add     : [(exp int) (exp int)] -> (exp int))
  (Is-zero : (exp int)             -> (exp bool)))

;; (type a) introduces a locally abstract type called "a." They are NOT
;; unification variables. A type variable is a flexible placeholder that can
;; unify with any type, while a locally abstract type creates a rigid, newly
;; minted type identity scoped strictly inside that function. They are what
;; enable local type refinement which is crucial to make GADTs work.
(val eval : (type a) . (exp a)
         -> a)
(let (rec eval) [e] ; The "rec" specifier is a property of the binding not type.
  ;; The abstract type "a" is refined in each branch independently.
  (match e
    (Int n)     n
    (Bool b)    b
    (Add [x y]) (+ (eval x) (eval y))
    (Is-zero x) (= (eval x) 0)))

(let safe-exp (Add (Int 5) (Int 10)))
(eval safe-exp) ; 15

(let bad-exp (Add (Int 5) (Bool true))) 
;;                        ^^^^^^^^^^^ Expected (exp int), got (exp bool)

;; It's about time we introduce algebraic effects. For example, we define a simple
;; effect with two distinct effect operations. There are different kinds of
;; effect operation types: direct operations, one-shot controls, non-resuming
;; operations, muli-shot controls and raw controls. The order is intentional.

(effect (state a)
  ;; These are examples of direct operations. They are used when you want to
  ;; perform an operation and return a value directly to the perform site while
  ;; having tail-resumption as a guarentee. They can resume exactly once and
  ;; have no access to a continuation because they do not allocate one! They
  ;; are read and typed exactly like normal functions.
  (val get : unit -> a) 
  (val set : a -> unit))

;; Now, we define a function that performs the state effect. Miru tracks the
;; set of effect types as effect rows. They support row-polymorphism.
(val increment-by : int
                 -> int / { (state int) .. })
(let increment-by [amount]
  (let current (get ()))
  (set (+ current amount))
  (get ()))

;; Now, let's write a handle for the function. It reduces the state effect
;; from the row using row variables.
(val run-state : int
              -> (unit -> int / { (state int) ..e })
              -> int / e)
(let run-state [init action]
  (let state (ref init))

  ;; with-expressions allow us to eliminate deeply nested code blocks caused
  ;; by trailing closures, etc. More concrete examples will follow soon.
  (with (handle
    (get _) !state
    (set x) (:= x state)))

  ;; We can call this function safely.
  (action ()))

;; #(...) are anonymous functions.
(let res (run-state 10 #(increment-by 5)))
(println f"{res}") ; 15

;; Control operations capture the delimited continuation at the perform site.
;; Unlike Koka, control operations default to one-shot resumptions: continuation
;; can be called at MOST ONCE (0 times to abort, or 1 time to resume).

;; Lets model interators by modeling the states.
(type (iterator a)
  (Done)
  (Next [a (unit -> (iterator a))]))

;; Now, a control operation to yield values.
(effect (yield a)
  (control yield : a -> unit))

;; Lets define the main iterate function.
(val iterate : (unit -> unit / { (yield a) ..e })
            -> (iterator a) / e)
(let iterate [action]
  (with (handle
    (return _) (Done)
    (yield x)  (Next [x #(resume ())])))
  (action ()))

;; And a function that produces some result.
;; NOTE: When sending the entire row, you don't need { ..<id> } and can
;; rather collapse it into an <id>.
(val run-print : (iterator int) / e
              -> unit / e)
(let run-print [iter]
  (match iter
    (Done) ()
    (Next [item next]) (begin (println f"Yielded: {item}")
                              (run-print (next ())))))

;; Build the iterator.
(let my-iterator
  (iterate #(begin
    (yield 1)
    (yield 2)
    (yield 3))))

;; And run it:
(run-print my-iterator)
;; Yielded: 1
;; Yielded: 2
;; Yielded: 3

;; A final control is explicitly non-resumptive; invoking resume inside its handle
;; causes a compile-time error. This allows the compiler to optimize the operation
;; as a non-local jump.

;; For example, we can model exceptions using final controls.
(effect (exn e)
  (final throw : e -> a))

(val parse-age : int
              -> int / { (exn string) })
(let parse-age [age]
  (if (< age 0)
    (throw "Age cannot be negative")
    age))

;; A simple example to turn exceptions into options.
(val run-exn : (unit -> a / { (exn string) ..e })
            -> (option a) / e)
(let run-exn [action]
  (with (throw err)
    (println f"Caught error: {err}")
    (None)) ; We cannot use resume here.
  
  (Some (action ())))

(let res1 (run-exn #(+ (parse-age -5) 100)))
(println f"{res1}") ; None

;; Multi-shot effects are opt-in at the effect level using the `multi` modifier.
;; Because multi-shot operations clone stack frames and data contexts to preserve 
;; purity across branches, marking the entire effect as `multi` signals to the compiler
;; that stack-cloning machinery is required.
(effect (multi amb)
  ;; Now this control has multi-shot capabilities.
  (control flip : unit -> bool))

;; Because it performs a multi-shot effect, this branch will evaluate and
;; return multiple times during handling.
(val choices : int
            -> int / { amb })
(let choices [x]
  (if (flip ())
    (+ x 10)
    (+ x 0)))

;; Handler for non-deterministic choice using `with`. Aditionally, handles handling any
;; effect can use a `return` clause (value clause) to wrap values if needed.
(val handle-amb : (unit -> a / { amb ..e })
               -> (list a) / e)
(let handle-amb [action]
  (with (handle
    (return v) :(v) ; Wrap the normal completion result in a list.
    (flip ())  (<> (resume true) (resume false)))) ; Combine the results of both forks.

  (action ()))

(let res (handle-amb #(choices 5)))
(println f"{res}") ; :(15 5)

;; Raw controls provide unmanaged, direct access to the raw underlying continuation 
;; fiber without automatically re-installing the enclosing handler scope upon resumption. 
;; This is the escape hatch used to implement low-level concurrency primitives, 
;; custom green-thread schedulers, or delimited control operators like shift/reset.
;; Let's reimplement the interate function from the "control" example:

;; Now, a control operation to yield values.
(effect (yield a)
  (raw yield : a -> unit))

(val iterate : (unit -> unit / { (yield a) ..e })
            -> (iterator a) / e)
(let iterate [action]
  (with (handle
    (return _) (Done)
    [(yield x) context] ; Raw controls pass their raw context.
      (Next [x #((.resume context) ())]))) ; You need to resume WITH the context.
  (action ()))

;; Raw controls do not automatically finalize the execution path. You have to take
;; the responsibility onto yourself i.e. ((.finalize context) ()). Raw controls
;; can be multi-shot but requires effect group annotation similar to controls. 

;; Let's take a bit of time to understand the with-expression. Here are some
;; cases. First is the case for a scoped resource manager.
(let count-steps [()]
  (scoped 0
    #(begin
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
      (begin
        (println f"{msg}")
        (resume ()))))

(emit "1st!")
(emit "2nd")

;; Would otherwise be something closer to:
(handle
  (emit msg)
    (begin
      (println f"{msg}")
      (resume ()))
  #(begin
    (emit "1st!")
    (emit "2nd"))) ; This will get very tedious with nested handles.

;; While algebraic effects track what a computation does downstream (outputs), 
;; Miru uses coeffects to track what a computation demands upstream (inputs). 
;; Instead of bubbling up to a handle, coeffects represent dynamic contexts 
;; injected down into the function before it can execute. 

;; Miru tracks (flat) coeffect rows using a backslash `\`. Just like effect, coeffects
;; also support row-polymorphism. Miru also implements structural coeffects; we will
;; even use them together later!
(val fetch-user-data : string \ { api-key : string, timeout : int, .. }
                    -> string)
(let fetch-user-data [user-id]
  (let key \api-key) ; \<token> is how you read from a (flat) coeffect.
  ;; You can always help the type system.
  (let (delay : int) \timeout) ; 'a -> int
  (format-to-string (f"https://api.example.com/{}?key={}&delay={}" user-id key delay)))

;; To discharge coeffects, we use a provide block instead of a handle block.
(let mock [action]
  (with (provide { api-key "KEY123", timeout 5000, .. }))
  (with (provide { timeout 10000, .. })) ; Shadows the timeout.
  (action ()))

(mock #(fetch-user-data "user_miru"))

;; It's nice to think it in terms of: you handle effects and provide contexts.
;; Effects capture dynamic control flow operations that bubble up the stack,
;; but are structurally wrong for passive requirements. Coeffects (flat) exist
;; to track the opposite direction: what a function demands down from its
;; environment before executing.

;; A flat coeffect tracks ambient environment requirements as a single, global record
;; shared across the entire computation, whereas a structural coeffect tracks resource
;; properties or usage constraints individually for each specific variable in the context.
;; So tracking properties like linearity, portability, contention, locality etc. are what
;; makes structural coeffects very powerful. Miru tracks structural coeffects very similar
;; to modaities found in OxCaml (Jane Street's Oxidized OCaml fork). Unlike flat coeffects,
;; structural coeffects do not make use of row-polymorphism but modality lattices.

;; The uniqueness axis: a value is either @unique (exactly one live
;; reference) or the default, shared.
(begin
  (let (x @ { unique }) "hello")
  (global-aliased-use x) ; x used as aliased i.e. uniqueness is lost.
  (unique-use x)) ; ERROR: x has already been aliased.

;; To solve this, we introduce borrowing: &<id>
(begin
  (let (x @ { unique }) "hello")
  (global-aliased-use &x) ; Temporarily alias x.
  (unique-use x)) ; x is still uniquely owned.

;; A borrowed value is aliased so it can't be passed where a unqiue value
;; is expected. It is also local, because it cannot escape the current
;; borrow region.

;; The original value is inferred as many for borrow to work i.e.
(let (x @ { once }) "hello")
(global-aliased-use &x) ; ERROR: x is once, must be many.

;; The locality axis: @local restricts a value to its enclosing scope,
;; forbidding it from escaping into a return value, a closure, or a heap
;; structure.
(val sum-pairs : (array int) @ { local }
              -> int)
(let sum-pairs [pairs]
  (reduce + 0 pairs)) ; fine: pairs never leaves this scope.

(val leak-pairs : (array int) @ { local }
               -> (array int)) 
(let leak-pairs [pairs]
  pairs) ; ERROR: @local value would escape via the return type.

;; You can always compose the modes e.g. value @ { local unique } and it
;; implements sub-moding.

;; To avoid the confusion of what "coeffects" mean, flat coeffects (\) are commonly
;; refered to as ambient contexts or just contexts while structural coeffects (@) are
;; effectively called modes in Miru.

;; Miru's procedural macros provide the same expression power as OCaml PPX
;; rewriters. Hence, they come with their own set of downsides: fragility,
;; hygiene and most importantly they are untyped. While they are very powerful
;; compiler extensions, a typed subset makes day-to-day utilities feel less like
;; a chore. Miru takes a lot of inspiration from MetaOCaml, Scala, Nim, MacoCaml
;; to implement expression values, and the two basic constructs to build them:
;; quoting and splicing.

;; These are just normal Miru functions that modify (expr 'a) just like any
;; other data structure.
(val unroll : int
           -> (expr int)
           -> (expr int))
(let (rec unroll) [n x] 
  (match n
    0 `1 ; This is quoting.
    1 x
    _ `(* $x $(unroll (- n 1) x)))) ; Both $(<token>) and $<token> are splices.

;; Miru implements multi-stage programming (MSP) such that quotes increment the stage while
;; splices decrement the stage; `(...) and $(...) are syntactic and are intertwined
;; with each other. There are two phasing bridges: (lift <x>) turns a stage-x value
;; into a stage-(x + 1) value i.e. 'a -> (expr 'a) while (lower <x>) evalues a stage-(x + 1)
;; value to produce a stage-x value i.e. (expr 'a) -> 'a.

;; `unroll` returns a value of type (expr int) thus, making it stage-1.
(let value (lower (unroll 4 `3))) ; `lower` drops it to stage-0 by evaluating it.

;; Rule of thumb: stage = count of `expr`.
;; e.g. (expr (expr (expr int))) is stage-3.

;; MSP is phase-agnostic i.e. you could expand the expressions either at compile-time or
;; at runtime. So, how do we drive the context? We divide it. `lower` lowers the expression
;; at runtime, while `realize` realizes the expression at compile-time. Both are a form of
;; "lowering" values.

(let value (realize (unroll 4 `3))) ; It will be realized at compile-time unlike `lower`.

;; This allows you to mix and match code that evalues at compile-time with code that should evaluate
;; at runtime. That said, there is a specific rule that must be followed: you can lower an expression
;; that realizes but not realize an expression that lowers at the same stage. The idea is rather simple:
;; `lower` waits till runtime to compile an expression while `realize` expects the expression to
;; evaluate entirely at compile-time.

;; Let's take this function for e.g.
(let illegal [quote]
  (let x (lower quote)) ; ERROR! Trying to lower and realize at the same stage is a violation!
  `x) ; This is the lift!

(realize (illegal `(+ 1 2)))

;; This on the other hand is fine!
(let legal [quote]
  `(lower $quote)) ; `lower` is at stage-(realize + 1), so it's allowed.

(realize (legal `(+ 1 2)))

;; This rule exists to preserve compile-time determinism while allowing users
;; to do so at runtime. To track this in the type-system Miru models capabilities
;; using it's powerful coeffect system. Additionally, realization is such a common
;; operation that Miru has a simple top-level reader for it which mirrors splicing:

$(legal `(+ 1 2))

;; Miru integrates SMT solvers to provide native support for Liquid Refinement
;; types! A rather common runtime check is array bounds but with liquid types,
;; you can prove that an index never leaves the array's bounds at compile-time!

;; Parameterizing length directly in the array type:
(val get-at : (arr : (array 'a))
           -> (i   : int | (&& (>= i 0) (< i (Array/length arr))))
           -> 'a)
;; Refinement uses the pipe (|) operator.
;; (Array/length arr) here works as a reflected measure! More on measures and
;; reflected functions later.

;; The compiler will ensure that 0 <= i < length(arr) always holds true.
(let get-at [arr i]
  ;; The refinement allows us to remove runtime checks from this get call!
  (Array/get arr i))

;; You can also move the inline predicates to predicate definations! Very similar to
;; LiquidHaskell's predicates.
(predicate in-bounds [i arr]
  (&& (>= i 0) (< i (Array/length arr))))

;; And use it in the predicate position:
(val get-at : (arr : (array 'a))
           -> (i   : int | (in-bounds i arr))
           -> 'a)

;; Contract-based specification literature often uses terms like "requires" to define
;; pre-conditions, "modifies" to track the set of plausibly mutable values, and "ensures"
;; to define post-conditions. Miru's SMT implementation tries to unify them under one
;; belt by taking advantage of what the type systems already provides:
;; 1) You can bind names to positional types, thus making them referenceable.
;; 2) Mutability being a property of the data-structure makes mutation sets inferable.
;; 3) Pre-conditions and post-conditions can be merged into a single expression.

;; A more thorough e.g. of merged conditions:
(val safe-div : (num   : int)
             ;; The merger simply dissolves into the "conditions that matter" for a type.
             -> (denom : int | (!= denom 0))
             -> (res   : int | (== (* res denom) num)))

;; NOTE: While allowed, non-linear arithmetic like x * y is undecidable, but you
;; can treat them as uninterpreted functions to modify the approach the solver
;; takes.

;; Let's talk about procedural macros. MSP handles most of the usecases one would like to
;; use macros for in languages like Rust but they can't extend the syntax of the language.
;; Macros-based reflection is also a great way to cover the grounds given Miru doesn't
;; provide any *intrinsic* support for reflection; neither static nor dynamic. The macro
;; model is very similar to Rust. Procedural macros can be of two forms: function-style
;; macros and attribute macros.

;; Example of a function-style macro that embeds an HTML-esque DSL:
(#html ; Macro invocation looks similar to functions but are prepended with a #!
  <html>
    <head>
      <title>{ "This is a new one!" }</title>
      ;; Comments are still comments but depends on the implementation!
      ;; Note, you use { ... } to embed Miru values, which is a good distinction.
    </head>
    <body>
      <button>{ "This button does nothing so far..." }</button>
    </body>
  </html>)

;; Example of an attribute macro that derives a modular implicit for a type:
#[(derive Show)]
(type colors
  (Red   int)
  (Green int)
  (Blue  int))

;; Other forms include:
#[shiny-macro]
#[(shiny-macro-with-payload ...)]
;; "..." has the same syntax freedom as (#<name> ...) which is passed as TokenStream.

;; These were the examples of outer attributes i.e. applied to the specific term
;; immediately following them. Miru has has inner attributes which are applied to the
;; module itself.

#![allow(dead-code)] ; You'll see them often when dealing with module level options.
```

TODO!
