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

;; You can specify the types explicitly if you want.
;; The type unit is special because Miru doesn't have an equivalent of nil as
;; a primitive.
;; Additionally, like most functional languages Miru lacks procedures. Every
;; function must return something even if it's an unit.
(let greet [name : string] : unit
  ;; "<>" is a semigroup append operator.
  ;; Since string concatenation forms a free semigroup, it behaves the same
  ;; as String/concat!
  (println (<> "Hello, " name)))

;; You can also separate the type definition into a (sig ...) expression.
;; The type signature are written in curried form.
;; Type signatures use infix forms which is how you would define them
;; in mathematics.
(sig greet : string -> unit)
(let greet [name]
  ;; "println" is not a function but a macro!
  ;; Modular implicits allow locally-resolved typeclass-like features.
  ;; More on them later.
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
;; let uses sequential binding, similar to let* in Scheme.
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
(let [x y z] [1 2.3 "hello!"])
(print x) ; 1
(print y) ; 2.3
(print z) ; hello!
;; Almost all data structures can be destuctured!

;; Since functions are first-class you can always use lambdas.
(let square (fn [x] (* x x)))

;; Symbolic functions are completely valid!
(let ~/ [x] (/ 1.0 x))
(~/ 4.0) ; 0.25

;; Infact you can also do:
(print "{}" ~/4.0) ; Symbolic functions with one arguments can be
                   ; directly prefixed!

;; Miru has a lot of data structures. Let's take a look at some of them:

;; Tuples are immutable, fixed-sized collections of heterogeneous elements.
;; Tuples are both persistent and a product type!
[ 1, 2.0 "Hello World" ] ; commas are the same as whitespace.

;; Lists are dynamic, ordered, homogeneous singly linked lists.
;; Lists are persistent data structures.
[> 1 2 3 >]

;; Arrays are fixed-sized, contiguous, homogeneous collections.
;; Unlike OCaml, Miru arrays are immutable.
[| 1 2 3 |]

;; Mutable arrays are the mutable version of arrays.
;; In Miru, mutability is a property of data structures. Thus, Miru has no
;; concept of a mutable pointer.
[! 1 2 3 !]

;; Dynamic arrays are the resizable version of mutable arrays.
;; They are also known as vectors in other languages.
[~ 1 2 3 ~]

;; Miru is also an array language, which means it has native support for
;; N-dimentional tensors, both immutable and mutable.
;; Miru is column-major and 0-indexed.
[| 1 4 7 |  ; Pipes to used to segment dimensions.
   2 5 8 |  ; Rule of thumb: tensor dimension = (no. of pipes) + 1
   3 6 9 |] ; This is 3x3 matrix!

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
;; making them ideal for linear algebra!

;; Unlike the fixed variants, dynamic arrays are strictly 1-dimentional.
;; Hence, there is no *intrinsic* way to build dynamic dimention-reshaping
;; tensors. Instead, you can use a 1D dynamic array ([~ ... ~]) to handle
;; runtime growth/dynamism, and then perform a zero-copy (!!) cast into a
;; fixed N-dimensional tensor as long as the total element count matches
;; the target shape!

;; Sets are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous collections that enforce unique elements. Uses list delimiters
;; [> ... >] in the reader phase to signal a heap-allocated tree layout.
#set [> 1 2 3 >] ; #set is a tagged template reader! More on them later.
;; or
(Std/Collections/Set/from-array [| 1 2 3 |])

;; Hashsets are mutable, non-persistent, unordered (hash-based) linear
;; collections. Uses flat vector delimiters [| ... |] to signify a contiguous
;; memory layout (Swiss Table!).
#hash-set [| 1 2 3 |]
;; or
(Std/Collections/Set/Hash/from-array [| 1 2 3 |])

;; Sorted sets are immutable, persistent, value-ordered (Persistent B-Tree)
;; collections.
#sorted-set [> 1 2 3 >]
;; or
(Std/Collections/Set/Sorted/from-array [| 1 2 3 |])

;; Ordered sets are immutable, persistent, insertion-ordered (Linked CHAMP)
;; collections.
#ordered-set [> 1 2 3 >]
;; or
(Std/Collections/Set/Ordered/from-array [| 1 2 3 |])

;; Bit sets are mutable or unboxed, bitwise-packed sets of non-negative
;; integers.
#bit-set [| 0 1 64 128 |]
;; or
(Std/Collections/Set/Bit/from-array [| 0 1 64 128 |])

;; Maps are immutable, persistent, purely applicative, unordered (CHAMP),
;; homogeneous key-value collections.
#map { id 1 } ; Borrows the struct body form.
;; or
(Std/Collections/Map/from-array [| ["id" 1] |])

;; Hashmaps are mutable, non-persistent, unordered (hash-based) linear
;; key-value maps.
#hash-map { id 1 }
;; or
(Std/Collections/Map/Hash/from-array [| ["id" 1] |])

;; Sorted maps are immutable, persistent, value-ordered (Persistent B-Tree)
;; key-value maps. Orders entries by key comparison to enable range queries
;; and bounds slicing.
#sorted-map { id 1 }
;; or
(Std/Collections/Map/Sorted/from-array [| ["id" 1] |])

;; Ordered maps are immutable, persistent, insertion-ordered (Linked CHAMP)
;; key-value maps.
#ordered-map { id 1 }
;; or
(Std/Collections/Map/Ordered/from-array [| ["id" 1] |])

;; The mutable hash-sets and hash-maps function as accumulators for the
;; persistent variants just like dynamic arrays function for tensors. That
;; said, unlike dynamic arrays <-> tensors, hash-* <-> persisted-* is NOT
;; zero-copy and will allocate due to layout differences.

;; Records are product types just like tuples. They are nominal by default but
;; can be made structural to explicitly enable row polymorphism.
(type session
  { id   : string
    name : string }) ; the keys are untagged symbols!

;; This will be inferred as session. Anonymous definitions are illegal due
;; to the fundamental limitations of a nominal type.
(let s1 { id "MIRU" name "Miru Session" })

;; To opt into structural typing, append the row operator `| <row-variable>`.
;; This forces the compiler to treat the record as an open, anonymous shape
;; instead of binding it to a nominal definition.
(let s2 { id "MIRU" name "Miru Session" | _ }) ; "_" is an ignored row variable.

;; This enables a powerful feature called field-level row-polymorphism.
;; For example, let's define a function to print the id of a session.
;; We'll take any record as input that has an "id" field.
(sig print-id : { id : string | _ } -> unit)
(let print-id [record]
  (println (.id record))) ; Nominal types can seamlessly fit here!

;; Both of these work!
(print-id s1) ; s1 is nominal.
(print-id s2) ; s2 is structural.

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
(.age! 31 p1) ; an special setter is generated with a "!" suffix to allow mutation.
;; This is also valid. Fully qualified setters are easier to optimize since the
;; nominal type is known before-hand.
(person.age! 31 p1)

;; These setters boil down to a "<-" (mutating) primitive operation.
;; All these operations are data-last.
(<- person.age 31 p1)

;; We can use this property to build a ref cell around records.
(type (ref a) ; "a" is a type variable.
  { (mut contents) : a })

;; We can use ref cells to simulate mutable bindings.
(let name (ref "Miru"))
(println name.contents) ; Miru

(ref.contents! "MIRU" name)
(println name.contents) ; MIRU

(<- ref.contents "MirU" name)
(println name.contents) ; MirU

;; This is a very useful construct and the stdlib will provide it by default.
;; Mutating and de-referencing is common enough that Miru has a built-in
;; functions for references, and a symbolic function for mutation.
(@<- "Miru" name)
(println @name) ; Miru

;; The "@<-" function is implemented as follows:
(sig (@<- a) : a -> (ref a) -> unit)
(let @<- [value container]
  (<- ref.contents value container))

;; We can also use the type expression to define sum or variant types.
;; '<id> is reserved for type variables in Miru not quoting.
;; Infact, Miru only supports *typed* quasi-quoting using `(...) which
;; evaluate to an (expr 't) data-structure. More on them later!
(type shape
  (Circle    : { radius : float | 'r1 }) ; Variant constructors must be capitalized!
  (Rectangle : { width : float, height : float | 'r2 })) ;
  ;; To note, 'r1 and 'r2 are type variables and they are differentt from
  ;; locally abstract types, which we'll discuss below.

(let [basic-circle { radius 5.0 | _ }
      fancy-circle { radius 10.0 color "red" | _ }
      shape-1 (Circle basic-circle)
      shape-2 (Circle fancy-circle)]) ; Both are valid!

;; Let's look at more examples of variant types:
(type colors
  (White)
  Gray ; Parens are optional for constructors with no payload.
  (Black)
  (RGB : [int int int]) ; Tuple variants are also allowed!
  (HSL : { h int, s int, l int })) ; Record variants as usual.

(let a White)
(let b (colors.Gray)) ; You can namespace them!
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
;; Types also require the "rec" specifier. Implicit recursion is not allowed.
(and
  (type (rec expression)
    (Literal  : int)
    (Variable : string)
    (Block    : (list statement)))
  (type (rec statement)
    (Assignment      : [string expression])
    (If-then-else    : [expression statement statement])
    (Void-expression : expression)))

;; Let's build a tree for an example! "a" here is again a type variable.
(type (tree 'a)
  Empty
  (Node : [(tree 'a) 'a (tree 'a)]))

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
(type small < :A :B >) ; < ... > are rows!
(type large < :A :B :C (:D string) | _ >) ; They can have payloads!

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
    (:RGB : [int int int])
    (:HSL : { h int, s int, l int }) >)

;; Time to introduce GADTs!
;; For this e.g., let's model an expresssion evaluator.
(type (exp _) ; The type variable we'll specialize.
  ; You MUST specify the returning type. Specialization is explicit!
  (Int     : int                   -> (exp int))
  (Bool    : bool                  -> (exp bool))
  (Add     : [(exp int) (exp int)] -> (exp int))
  (Is-zero : (exp int)             -> (exp bool)))

;; (type a) introduces a locally abstract type called "a." They are NOT
;; type variables! A type variable is a flexible placeholder that can unify
;; with any type, while a locally abstract type creates a rigid, newly
;; minted type identity scoped strictly inside that function. They are what
;; enable local type refinement which is crucial to make GADTs work!
(sig eval : (type a) . (exp a) -> a)
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

;; Let me introduce you the crown jewel: effects.
;; We define a simple effect with two distinct effect operations.
(effect console
  ;; Return types NOT encoded; they are not "normal" functions.
  (Read  : unit -> string) 
  (Write : string -> unit))

;; Now, we define a function that performs the Console effect.
;; Miru tracks the set of effect types as effect rows.
;; | _ is required to keep the function open to composition.
(sig prompt-user : string -> string / <console | _>)
(let prompt-user [msg]
  ;; Effect calls look like function calls.
  (Write msg)
  (console.Read ())) ; You can also namespace them.
  ;; They look very similar to ADTs, right? Exactly! They are
  ;; internally powered by GADTs but lifted as a distinct language
  ;; feature for deeper syntactic and sementic integration.

;; Now, let's write a handler for the function.
;; It reduces the Console effect from the row!
(sig mock-console : (unit -> string / <console | 'e>) -> string / <'e>)
(let mock-console [action]
  (handle (action ())
    ;; Tuples are commonly used for pairs.
    [(Write msg) k] ; k is the captured continuation!
       (block
         (println (String/concat "[WRITE]: " msg))
         (resume k ())) ; Resume the continuation!
    [(Read ()) k]
       (resume k "Hello from the handler!")))

;; #(...) are anonymous functions.
(let res (mock-console #(prompt-user "Enter command")))
(println res)

;; Miru effects are stackful and one-shot by default. It covers almost all
;; of the cases you'd use effects for. However, there are scenarios where
;; stackless state machines are inherently more efficient. I might consider
;; a special compiler tag to opt-into stack lifting in the future.

;; Multi-shot effects are opt-in and are always stackful due to their nature.
(effect (multi amb) ; Mark the effect using "multi" specifier.
  ((control Flip) : unit -> bool))
  ; You use the "control" specifier to make this operation multi-shot.

;; Let's look at a function that takes a number and adds either 10 or 0
;; depending on the flip.
;; Because it is multi-shot, this function will internally return *twice*.
(sig choices : int -> int / <amb | _>)
(let choices [x]
  (if (Flip ())
    (+ x 10)
    (+ x 0)))

(sig handle-amb : (unit -> 'a / <amb | 'e>) -> (list 'a) / <'e>)
(let handle-amb [action]
  (handle (action ())
    ;; Wrap the normal completion result in a list. This is special, and alse
    ;; known as the value clause.
    (Return v) [> v >]
    ;; Unlike Koka, you don't need to tell handler than Flip is a "control".
    ;; The compiler can inspect the signature either way.
    [(Flip ()) k]
      ;; Combine the results of both.
      (<> (resume k true) (resume k false))))

(let res (handle-amb #(choices 5)))
(println res) ; [> 15 5 >]

;; While algebraic effects track what a computation does downstream (outputs), 
;; Miru uses coeffects to track what a computation demands upstream (inputs). 
;; Instead of bubbling up to a handler, coeffects represent dynamic contexts 
;; injected down into the function before it can execute. We define them 
;; using the "context" keyword.
(context config
  ;; These are lowercased because contexts/coeffects are represented internally
  ;; as a struct with function fields just like how effects are modeled as GADTs
  ;; with constructor fields. It makes it consistent with their internal
  ;; represenation.
  (api-key : string) ; Return types NOT encoded; they are not "normal" functions.
  (timeout : int))

;; Miru tracks coeffect rows using a backslash `\`. 
;; Just like effect, coeffects also support row-polymorphism.
(sig fetch-user-data : string \ <config | _> -> string)
(let fetch-user-data [user-id]
  ;; We extract values from the context.
  (let key (api-key ()))
  (let delay (timeout ()))
  ;; IMAGINE a fetch function exists!
  (fetch (format "https://api.example.com/{}?key={}&delay={}" user-id key delay)))

;; To discharge coeffects, we use a provider block instead of a handler block.
;; The "provide" keyword injects values downward, reducing "config" from the row!
(sig with-mock-config : (unit \ <config | _> -> 'a) -> 'a)
(let with-mock-config [action]
  (provide
    ;; Provide the contexts! It looks like a function call but are not "normal" functions.
    (api-key "top-secret-key!!!")
    (timeout 5000)
    ;; Now use these contexts!
    (action ())))

(with-mock-config #(fetch-user-data "user_miru")) ; Simple as that!

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

;; These are just normal Miru functions that modify (expr a) just like any
;; other data structure! It is also known as multi-stage expansion.
(sig unroll : int -> expr int -> expr int)
(let (rec unroll) [n x] 
  (match n
    0 `1 ; Quoting!
    1 x
    _ `(* $x $(unroll (-n 1) x)))) ; Splicing values in place!

;; (expand ...) is a special form that runs ANY arbitrary computation at
;; compile time!
(let value (expand (unroll 4 `3))) ; (* 3 (* 3 (* 3 (* 3 1))))
```

TODO!
