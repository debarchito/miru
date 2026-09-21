> [!NOTE]
> This document outlines the language's design, feature sets, trade offs,
> soundness and related aspects. It aims to provide a detailed and unambiguous
> informal specification, serving as a reliable reference. It is an ongoing
> process, and nothing is finalized.

---

Miru is a strictly evaluated functional language designed to be a Lisp with ML
semantics. It aims to compose algebraic effects, co-effects, and liquid
refinement types orthogonally. Miru is designed to be pragmatic and useful for
day to day general purpose computing while retaining the necessary tools to
function as a strong scientific language.

### 1. Starting out with comments

The most common way to comment is prefixing a phrase with `;`. The number of `;`
characters changes the semantic meaning.

```clojure
; This is a comment, used for inline notes.
;; This is also a comment, used for standalone lines.
;;; This is a documentation comment, placed on top of expressions or declarations.

#! Hashbangs are also treated as comments. They are sementically the same as `;;`.
```

Miru has various built-in reader macros. One of them is `#_ <form>`, the discard
reader macro. It discards any form that immediately follows it, essentially
turning the form into an inplace comment.

```clojure
(+ 1 #_ 2 3) ; (+ 1 3)
```

To note, reader macros in Miru are not user extensible. Extensible reader macros
are an evergreen minefield of broken tooling that Miru aims to avoid. We'll look
into alternatives down the line.

### 2. Introduction to bindings

All bindings use the `let`-form; this includes named bindings (having arity = 0)
and function bindings (having arity >= 1). Bindings are immutable but
shadowable.

```clojure
(let name "Miru") ; This is a named binding.

;; This is a function binding with arity = 1.
(let greet [name] ; Arguments are passed in tuple form [<x> <y> ...].
  (String/concat "Hello, " name))

;; Now, we can call the function.
(greet name)
```

In this example, `String` is a module. `/` is the universal inspection operator
and `concat` is a function with arity = 2 defined inside the `String` module.
Note that all bindings and types in Miru follow the kebab-case convention; the
only exceptions include modules and type constructors which use
Header-kebab-case.

The type of the `greet` function is inferred as `string -> string`. We can also
use the `val`-form to define the type of a binding ourselves.

```clojure
(val greet : string -> string) ; `greet` is the name of the binding. The name is
                               ; seperated from the signature using the type
                               ; marker `:`. `->` is a mapping; it takes a
                               ; string as input and maps it to another string
                               ; as output.
```

Lets define another function; this time with more arguments and type it
ourselves.

```clojure
(val multiply : int -> int -> int) ; The signature is curried. The last type in
                                   ; the chain is the return type of the entire
                                   ; expression.
(let multiply [a b]
  (* a b)) ; The result of the last expression is automatically returned from
           ; this scope. No return keyword required.
```

Functions are first-class values and curried automatically.

```clojure
(let multiply-by-5 (multiply 5)) ; It wraps a lambda that expects the remaining
                                 ; arguments.
(multiply-by-5 10) ; 50
```

### 3. Strings and their forms

Before we starting printing values, we need to explore strings and their forms.

We start with standard strings and the ability to tag them. Tagged strings are
very useful when we want to avoid constant escaping. In this example, `(tag)"`
always closes with `"(tag)` rather han `"`. We can name tags just like bindings.

```clojure
;; Good ol' strings.
(let a "I'm a normal string")
(let b (tag)"I'm a tagged string"(tag))
```

Raw strings are also fully supported.

```clojure
(let c r"I'm a raw string\n") ; Raw strings do not evaluate escape sequences.
(let c r(tag)"I can also be tagged!"(tag)) ; Naturally, they can be tagged
                                           ; as well.
```

Format strings are special in that they aren't actually strings at all. They
allow interpolation and are desugared into GADT (Generalized Algebraic Data
Types) constructors, much like in OCaml. They retain the "string" designation
purely for convenience and similarity, though calling them formal constructors
is more precise. By default, interpolation uses `{...}` and lets us embed named
bindings directly. However, much like in Rust, it does not support embedding
arbitrary expressions.

```clojure
(let d "interpolate")
(let d f"I can {d} values!") ; I can interpolate values!
```

Alternatively, we can use the constructor form. Note that we cannot mix the
literal and constructor forms together. We will dive deeper into GADTs and ADTs
later.

```clojure
(let d (f"I can {} values!" d))
```

Format constructors also support chaining, which alter the interpolation
semantics accordingly.

```clojure
(let d (ff"I can {{}} values!" d)) ; `ff` shifts the interpolation target
                                   ; from {...} to {{...}}.
```

The rule of thumb follows a predictable pattern: `f -> {...}`, `ff -> {{...}}`,
`fff -> {{{...}}}`, or more generally, `f_n -> {_n ... }_n`.

Raw format constructors are available and support chaining as well.

```clojure
(let d (rff"I can {{}} values and raw literals like \n" d))
```

### 4. Printing with format constructors

Now, we've everything required to start printing values. Let's reimplement the
`greet` function to print the value directly rather than returning a string.

Functions must always return a value. If there is no meaningful value to return,
we return unit instead.

```clojure
(val greet : string -> unit)
(let greet [name]
  ;; "<>" is a semigroup append function. Since string concatenation forms a
  ;; free semigroup, it behaves the same as `String/concat`.
  (println (f"{}" (<> "Hello, " name))))
```

`println` always expects a format constructor; we can't pass a standard string
as its argument directly. To convert format strings into plain strings, we can
use the `String/from-format` function.

```clojure
(let to-embed "World")
(String/from-format f"Hello, {to-embed}!") ; Hello, World!
```

### 5. More on function bindings

Recursive functions need to be marked with a `rec` specifier. Specifiers are
special positional properties attached to names.

```clojure
(let (rec factorial) [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))
```

We can extend this naturally to mutually recursive functions.

```clojure
;; Ending names with `?` is a convention for boolean functions.
(let (rec is-even?) [n]
  (match n
    0 true
    n (is-odd? (- n 1))))

(let (rec is-odd?) [n]
  (match n
    0 false
    n (is-even? (- n 1))))
```

As stated before, function bindings must have arity >= 1. Some functions
naturally don't take any arguments, so we use the `unit` type for the first
argument, effectively calling the function only for its side effects.

```clojure
(let hello-world : unit -> string)
(let hello-world [()] ; () is the unit value.
  "Hello, World!")

;; This is how we call the function.
(hello-world ()) ; We must pass the unit value here as well.

;; The following snippet is invalid.
  (hello-world)
; ^^^^^^^^^^^^^ Syntax Error
```

If we want to alias a function, we do:

```clojure
(let aliased-hello-world hello-world)
```

Currying makes composition clean and natural. In this example, `:(...)` are
linked lists. We'll cover them later. `(* 2)` wraps a lambda that expects a
second argument.

```clojure
(let new-list (map (* 2) :(1 2 3 4))) ; :(2 4 6 8)
```

We can always define functions using lambdas and named bindings.

```clojure
(let square (fn [x] (* x x)))
;; or:
(let square #(* % %)) ; Special reader for lambdas.

(square 6) ; 36
```

Symbolic functions are valid too, although they must be defined inside `(...)`.

```clojure
(let (~/) [x] (/ 1.0 x))
(~/ 4.0) ; 0.25
```

### 6. Sequential scopes and parallel bindings

We can use the `begin`-form to introduce a new top-down sequential scope. The
`let`-form is also sequential but it requires an existing scope to bind to,
similar to `let ... in ...` in OCaml.

```clojure
(begin
  (let x 10)
  (let y 11)
  (+ x y)) ; 21
```

Parallel bindings can be introduced using product unpacking. Miru only allows us
to unpack product types (tuples and records) within the `let`-form because they
can be exhaustively unpacked using a single pattern. This doesn't hold for sum
types or arbitrary data structures like lists or arrays; the `match`-form is a
strictly better fit for those cases.

```clojure
(let [a b] [1.0 "Hello, World!"]) ; `a` and `b` are unaware of each other
                                  ; because unpacking is parallel by nature.
```

### 7. Data structures

#### 7.1. Tuples

Tuples are immutable, fixed-sized collections of heterogeneous elements. Tuples
are structural product types. We can use the same inspection operator `/` to
access the fields of a tuple.

```clojure
(let tup [1, 2.0 "Hello World"]) ; Commas are treated the same as whitespace.
(println (f"{}" tup/1)) ; 2.0
```

#### 7.2. Lists

Lists are dynamic, ordered, homogeneous singly-linked lists. Lists are
persistent data structures, meaning the data structure is immutable and always
preserves its previous versions when modified, relying heavily on structural
sharing to make copying efficient.

```clojure
(let lst :(1 2 3))
```

Lists do not provide language syntax for random access. However, we can always
use `List/nth`, though we should be aware of the pointer indirection cost. It
returns an `option` type.

```clojure
(println (f"{}" (List/nth 1 lst))) ; (Some 2)
```

Lists are intertwined with the cons function `::`. The following declaration is
semantically identical to the first:

```clojure
(let lst (:: 1 (:: 2 (:: 3 :()))))
```

We can always prepend more elements structurally.

```clojure
(let lst-new (:: 0 lst))
```

We can also use the `match`-form to deconstruct lists. More on `match`-forms
later.

```clojure
(match lst
  :() (println (f"The list is empty!"))
  (:: head _) (println (f"The first element is {head}")))
```

#### 7.3. Arrays

Arrays are fixed-sized, contiguous, homogeneous collections. Unlike in OCaml,
Miru arrays are immutable.

```clojure
(let arr [| 1 2 3 |])
```

Arrays fields can be accessed directly using the inspection range operator
`/[...]`.

```clojure
(println (f"{}" arr/[2])) ; 3
```

We can also use the `Array/nth-offset` function, which takes an offset and
returns an `option` type. Since arrays can be N-dimensional, a unified 1D-style
`Array/nth` does not exist. For a 1D array, the offset is equivalent to the
index.

```clojure
(println (f"{}" (Array/nth-offset 1 arr))) ; (Some 2)
```

As an array language, Miru has native support for N-dimensional arrays. Miru
uses column-major order while remaining 0-indexed. This is a departure from the
broader column-major world, which is typically 1-indexed, but it is an
intentional trade-off to stay closer to conventional systems semantics. N-D
arrays are special because they are not arrays of arrays (also known as jagged
arrays). Instead, elements are stored contiguously in memory and queried via
pre-calculated offsets.

```clojure
(let arr [| 1 4 7 |   ; Pipes are used to segment dimensions.
            2 5 8 |   ; Array dimension = (no. of consecutive pipes) + 1.
            3 6 9 |])
(println (f"{}" arr/[2 2])) ; 9
```

We can also use `Array/nth-offset` here, but the offset must be a pre-calculated
using the formula `offset = (column * height) + row`. For this example, our
offset is `(2 * 3) + 2 = 8`. This is precisely what the compiler computes for us
when we use the `/[...]` operator.

```clojure
(println (f"{}" (Array/nth-offset 8 arr))) ; (Some 9)
```

The aforementioned formula is only valid for 2D arrays. Because this operation
is very common, the helper function `Array/offset` makes things easier for us.

```clojure
(println (f"{}" (Array/nth-offset (Array/offset [| 2 2 |]) arr)))
```

#### 7.4. Mutable arrays

Mutable arrays are the mutable variant of arrays, allowing for in-place
mutation. In Miru, mutability is a property of data structures. Consequently,
Miru has no concept of a mutable pointer, though we will emulate one later.

```clojure
(let arr [! 1 2 3 !])

;; We can use the same `/[...]` operator.
(println (f"{}" arr/[2])) ; 3

;; or, use the `Mut-array/nth-offset` function directly for the 1D case.
(println (f"{}" (Mut-array/nth-offset 1 arr))) ; (Some 2)
```

Miru provides a universal mutating primitive, `<-`, that can be used to mutate
specific fields of mutable data structures in-place.

```clojure
;; `<-` is data last.
(<- 4 arr/[2])
(println (f"{}" arr/[2])) ; 4
```

Mutable arrays can also be N-dimensional.

```clojure
(let arr [! 1 4 7 |
            2 5 8 |
            3 6 9 !])
(println (f"{}" arr/[2 2])) ; 9

;; Let's mutate [2 2]!
(<- 10 arr/[2 2])

;; And use the `option` version instead. There is no separate `Mut-array/offset`.
(println (f"{}" (Mut-array/nth-offset (Array/offset [| 2 2 |]) arr))) ; (Some 10)
```

#### 7.5. Dynamic arrays

Dynamic arrays are the resizable version of mutable arrays, commonly referred to
as vectors in other languages. Unlike their fixed-size counterparts, dynamic
arrays are strictly 1-dimensional. Hence, there is no intrinsic way to build
dynamically dimension-reshaping arrays. Instead, you can use a 1D dynamic array
to handle runtime growth and then perform a zero-copy cast to a fixed N-D array,
provided the total element count matches the target shape.

```clojure
(let dyn-arr [~ 1 2 3 4 5 6 7 8 9 ~])
(println (f"{}" dyn-arr/[5])) ; 6

;; Push a new element to the dynamic array. Functions ending in `!` are in-place
;; mutating by convention.
(Dyn-array/push! 10 dyn-arr)

;; Pop elements as needed.
(Dyn-array/pop! dyn-arr)

;; No `nth-offset` here because dynamic arrays are always 1D.
(println (f"{}" (Dyn-array/nth 9 dyn-arr))) ; (Some 10)

(let arr (Array/from-dyn [| 3 3 |] dyn-arr)) ; Cast it into a 3x3 2D array.
```

#### 7.6. Views

Non-owning or borrowed views are as important as owning data containers. They
allow Miru to provide natural, non-copying slicing operations using strided
subsections. Let's explore the three view types Miru provides: `string-view`,
`array-view` and `mut-array-view` and their respective modules. Views are deeply
intertwined with modalities (an implementation of structural co-effects) and
borrowing, which we will explore in further detail later.

> [!NOTE]
> This section requires ironing out modalities and cross-mode interaction.

#### 7.7. Sets

Base provides five set variants: CHAMP sets, hash sets, sorted sets, ordered
sets, and bit sets. Let's take a brief look at them all at once.

```clojure
;; CHAMP sets are the default set implementation in Miru. They are immutable,
;; persistent, purely applicative, unordered, homogeneous collections that
;; enforce unique elements.
(Set/from-list :(1 2 3))

;; Hashsets are mutable, non-persistent, unordered (hash-based) linear
;; collections.
(Base/Collections/Hash-set/from-list :(1 2 3))

;; Sorted sets are immutable, persistent, value-ordered (Persistent B-Tree)
;; collections.
(Base/Collections/Sorted-set/from-list :(1 2 3))

;; Ordered sets are immutable, persistent, insertion-ordered (Linked CHAMP)
;; collections.
(Base/Collections/Ordered-set/from-list :(1 2 3))

;; Bit sets are mutable or unboxed, bitwise-packed sets of non-negative
;; integers.
(Base/Collections/Bit-set/from-list :(0 1 64 128))
```

#### 7.8. Maps

Base provides four map variants: CHAMP maps, hash maps, sorted maps, and ordered
maps. Let's take a brief look at them all at once.

```clojure
;; CHAMP maps are the default map implementation in Miru. They are immutable,
;; persistent, purely applicative, unordered, homogeneous key-value collections.
(Map/from-list :(["id" 1] ["id-2" 2])) ; List of 2-tuple (pair).

;; Hashmaps are mutable, non-persistent, unordered (hash-based) linear
;; key-value maps.
(Base/Collections/Hash-map/from-list :(["id" 1] ["id-2" 2]))

;; Sorted maps are immutable, persistent, value-ordered (Persistent B-Tree)
;; key-value maps. Orders entries by key comparison to enable range queries
;; and bounds slicing.
(Base/Collections/Sorted-map/from-list :(["id" 1] ["id-2" 2]))

;; Ordered maps are immutable, persistent, insertion-ordered (Linked CHAMP)
;; key-value maps.
(Base/Collections/Ordered-map/from-list :(["id" 1] ["id-2" 2]))
```

Mutable hash sets and hash maps can function as accumulators for the persistent
variants, much like dynamic arrays do for N-D arrays. However, unlike the
latter, converting between hash variants and persistent variants is not
zero-copy and will allocate due to layout differences.

#### 7.9. Records and Modules

Records are product types, just like tuples. They are nominal by default but can
be made structural to explicitly enable row-polymorphism.

```clojure
(type session
  { id : string, name : string }) ; The keys are untagged symbols.
```

The following will be inferred as `session`. We can use the inspection operator
`/` to access the fields of a record. Note that nominal types cannot have
anonymous definitions.

```clojure
(let s1 { id "MIRU", name "Miru Session" })
(println (f"{}" s1/id)) ; MIRU

(let s1 { id "MIRU", name "Miru Session", age 78 })
;;      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ERROR: Unbound record
```

To opt into structural typing, we can append the row operator `..`. This forces
the compiler to treat the record as an open, anonymous shape instead of binding
it to a primary nominal definition. The example below will be inferred
structurally as `{ id : string, name : string, .. }` rather than `session`.

```clojure
(let s2 { id "MIRU", name "Miru Session", .. })
```

You can cast a structural record to a nominal definition in case it respects the
field contracts.

```clojure
(val s2 : session)
(let s2 { id "MIRU", name "Miru Session", age 78, .. })
                                        ; ^^^^^^ this field is consumed by the
                                        ; `..` row operator during the cast to
                                        ; `session`.
```

After the cast, `s2` will behave just like any nominal `session` record. Extra
fields specified by the structural record that the nominal type doesn't include
become inaccessible:

```clojure
(println (f"{}" s2/id)) ; MIRU
(println (f"{}" s2/age))
                ;  ^^^ ERROR: Unbound field 'age'
```

This enables field-level row-polymorphism. For example, let's define a function
that takes any record containing an `id` field and prints it.

```clojure
(val print-id : { id : string, .. } -> unit)
(let print-id [record]
  (println (f"{}" record/id)))

;; Both of these work because they have an `id` field, despite `s1` being
;; nominal.
(print-id s1) ; MIRU
(print-id s2) ; MIRU
```

`..<name>` can be used when the row variable needs a specific name. In this
example, `r` is a unification variable rather than an abstract type. We'll look
into abstract types with greater detail in the later chapters.

```clojure
(val print-id : { id : string, ..r } -> unit)
```

f a record field shares the same name as a named binding, we can use the field
binding operator `~` to avoid redundant duplicates.

```clojure
(let id "value")
(let record { ~id, .. }) ; Identical to { id id, .. } i.e. { id "value", .. }.
```

When matching against a record, we can use the flat binding operator `<~` to
rebind field names.

```clojure
(let { field <~ id, .. } record)
(println f"{field}")
```

Records can have mutable fields using the `mut` specifier.

```clojure
(type person
  { name : string, (mut age) : int })
```

Field mutation uses the same mutating operator `<-`.

```clojure
(let p1 { name "John Doe", age 30 })
(<- 31 p1/age)
(println (f"{}" p1/age)) ; 31
```

We can use this property to build a reference cell around records to emulate
mutable names.

```clojure
(type (ref a) ; `a` is a type parameter. They are open to the outside world.
  { (mut contents) : a })

(let name (ref "Miru"))
(println (f"{}" name/contents)) ; Miru

(<- "MIRU" name/contents)
(println (f"{}" name/contents)) ; MIRU
```

This is a very useful construct, and Base provides it by default. Mutating and
dereferencing are common enough that Miru includes a built-in reader (`!<id>`)
for references and a symbolic function (`:=`) for mutation, similar to OCaml.

```clojure
(:= "Miru keeps changing." name)
(println (f"{}" !name)) ; Miru keeps changing.
```

The `:=` function is implemented as follows:

```clojure
(val (:=) : a -> (ref a) -> unit)
(let (:=) [value container]
  (<- value container/contents))
```

Structural records in particular have access to special `sig` and `struct`-forms
that make them much cleaner to write. Nominal records cannot be represented
using `sig` and `struct`-forms, as these forms are inherently open-ended. Let's
rewrite the `session` type structurally:

```clojure
(type session
  (sig
    (val id : string)
    (val name : string)))

(val first : session) ; Casting/specification is required as structural records
                      ; do not unify with nominal definitions automatically in
                      ; order to preserve decidable unification.
(let first
  (struct
    (let id "Miru")
    (let name "The first session")))

;; This is identical to literal structural records.
(type session
  { id : string, name : string, .. })

(val first : session)
(let first { id "Miru", name "The first session", .. })
```

Records can also hold arbitrary type witness or abstract types.

```clojure
(type ORD
  { (type t) . ; `.` sementically means `in`.
    compare : t -> t -> int })

;; or, using the `sig`-form.
(type ORD
  (sig
    (type t)
    (val compare : t -> t -> int)))
```

Fields are public by default, but we can take advantage of the row operator `..`
consuming unspecified fields to control visibility.

```clojure
(type session
  (sig
    (val greet : unit -> string)))

(val second : session)
(let second
  (struct
    ;; The `id` field is not accessible outside.
    (let id "Miru")
    (let greet [()]
      (println f"Hello, {id}!"))))

(second/greet ()) ; Hello Miru!
(println (f"{}" second/id))
;                      ^^ ERROR: Unbound field 'id'
```

Miru additionally provides an `exposes`-form to perform the same encapsulation
inside-out. This can be used inside both `sig` and `struct`-forms.

```clojure
(type session
  (sig
    ;; Defines two bindings but only exposes `greet`.
    (exposes greet)
    (val id : string)
    (val greet : unit -> string)))

(val second : session)
(let second
  (struct
    ;; The `id` field is still not accessible outside.
    (let id "Miru")
    (let greet [()]
      (println f"Hello, {id}!"))))

(second/greet ()) ; Hello Miru!
(println (f"{}" second/id))
;                      ^^ ERROR: Unbound field 'id'
```

The `exposes`-form reflects top-level definitions. This is what a module looks
like in Miru; they are, at their core, just structural records coupled with an
additional ability to control encapsulation inside-out.

> [!NOTE]
> The section below is yet to be serialized properly.

```clojure
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
    (println (f"Got: {} * {} * {}" t/0 t/1 t/2))

  (HSL r)
    (println (f"Got: {{ h {}, s {}, l {} }}" r/h r/s r/l))
    ;;               ^        <->        ^ {{ or }} to escape interpolation.
    ;; or just:
    (println (ff"Got: { h {{}}, s {{}}, l {{}} }" r/h r/s r/l)))
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

;; Lets build a tree for an example.
(type (tree a)
  Empty
  (Node [(tree a) a (tree a)]))

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
;; (as ...) is an alias of (:> ...).

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
(val eval : (type a) . (exp a) -> a)
(let (rec eval) [e] ; The "rec" specifier is a property of the binding not type.
  ;; The abstract type "a" is refined in each branch independently.
  (match e
    (Int n)     n
    (Bool b)    b
    (Add [x y]) (+ (eval x) (eval y))
    (Is-zero x) (= (eval x) 0)))

;; Now, we can introduce keyword aliases. Some forms in the type spec can be written
;; more naturally if you want to:
(val eval : (type a) in (exp a) -> a) ; Makes it easy to read!

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
(val increment-by : int -> int ! { (state int) .. })
(let increment-by [amount]
  (let current (get ()))
  (set (+ current amount))
  (get ()))

;; "!" has a keyword alias too in case you like this better.
(val increment-by : int -> int performs { (state int) .. })

;; Now, let's write a handle for the function. It reduces the state effect
;; from the row using row variables.
(val run-state : int -> (unit -> int ! { (state int) ..e }) -> int ! e)
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
(val iterate : (unit -> unit ! { (yield a) ..e }) -> (iterator a) ! e)
(let iterate [action]
  (with (handle
    (return _) (Done)
    (yield x)  (Next [x #(resume ())])))
  (action ()))

;; And a function that produces some result.
;; NOTE: When sending the entire row, you don't need { ..<id> } and can
;; rather collapse it into an <id>.
(val run-print : (iterator int) ! e -> unit ! e)
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

(val parse-age : int -> int ! { (exn string) })
(let parse-age [age]
  (if (< age 0)
    (throw "Age cannot be negative")
    age))

;; A simple example to turn exceptions into options.
(val run-exn : (unit -> a ! { (exn string) ..e }) -> (option a) ! e)
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
(val choices : int -> int ! { amb })
(let choices [x]
  (if (flip ())
    (+ x 10)
    (+ x 0)))

;; Handler for non-deterministic choice using `with`. Aditionally, handles handling any
;; effect can use a `return` clause (value clause) to wrap values if needed.
(val handle-amb : (unit -> a ! { amb ..e }) -> (list a) ! e)
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

(val iterate : (unit -> unit ! { (yield a) ..e })
            -> (iterator a)  ! e)
(let iterate [action]
  (with (handle
    (return _) (Done)
    [(yield x) context] ; Raw controls pass their raw context.
      (Next [x #(context/resume ())]))) ; You need to resume FROM the context.
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

;; Miru implement two forms of coeffects: flat (contexts) and structural (modes).
;; A flat coeffect tracks ambient environment requirements as a single, global record
;; shared across the entire computation, whereas a structural coeffect tracks resource
;; properties or usage constraints individually for each specific variable in the context.
;; So tracking properties like linearity, portability, contention, locality etc. are what
;; makes structural coeffects very powerful. Miru tracks structural coeffects very similar
;; to modaities found in OxCaml (Jane Street's Oxidized OCaml fork). Unlike flat coeffects,
;; structural coeffects do not make use of row-polymorphism but modality lattices.

;; Contexts are intertwined with the "module" system which in turn surface as modular implicits
;; and explicits. Let's look at an example by defining a "module" type.

;; Module types are record types. By convention, they are always in UPPERCASE.
(type ORD
  { (type t) . ; You can define abstract types here and use them in the record body.
    compare : t -> t -> int, .. }) ; They need to be structural to enable subtyping.

;; Let's write a storing function.
(val sort-generic : (type t) . (t -> t -> bool) -> (list t) -> (list t))
(let sort-generic [compare lst]
  (let (rec insert) [x xs]
    (match xs
      :()       :(x)
      (:: y ys) (if (compare x y)
                  (:: x (:: y ys))
                  (:: y (insert x ys)))))
  (foldr insert :() lst))

;; Functors are just normal functions. Notice the sorting interface is stuctural.
;; But you could make it a seperate type too. By conventions, modules and functors
;; are Header-cased.
(val Make-sorter : ORD -> { (type t) . sort : (list t) -> (list t), .. })
(let Make-sorter [M]
  { (type t = M/t) .
    sort #(sort-generic M/compare %), .. })

;; Let's create our "modules".
(let Int-asc { (type t = int) .
               compare #(<= %1 %2) })

(let Int-desc { (type t = int) .
               compare #(>= %1 %2) })

;; And now, we can use the functor.
(let Int-asc-sorter (Make-sorter Int-asc))
(let Int-desc-sorter (Make-sorter Int-desc))

;; Functors are applicative by default similar to OCaml. Thus Miru also inherits
;; OCaml's convention of using unit to define generative functors syntactically.
;; This is less about sementic clarity and more about a pragmatic middle ground.
(val Make-sorter-gen : ORD -> unit -> { (type t) . sort : (list t) -> (list t), .. })
(let Make-sorter-gen [M ()]
  { (type t = M/t) .
    sort #(sort-generic M/compare %), .. })

;; Now, we can use our new functor. Unlike OCaml, Miru doesn't force you to curry
;; the unit call because functors are normal functions. The type t is minted uniquely
;; for each call making them different hence generative.
(let Int-asc-sorter-gen (Make-sorter-gen Int-asc)) ; Curried!
(let One (Int-asc-sorter-gen ()))
(let Two (Int-asc-sorter-gen ())) ; One and Two are not equivalent.

;; We define a type the context needs to supply.
(type SHOW
  { (type t) .
    show : t -> string, .. })

;; Miru tracks contexts using a question `?`. Just like effect, contexts
;; support row-polymorphism. We provide a name to the context payload
;; (which is a module in this case) using <~.
(val print-blank : S/t ? { S <~ SHOW .. } -> unit)
(let print-blank [x]
  (let S ?S) ; ?<id> is how you read from the context row.
  (println (f"{}" (S/show x))))

;; You could also write the signature as:
(val print-blank : (type a) .
                   a ? { S <~ (SHOW ~> (type t = a)) .. } -> unit)
;; <~ is formally called a flat binding while ~> is called a structural binding.

;; Similar to effects, coeffects also have keyword aliases.
(val print-blank : (type a) in
                   a demands { S as (SHOW with (type t = a)) .. } -> unit)
;; To note, these keyword aliases are no way related to the (<keyword> ...)
;; forms if any.

;; Let's implement a module for integers first.
(let Show-int { (type t = int) .
                show #(Int/to-string %) })

;; It naturally can also be written as:
(let Show-int { (type t = int) in
                show #(Int/to-string %) })

;; And another for lists, using a functor.
(val Show-list : SHOW -> SHOW)
(let Show-list [S]
  { (type t = (list S/t)) .
    show #(format-to-string (f"list({})" (join " " (map S/show %)))) })

;; This is how you would provide them when named:
(with (provide { S <~ Show-int }))
(print-blank 4) ; 4

(with (provide { S <~ (Show-list Show-int) }))
(print-blank :(1 2 3)) ; list(1 2 3)

;; You can actually skip the name too, and it will try to resolve using
;; type-direction!
(with (provide { (Show-list Show-int) }))
(print-blank :(1 2 3)) ; list(1 2 3)

;; Named contexts are useful when you have numerous contexts of the same type in demand.
;; Miru prefers explicit resolution but that doesn't mean implicit resolution is not
;; supported. Use them wisely and partly for trivial purposes.

;; Mark the type as implicit.
(val print-blank : S/t ? { S <~ (implicit SHOW) .. } -> unit)
(let print-blank [x]
  (println (f"{}" (?S/show x)))) ; You can also use ?<id> directly.

;; Now, the compiler will perform scope resolution for you.
(print-blank 4) ; 4
(print-blank :(1 2 3)) ; list(1 2 3)

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
(val sum-pairs : (array int) @ { local } -> int)
(let sum-pairs [pairs]
  (reduce + 0 pairs)) ; fine: pairs never leaves this scope.

(val leak-pairs : (array int) @ { local } -> (array int)) 
(let leak-pairs [pairs]
  pairs) ; ERROR: @local value would escape via the return type.

;; You can always compose the modes e.g. value @ { local unique } and it
;; implements sub-moding.

;; Moding also has an keyword alias.
(val leak-pairs : (array int) is { local } -> (array int)) 

;; To avoid the confusion of what "coeffects" mean, flat coeffects (?) are commonly
;; refered to as ambient contexts or just contexts while structural coeffects (@) are
;; effectively called modes in Miru.

;; Miru's procedural macros provide the same expression power as OCaml PPX
;; rewriters. Hence, they come with their own set of downsides: fragility,
;; hygiene and most importantly they are untyped. While they are very powerful
;; compiler extensions, a typed subset makes day-to-day utilities feel less like
;; a chore. Miru takes a lot of inspiration from MetaOCaml, Scala, Nim, MacoCaml
;; to implement expression values, and the two basic constructs to build them:
;; quoting and splicing.

;; These are just normal Miru functions that modify (expr a) just like any
;; other data structure.
(val unroll : int -> (expr int) -> (expr int))
(let (rec unroll) [n x] 
  (match n
    0 `1 ; This is quoting.
    1 x
    _ `(* $x $(unroll (- n 1) x)))) ; Both $(<token>) and $<token> are splices.

;; Miru implements multi-stage programming (MSP) such that quotes increment the stage while
;; splices decrement the stage; `(...) and $(...) are syntactic and are intertwined
;; with each other. There are two phasing bridges: (lift <x>) turns a stage-x value
;; into a stage-(x + 1) value i.e. a -> (expr a) while (lower <x>) evalues a stage-(x + 1)
;; value to produce a stage-x value i.e. (expr a) -> a.

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
(val get-at : (arr : (array a))
           -> (i   : int | (&& (>= i 0) (< i (Array/length arr))))
           -> a)
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
(val get-at : (arr : (array a))
           -> (i   : int | (in-bounds i arr))
           -> a)

;; Additionally, there is a keyword alias too.
(val get-at : (arr : (array a))
           -> (i   : int where (in-bounds i arr))
           -> a)

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
