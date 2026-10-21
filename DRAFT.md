> [!NOTE] This document outlines the language's design, feature sets, trade
> offs, soundness and related aspects. It aims to provide a detailed and
> unambiguous informal specification, serving as a reliable reference. It is an
> ongoing process, and nothing is finalized.

______________________________________________________________________

Miru is a strictly evaluated functional language designed to be a Lisp-like with
ML semantics. It aims to compose algebraic effects, co-effects, and liquid
refinement types orthogonally. Miru is designed to be pragmatic and useful for
day to day general purpose computing while retaining the necessary tools to
function as a strong scientific language.

### 1. Starting out with comments

The most common way to comment is prefixing a phrase with `;`. The number of `;`
characters changes the semantic meaning.

```clojure
; This is a comment, used for inline or internal notes.
;; This is also a comment, used for standalone lines.
;;; This is a documentation comment, placed on top of expressions or declarations.

#! Hashbangs are also treated as comments. They are semantically the same as `;;`.
```

Miru has various built-in reader macros. One of them is the discard reader form
`#_ <form>`, that discards any form that immediately follows it, essentially
turning the form into an inplace comment. An indentation delimiter between the
reader macro and the form is only required when the first token of the form is a
valid identifier.

```clojure
(+ 1 #_ 2 3) ; (+ 1 3)
(+ 1 #_2 3)
;;   ^^^ ERROR: Unbounded reader macro `_2`
(+ 1 #_(+ 1 1) 3) ; (+ 1 3)
                  ; It works because `(` is not a valid identifier.
```

To note, reader macros in Miru are not user extensible. Extensible reader macros
are an evergreen minefield of broken tooling that Miru aims to avoid. We'll look
into alternatives down the line.

### 2. Within Bindings

#### 2.1. The `val`-form

All bindings use the `val`-form. This includes nullary (arity = 0) named
bindings and fixed-arity (arity >= 1) function bindings. Bindings are the
fundamental value units (hence `val`) in Miru. They are immutable and
sequential.

```clojure
(val name "Miru") ; This is a named binding.

;; This is a unary (arity = 1) function binding.
(val greet [name] ; Arguments are passed in tuple form [<x> <y> ...].
  (String/concat "\s" '("Hello" name))) ; '(...) is a list at all times
                                        ; NOT a quotation.
;; Now, we can apply the function.
(greet name) ; Hello Miru
```

In this example, `String` is a module, `/` is the universal inspection operator,
and `concat` is a binary (arity = 2) function defined inside the `String`
module. Note that all bindings and types in Miru follow the kebab-case
convention; the only exceptions include modules and type constructors which use
Header-kebab-case.

Bindings being sequential make shadowing an intrinsic property. In fact, a
binding of arbitrary arity can be shadowed by another binding of the same name,
regardless of its arity.

```clojure
(val x 10)

;; Evalutes `x` to 10 and binds the new `x` to 30.
(val x (+ x 20))

;; This example shadows `x` with a binary function binding. A function binding
;; is a lambda bound to a named binding, hence its semantics.
(val x [y z]
  ; `x` inside the body refers to the outer named binding returning `30`.
  ; Functions are non-recursive by default to preserve the sequential semantics;
  ; if `x` wasn't defined in the immediate parent scope, this would fail to
  ; compile.
  (+ x (* y z))) 

;; Applying the new function.
(x 2 3) ; (+ 30 (* 2 3)) = 36
```

#### 2.2. Sequential scopes and parallel bindings

`val`-form is sequential but requires an existing scope to bind to. In such
cases, we can use the `begin`-form to introduce a new top-down sequential scope.

```clojure
(begin
  (val x 10)
  (val y 11)
  (+ x y)) ; 21
```

Parallel bindings can be introduced using two ways: product unpacking and the
`and`-form.

Miru only allows us to unpack product types (tuples and records) within the
`val`-form because they can be unpacked using a single exhaustive pattern. This
doesn't hold for sum types or arbitrary data structures like lists or arrays;
the `match`-form is a strictly better fit for those cases.

```clojure
(let [a b] [1.0 "Hello, World!"]) ; `a` and `b` are unaware of each other
                                  ; because unpacking is parallel in nature.
```

The `and`-form allows us to introduce multiple distinct bindings simultaneously.
All expressions in a binding chain are evaluated in parallel within the parent
scope before any new symbols are bound.

```clojure
(val y 39)
(and x (+ y 1))
;;        ^ ERROR: Unbound binding `y`
;; The expressions are evaluated simultaneously in the parent scope; `x` can't
;; look ahead to read the parallel binding of `y`.
```

This is an intentional departure from traditional Lisp semantics, choosing
instead to align with the binding behavior of ML languages.

Simultaneous evaluation makes `and`-form required for handling mutual recursion.
When function bindings are chained using the `and`-form, they share a mutual
scope, allowing them to freely reference one another regardless of their lexical
ordering. Let's take a brief look at recursion in the next section.

#### 2.3. Recursion and named arguments

Recursive functions must be marked with a `rec` specifier. Specifiers are
special positional properties attached to names. Let's start with a
tail-recursive implementation of factorial. Miru will automatically perform
tail-call elimination for all tail-recursive functions.

```clojure
(val (rec factorial) [n (val %acc 1)] ; You can inline `val`-forms to set
                                      ; default values for `%<named>` arguments.
  (if (<= n 1)
    acc
    (factorial (- n 1) (* n acc))))
;;                          ^^^ Once bound, you can refer them without `%`.

;; Now, let's call it.
(factorial 6) ; 720

;; Or, get a tad bit explicit.
(factorial (val %acc 1) (val %n 6)) ; The order doesn't matter.
```

If we try to do the same but without the `rec` specifier, we are greeted with an
error.

```clojure
(val factorial [n (val %acc 1)]
  (if (<= n 1)
    acc
    (factorial (- n 1) (* n acc))))
;;  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ERROR: Unbound binding `factorial`. Did you
;;                                 forget to specify `factorial` as recursive?
```

We can extend this naturally to mutually recursive functions.

```clojure
(val (rec is-even?) [n] ; Boolean functions end in `?` as convention.
  (match n
    0 true
    n (is-odd? (- n 1))))

(and is-odd? [n]
  (match n
    0 false
    n (is-even? (- n 1))))
```

Miru enforces a strict xor across all chained bindings. An entire sequence of
`val` and `and`-forms must be either entirely mutually recursive or
non-recursive. We can't mix both behaviors within the same chain.

Miru supports fixed-point recursion using the `fix` function from the `Function`
module, allowing us to bypass explicit recursion specifiers entirely. Any
function definition can be treated as a fixed point by mapping it to a core
combinator. Below, we reimplement the factorial function using this fixed-point
style, the `fn`-form, and the `#(...)` reader macro for `fn`-forms.

```clojure
(val factorial
  (Function/fix #(fn [n (val %acc 1)]
    (if (<= n 1)
      acc
      (% (- n 1) (* n acc))))))
;;     ^ is the first argument. Positional placeholders are also allowed:
;;       %1 for first, %2 for second, and %n for nth position.
```

This can also be written without `#(...)`.

```clojure
(val factorial
  (Function/fix (fn [self]
    (fn [n (val %acc 1)]
      (if (<= n 1)
        acc
        (self (- n 1) (* n acc)))))))

(factorial 6) ; 720
```

Fix-points decouple the recursive step from the function itself. This is rather
useful for memoization, dynamic programming, tracing, anonymous recursion, among
many other domains.

Fix-points aren't limited to functions; we can also find fix-points of data
types. We'll explore them and their orthogonal variants in later chapters.

#### 2.4. Automatic currying

Miru supports automatic currying. Consequently, variadic arguments are not
supported due to their structural incompatibility.

```clojure
(val multiply [a b]
  (* a b))

(val multiply-by-5 (multiply 5)) ; It wraps a lambda that expects the remaining
                                 ; arguments.
(multiply-by-5 10) ; 50
```

Currying makes composition clean and natural. In this example, `(* 2)` wraps a
lambda that expects a second argument.

```clojure
(val new-list (List/map (* 2) '(1 2 3 4))) ; '(2 4 6 8)
```

#### 2.5. Type annotations

Let's get back to the `greet` function, which is inferred as `string -> string`.
We can also use the `val`-annotation form to define the type of a binding
ourselves.

```clojure
(val greet : string -> string) ; `greet` is the name of the binding. The name is
                               ; separated from the signature using the type
                               ; marker `:`. `->` is a mapping; it takes a
                               ; string as input and maps it to another string
                               ; as output.
```

Let's annotate the `multiply` function we made use of in the currying example.

```clojure
(val multiply : int -> int -> int) ; The signature is curried. The last type in
                                   ; the chain is the return type of the entire
                                   ; expression.
(val multiply [a b]
  (* a b)) ; The result of the last expression is automatically returned from
           ; this scope. No return keyword required.
```

We can partially annotate fields we care about while leaving the others for the
compiler to infer using type holes `_`.

```clojure
(val multiply : _ -> _ -> int)
(val multiply [a b]
  (* a b))
```

Type holes are not just limited to concrete types, they can infer effects,
contexts and modalities while setting defaults for refinement predicates. Any
unannotated component acts as an implicit type hole, allowing us to specify only
the exact constraints we care about at any given time. This forms the foundation
for inline annotations, which are permitted in two specific positions:

- Parameter tuples in `val`-form and `fn`-form.
- Any expression or pattern.

We can annotate inline parameters and expressions with concrete types by reusing
the exact same `val`-annotation format we use at the top level. Just like with
default values, reusing the annotation form here preserves grammar uniformity
and eliminates the need for a separate, specialized reader macro. This extends
naturally to universal quantifiers, abstract types, effects, contexts,
modalities, and refinements.

```clojure
(val multiply [(val a : int) b]
  (val (* a b) : int)) ; There is no separate type marker for returning values
                       ; we annotate the final returning expression directly.
```

This is semantically the same as:

```clojure
(val multiply : int -> _ -> int)
(val multiply [a b]
  (* a b))
```

> [!NOTE] While inline expressions offer a flexible, quick way to guide the
> compiler locally, they should be used sparingly. Whenever a function signature
> becomes complex, involving dense modal logic, effects, or refinements, the
> top-level `val`-annotation form is preferred to keep things readable.

#### 2.6. Calling a function just for its side-effects

As stated before, function bindings must have arity >= 1. Some functions
naturally don't take any arguments, so we use the `unit` type for the first
argument, effectively calling the function only for its side effects.

```clojure
(val hello-world : unit -> string) ; `unit` is the unit type.
(val hello-world [()] ; `()` is the unit value.
  "Hello, World!")

;; This is how we call the function.
(hello-world ()) ; We must pass the unit value here as well.

;; The following snippet is invalid.
   (hello-world)
;; ^^^^^^^^^^^^^ SYNTAX ERROR: Invalid placement of strings tags or
;;               an illegal function call with no arguments.
;
```

We'll look into how Miru tracks side-effects in its type system in later
chapters.

#### 2.7. Lambdas and aliasing

We can always define functions using lambdas and named bindings.

```clojure
(val square (fn [x] (* x x)))

;; Or, we could always use the reader form.
(val square #(* % %))

(square 6) ; 36
```

If we want to alias a function, we do:

```clojure
(val aliased-square square)
```

#### 2.8. Symbolic functions

Symbolic functions are valid, but they must be defined inside an enclosure
`(...)`.

```clojure
(val (~/) [x] (/ 1.0 x))
(~/ 4.0) ; 0.25
```

### 3. Within strings

#### 3.1. Standard strings

Before we start printing values, we need to explore strings and their forms.

We start with standard strings and the ability to tag them. Tagged strings are
very useful when we want to avoid constant escaping. In this example, `(tag)"`
always closes with `"(tag)` rather han `"`. We can name tags just like bindings.

```clojure
;; Good ol' strings.
(val a "I'm a normal string")
(val b (tag)"I'm a tagged string"(tag))
```

#### 3.2. Raw strings

Raw strings are also fully supported.

```clojure
(val c r"I'm a raw string\n") ; Raw strings do not evaluate escape sequences.
(val c r(tag)"I can also be tagged!"(tag)) ; Naturally, they can be tagged
                                           ; as well.
```

#### 3.3. Format strings/constructors

Format strings are special in that they aren't actually strings at all. They
allow interpolation and are desugared into generalized variant constructors,
much like in OCaml. They retain the "string" designation purely for convenience
and similarity, though calling them formal constructors is more precise. By
default, interpolation uses `{...}` and lets us embed named bindings directly.
However, much like in Rust, it does not support embedding arbitrary expressions.

```clojure
(val d "interpolate")
(val d f"I can {d} values!") ; I can interpolate values!
```

Alternatively, we can use the constructor form. Note that we can't mix the
literal and constructor forms together. We will dive deeper into GADTs and ADTs
later.

```clojure
(val d (f"I can {} values!" d))
```

#### 3.4. Chaining and interpolation

Format constructors also support chaining, which alter the interpolation
semantics accordingly.

```clojure
(val d (ff"I can {{}} values!" d)) ; `ff` shifts the interpolation target
                                   ; from {...} to {{...}}.
```

The rule of thumb follows a predictable pattern: `f -> {...}`, `ff -> {{...}}`,
`fff -> {{{...}}}`, or more generally, `f_n -> {_n ... }_n`.

Raw format constructors are available and support chaining as well.

```clojure
(val d (rff"I can {{}} values and raw literals like \n" d))
```

#### 3.5. Printing with format constructors

Now, we've everything required to start printing values. Let's reimplement the
`greet` function to print the value directly rather than returning a string.

```clojure
(val greet [name]
  ;; "<>" is a semigroup append function. Since string concatenation forms a
  ;; free semigroup, it behaves similar to `String/concat`.
  (println (f"{}" (<> "Hello, " name))))
```

`println` always expects a format constructor; we can't pass a standard string
as its argument directly. To convert format strings into plain strings, we can
use the `String/from-format` function.

```clojure
(val to-embed "World")
(String/from-format f"Hello, {to-embed}!") ; Hello, World!
```

### 4. Brief view of data structures

#### 4.1. Lists

Lists are dynamic, ordered, homogeneous singly-linked lists. Lists are
persistent data structures, meaning the data structure is immutable and always
preserves its previous versions when modified, relying heavily on structural
sharing to make copying efficient.

```clojure
(val lst '(1 2 3))
```

Lists do not provide language syntax for random access. However, we can always
use `List/nth`, though we should be aware of the pointer indirection cost. It
returns an `maybe` type.

```clojure
(println (f"{}" (List/nth 1 lst))) ; (Just 2)
```

Lists are intertwined with the cons function `::`. The following declaration is
semantically identical to the first:

```clojure
(val lst (:: 1 (:: 2 (:: 3 '()))))
```

We can always prepend more elements structurally.

```clojure
(val lst-new (:: 0 lst))
```

We can also use the `match`-form to deconstruct lists. More on `match`-forms
later.

```clojure
(match lst
  '() (println (f"The list is empty"))
  (:: head _) (println (f"The first element is {head}")))
;;         ^ we discard the tail.
```

#### 4.2. Arrays

Arrays are fixed-sized, contiguous, homogeneous collections. Unlike in OCaml,
Miru arrays are immutable.

```clojure
(val arr [| 1 2 3 |])
```

Arrays fields can be accessed directly using the inspection range operator
`/[...]`.

```clojure
(println (f"{}" arr/[2])) ; 3
```

We can also use the `Array/nth-offset` function, which takes an offset and
returns an `maybe` type. Since arrays can be N-dimensional, a unified 1D-style
`Array/nth` does not exist. For a 1D array, the offset is equivalent to the
index.

```clojure
(println (f"{}" (Array/nth-offset 1 arr))) ; (Just 2)
```

As an array language, Miru has native support for N-dimensional arrays. Miru
uses column-major order while remaining 0-indexed. This is a departure from the
broader column-major world, which is typically 1-indexed, but it is an
intentional trade-off to stay closer to conventional systems semantics. N-D
arrays are special because they are not arrays of arrays (also known as jagged
arrays). Instead, elements are stored contiguously in memory and queried via
pre-calculated offsets.

```clojure
(val arr [| 1 4 7 |   ; Pipes are used to segment dimensions.
            2 5 8 |   ; Array dimension = (no. of consecutive pipes) + 1.
            3 6 9 |])
(println (f"{}" arr/[2 2])) ; 9
```

We can also use `Array/nth-offset` here, but the offset must be a pre-calculated
using the formula `offset = (column * height) + row`. For this example, our
offset is `(2 * 3) + 2 = 8`. This is precisely what the compiler computes for us
when we use the `/[...]` operator.

```clojure
(println (f"{}" (Array/nth-offset 8 arr))) ; (Just 9)
```

The aforementioned formula is only valid for 2D arrays. Because this operation
is very common, the helper function `Array/offset` makes things easier for us.

```clojure
(println (f"{}" (Array/nth-offset (Array/offset [| 2 2 |]) arr)))
```

#### 4.3. Mutable arrays

Mutable arrays are the mutable variant of arrays, allowing for in-place
mutation. In Miru, mutability is a (tracked) property of data structures.
Consequently, Miru has no concept of a mutable pointer, though we will emulate
one later. We'll also look into mutability tracking in later chapters. For now,
let's ignore the handling semantics and explore the properties of mutable
arrays.

```clojure
(val arr [! 1 2 3 !])

;; We can use the same `/[...]` operator.
(println (f"{}" arr/[2])) ; 3

;; or, use the `Mut-array/nth-offset` function directly for the 1D case.
(println (f"{}" (Mut-array/nth-offset 1 arr))) ; (Just 2)
```

Miru provides a universal mutating primitive `<-`, that can be used to mutate
specific fields of mutable data structures in-place.

```clojure
;; `<-` is data last.
(<- 4 arr/[2])
(println (f"{}" arr/[2])) ; 4
```

Mutable arrays can also be N-dimensional.

```clojure
(val arr [! 1 4 7 |
            2 5 8 |
            3 6 9 !])
(println (f"{}" arr/[2 2])) ; 9

;; Let's mutate [2 2]!
(<- 10 arr/[2 2])

;; And use the `maybe` version instead. There is no separate `Mut-array/offset`.
(println (f"{}" (Mut-array/nth-offset (Array/offset [| 2 2 |]) arr))) ; (Just 10)
```

Miru tracks mutability in its effect system. We'll dive into more details in
later chapters.

#### 4.4. Dynamic arrays

Dynamic arrays are the resizable version of mutable arrays, commonly referred to
as vectors in other languages. Unlike their fixed-size counterparts, dynamic
arrays are strictly 1-dimensional. Hence, there is no intrinsic way to build
dynamically dimension-reshaping arrays. Instead, we can use a 1D dynamic array
to handle runtime growth and perform a zero-copy cast to a fixed N-D array,
provided the total element count matches the target shape. The mutability of
dynamic arrays is also tracked similar to mutable arrays or any data-structure
with interior mutability. For now, let's ignore the handling semantics and
explore the properties of dynamic arrays.

```clojure
(val dyn-arr [~ 1 2 3 4 5 6 7 8 9 ~])
(println (f"{}" dyn-arr/[5])) ; 6

;; Push a new element to the dynamic array. Functions ending in `!` are in-place
;; mutating by convention.
(Dyn-array/push! 10 dyn-arr)

;; Pop elements as needed.
(Dyn-array/pop! dyn-arr)

;; No `nth-offset` here because dynamic arrays are always 1D.
(println (f"{}" (Dyn-array/nth 8 dyn-arr))) ; (Just 9)

(val arr (Array/from-dyn [| 3 3 |] dyn-arr)) ; Cast it into a 3x3 2D array.
```

#### 4.5. Views

Non-owning or borrowed views are as important as owning data containers. They
allow Miru to provide natural, non-copying slicing operations using strided
subsections. Let's explore the three view types Miru provides: `string-view`,
`array-view` and `mut-array-view` and their respective modules. Views are deeply
intertwined with modalities (an implementation of structural co-effects) and
borrowing, which we will explore in further detail later.

> [!NOTE] This section requires ironing out modalities and cross-mode
> interaction.

#### 4.6. Sets

Base provides five set variants: CHAMP sets, hash sets, sorted sets, ordered
sets, and bit sets. Let's take a brief look at them all at once.

```clojure
;; CHAMP sets are the default set implementation in Miru. They are immutable,
;; persistent, purely applicative, unordered, homogeneous collections that
;; enforce unique elements.
(Set/from-list '(1 2 3))
;; or the alias:
(Champ-set/from-list '(1 2 3))

;; Hashsets are mutable, non-persistent, unordered (hash-based) linear
;; collections.
(Base/Containers/Hash-set/from-list '(1 2 3))

;; Sorted sets are immutable, persistent, value-ordered (Persistent B-Tree)
;; collections.
(Base/Containers/Sorted-set/from-list '(1 2 3))
;; or the alias:
(Base/Containers/B-tree-set/from-list '(1 2 3))

;; Ordered sets are immutable, persistent, insertion-ordered (Linked CHAMP)
;; collections.
(Base/Containers/Ordered-set/from-list '(1 2 3))
;; or the alias:
(Base/Containers/Linked-champ-set/from-list '(1 2 3))

;; Bit sets are mutable or unboxed, bitwise-packed sets of non-negative
;; integers.
(Base/Containers/Bit-set/from-list '(0 1 1 0))
```

#### 4.7. Maps

Base provides four map variants: CHAMP maps, hash maps, sorted maps, and ordered
maps. Let's take a brief look at them all at once.

```clojure
;; CHAMP maps are the default map implementation in Miru. They are immutable,
;; persistent, purely applicative, unordered, homogeneous key-value collections.
(Map/from-list '(["id" 1] ["id-2" 2])) ; List of 2-tuple (pair).
;; or the alias:
(Champ-map/from-list '(["id" 1] ["id-2" 2]))

;; Hashmaps are mutable, non-persistent, unordered (hash-based) linear
;; key-value maps.
(Base/Containers/Hash-map/from-list '(["id" 1] ["id-2" 2]))

;; Sorted maps are immutable, persistent, value-ordered (Persistent B-Tree)
;; key-value maps. Orders entries by key comparison to enable range queries
;; and bounds slicing.
(Base/Containers/Sorted-map/from-list '(["id" 1] ["id-2" 2]))
;; or the alias:
(Base/Containers/B-tree-map/from-list '(["id" 1] ["id-2" 2]))

;; Ordered maps are immutable, persistent, insertion-ordered (Linked CHAMP)
;; key-value maps.
(Base/Containers/Ordered-map/from-list '(["id" 1] ["id-2" 2]))
;; or the alias:
(Base/Containers/Linked-champ-map/from-list '(["id" 1] ["id-2" 2]))
```

Mutable hash sets and hash maps can function as accumulators for the persistent
variants, much like dynamic arrays do for N-D arrays. However, unlike the
latter, converting between hash variants and persistent variants is not
zero-copy and will allocate due to layout differences.

### 5. Types

#### 5.1. Type aliases

We can create type aliases using the `alias` specifier.

```clojure
(type (alias word) (maybe int)) ; Why would anyone want an maybe word :O?
```

#### 5.2. Recursive and non-recursive types

Types are recursive by default because they are commonly used to define
self-referential data structures. This example uses variant types, which we will
explore in detail in later chapters.

```clojure
(type expression
  (Literal int)
  (Variable string)
  (Block (list statement)))

(and statement
  (Assignment [string expression])
  (If-then-else [expression statement statement])
  (Void-expression expression)))
```

Non-recursive types use the `nonrec` specifier. This is useful for shadowing
types.

```clojure
(type (nonrec maybe a)
  (Just a)
  Nothing)
```

#### 5.3. Private types

Private types allow us to expose a type's structure or representation for
reading and inspection outside its defining module while restricting creation
and modification. We create them using the `private`-form.

```clojure
(type account
;     ^^^^^^^ 1
  (private 
    { owner : string
      balance : int }))
; ^^^^^^^^^^^^^^^^^^^^ 2
; 1 = `account` is public; anyone can read fields like `acc.balance`.
; 2 = `private`-form restricts direct record creation and field mutation outside
;     the module.
```

They work in tandem with the module system; we'll explore more concrete examples
in later chapters.

### 6. Within product types

#### 6.1. Tuples

Tuples are immutable, fixed-sized collections of heterogeneous elements. Tuples
are structural product types. We can use the same inspection operator `/` to
access the fields of a tuple.

```clojure
(val tup [1, 2.0 "Hello World"]) ; Commas are treated the same as whitespace.
(println (f"{}" tup/1)) ; 2.0
```

#### 6.2. Nominal records

Records are product types, just like tuples. They are nominal by default but can
be made structural to explicitly enable row-polymorphism.

```clojure
(type session
  { id : string, name : string }) ; The keys are untagged symbols.
```

The following will be inferred as `session`. We can use the inspection operator
`/` to access the fields of a record. Note that nominal types can't have
anonymous definitions.

```clojure
(val s1 { id "MIRU", name "Miru Session" }) ; Commas are whitespaces.
(println (f"{}" s1/id)) ; MIRU

(val s1 { id "MIRU", name "Miru Session", age 78 })
;;      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ERROR: Unbound record.
```

#### 6.3. Structural records

To opt into structural typing, we can append the row operator `..`. This forces
the compiler to treat the record as an open anonymous shape instead of binding
it to a principal type. Thus, this expression will be inferred structurally as
`{ id : string, name : string, .. }`, not `session`:

```clojure
(val s2 { id "MIRU", name "Miru Session", .. })
```

We can explicitly coerce a structural record to a principal type in case it
respects the field contracts using the explicit coercion operator `:>`.

```clojure
(val s2 (val { id "MIRU", name "Miru Session", age 78, .. } :> session))
                                             ; ^^^^^^ this field is consumed
                                             ; by the `..` row operator during
                                             ; the coercion to `session`.
```

Alternatively, you can achieve the same result by combining the `val`-form with
the lookup operator `^`.

```clojure
(val s2 { id "MIRU", name "Miru Session", age 78, .. })
;; We are shadowing `s2` here.
(val s2 (val ^s2 :> session))
;;      ^^^^^^^^^^^^^^^^^^^^ Find the value `s2` in scope, coerce it to `session`
;;                           and return the coerced value in place.
```

Coercions can also be written using the `val`-annotation form and the explicit
coercion operator `:>`.

```clojure
(val s2 :> session)
(val s2 { id "MIRU", name "Miru Session", age 78, .. })
```

Notice that this top-level annotation does not use the lookup operator `^`. When
the lookup operator is omitted, the compiler assumes the target name immediately
follows the annotation. This is exactly what we've been doing in the earlier
examples.

After the cast, `s2` will behave just like any nominal `session` record. Extra
fields specified by the structural record become inaccessible.

```clojure
(println (f"{}" s2/id)) ; MIRU
(println (f"{}" s2/age))
;;                 ^^^ ERROR: Unbound field 'age'.
```

#### 6.4. Field-level row-polymorphism

This enables a property called field-level row-polymorphism. For example, let's
define a function that takes any record containing an `id` field and prints it.

```clojure
(val print-id : { id : string, .. } -> unit)
(val print-id [record]
  (println (f"{}" record/id)))

;; Both of these work because they have an `id` field, despite the latter being
;; nominal.
(print-id { id "Something", .. }) ; Something
(print-id s1) ; MIRU
```

`..<name>` can be used when the row variable needs a specific name. In this
example, `p` is a unification variable rather than an abstract type. We'll look
into abstract types with greater detail in later chapters.

```clojure
(val print-id : { id : string, ..p } -> unit)
```

#### 6.5. Record bindings operators

If a record field shares the same name with a named binding, we can use the
field binding operator `~`.

```clojure
(val id "value")
(val record { ~id, .. }) ; Identical to { id id, .. } i.e. { id "value", .. }.
```

When matching against a record, we can rebind field names using the `val`-form.

```clojure
(val { (val field id), .._ } record) ; This is a form of pattern matching.
(println f"{field}") ; value
```

We name the row operator `_` to discard its value. Miru uses `_` as the
universal placeholder for data destruction, abandonment, holes and catch all
throughout the language.

The splat operator `<id>..` can be used to splat the fields of a record into
another record. It's the logical equivalent of the struct update syntax in Rust
or functional update in OCaml; it always creates a brand new record. The fields
are either copied or their ownerships are moved given the values are
non-copyable.

```clojure
(val s1 { id "M1", name "MIRU" }) ; Say of type `session`.
(val s2 { s1.., name "Miru" }) ; Gets the fields of `s1` and updates `name`.
```

When splatting a structural record, the splat operator preserves row
polymorphism. The row variable `..` from the source record automatically flows
into the destination record. This ensures that extra runtime fields are safely
carried over without information loss, maintaining the structural open-world
nature of the data:

```clojure
(val s1 { id "M1", name "MIRU", .. })
;; The row operator `..` flows from the source; no additional row operator
;; `..` is required.
(val s2 { s1.., name "Miru" }) ; { id : string, name : string, .. }
```

If we wish to force a structural record to close down into a rigid principal
type during a splat operation, we must explicitly coerce the resulting
expression:

```clojure
(val s3 (val { s1.., name "Miru" } :> session)) ; The row variable `..` is
                                                ; explicitly consumed here.
```

Records must be splat before their fields can be updated. This order is not
valid:

```clojure
(val s1 { id "M1", name "MIRU" })
(val s2 { name "Miru", s1.. })
;;                     ^^^^ ERROR: Invalid splat position. Splats must
;;                     precede field updates.
```

#### 6.6. Polarity constraints

Because structural records allow open-world rows, splatting one structural
record into another introduces the risk of silent field masking. If a source
record carries an unexpected field within its row variable `..`, explicitly
adding a field with the same name after the splat will shadow the hidden value.
This can cause down-stream semantic bugs if subsequent consumers expect the
hidden value's original configuration.

To prevent this, Miru introduces polarity constraints (or polarities) using row
variables refinements `..<id> | {<field> ...}`. Elements by default always carry
the _presence_ polarity while the _absence_ polarity can be introduced using
`-<field>`. Polarities are inert and do not require a special solver; they unify
like normal elements and only cause a unification error when trying to unify
with their opposite polarity.

In this example, the row variable `p` is mathematically guaranteed to lack the
fields `a`, `b` and `c`.

```clojure
(val transform : { ..p | {-a -b -c} } -> { a int, b string, c boolean, ..p })
;;               ^^^^^^^^^^^^^^^^^^^^ The constraint is on the input.
(val transform [input]
  { a 10, b "meta", c true, input.. })
;;                          ^^^^^^^ Splating is safe because `input` is an
;;                                  ordinary structural record that just
;;                                  happened to not have fields `a`, `b` and
;;                                  `c`. It doesn't carry any proofs with it
;;                                  at runtime.
```

`transform` safely adds the fields `a`, `b` and `c` to the open-ended record
while preventing silent overrides.

#### 6.7. Mutable fields

Records can have mutable fields using the `mut` specifier. Mutability must be
bound to a logical region, which is `r` in this example. We'll look more into
regions and the state transformation semantics in the next section. As noted
before, this applies to every data structure with interior mutability including
mutable arrays, dynamic arrays, etc.

```clojure
(type (person r) ; `r` is a type parameter that is inferred as a region.
  { name : string, (mut r age) : int })
```

Field mutation uses the same mutating operator `<-`.

```clojure
(val p1 { name "John Doe", age 30, .. })
(<- 31 p1/age)
(println (f"{}" p1/age)) ; 31
```

Structural records can also define mutable fields by applying the `mut`
specifier directly to the field name within the literal. While this inline
specifier is optional for nominal records, whose mutability is pre-defined by
their explicit type signatures, it can be used for them as well.

```clojure
(val p2 { name "Jane Doe", (mut age) 30, .. }) ; A region `r` is inferred here.
(<- 32 p2/age)
(println (f"{}" p2/age)) ; 32
```

#### 6.8. Reference cells and regions

We can use this property to build a reference cell around records to emulate
mutable names.

```clojure
(type (ref r a) ; We take a region `r` and a type `a`.
  { (mut r contents) : a }) ; The value of type `a` is bound to region `r`.

(val name (ref "Miru"))
(println (f"{}" name/contents)) ; Miru

(<- "MIRU" name/contents)
(println (f"{}" name/contents)) ; MIRU
```

This is a very useful construct, and `Base` provides it by default. Mutating and
dereferencing are common enough that Miru includes a built-in reader (`!<id>`)
for references and a symbolic function (`:=`) for mutation, similar to OCaml.

```clojure
(val message (ref "The world is still"))
(:= "Miru keeps evolving" message)
(println (f"{}" !message)) ; Miru keeps evolving
```

Note that, `r` represents a logical region that holds the data structure.
Multiple distinct data structures within the same scope can share a single
logical region `r` regardless of being allocated on the stack or the heap. This
allows the compiler to cleanly group and track their associated state effects.

#### 6.9. `var`-form and the `run-state` function

Reading and writing to mutable values within a bounded scope is referentially
transparent, provided the mutation is strictly encapsulated and cannot be
observed from the outside.

To guarantee this, Miru provides a specialized `var`-form which restricts
mutation strictly to the defining lexical scope and its immediate child scopes.
To prevent mutation from leaking, Miru enforces two structural rules:

- **No escape via closures or stack exclaves**: A variable cannot be captured or
  mutated inside an escaping closure, regardless of the level of nesting, nor
  can it be allocated in the caller's stack region through an exclave.
- **Automatic de-referencing**: The compiler automatically manages references so
  the underlying mutable container can never outlive its declaring scope.
  Consequently, variables are always at `local` mode and cannot be aliased.

```clojure
(begin
  (var x 2)
  (val y x) ; Automatically dereferences `x`.
  (:= 3 x) ; `y` is still `2` after this.
  ; This is not an escape but another dereference.
  x) ; 3
```

Reading from and writing to a mutable segment of a region `r` is effectful and
is encoded via `(read r)` and `(write r)` effects respectively. When both
operations happen in tandem, it can be encoded using a single `(state r)`
effect. Like any other effect in Miru, they do not simply disappear; they infect
the active effect row of any calling function and must be explicitly handled.
The `run-state` function introduces and encapsulates the exact region `r`
required to satisfy and discharge these effects.

```clojure
(type (person r)
  { name : string, (mut r age) : int })

;; The syntax for effects will be explored in detail in later chapters. Effects
;; are annotated using `{ eff, eff2 .. } value` or simplified to `effect value`
;; when a function performs a single effect, which in this case is `(state r)`.
(val birthday : (person r) -> (state r) unit)
(val birthday [p]
  (<- (+ p/age 1) p/age))

(val celebrate : unit -> int) ; No effect pollution here.
(val celebrate [()]
  ; The `run-state` function creates a fresh logical region 'r' for its closure.
  (run-state
    #((val guest { name "John", (mut age) 30 })
      (birthday guest)
      guest/age)))
```

We can make use of the `with`-form to write it without nesting.

```clojure
(val celebrate [()]
  ; `with`-form allows us to eliminate deeply nested code blocks caused
  ; by trailing closures. More concrete examples will follow soon.
  (with run-state)

  (val guest { name "John", (mut age) 30 })
  (birthday guest)
  guest/age)
```

Now, we can evaluate the function as usual:

```clojure
(celebrate ()) ; 31
```

In fact, when a scope is evaluated, the compiler implicitly inserts a
`run-state` function to encapsulate and discharge the resulting state effects
from `var`-forms. This example is equivalent to the original `var`-form example.

```clojure
(begin
  ; A `run-state` function to handle the region `r` required by `ref`.
  (with run-state)

  (val x (ref 2))
  (val y !x) ; Manually dereferences `x`.
  (:= 3 x) ; `y` is still `2` after this.
  ; Explicitly dereferences again.
  !x) ; 3
```

#### 6.10. Record signatures and structures

Structural records in particular have access to special `sig` and `struct`-forms
that make them cleaner to write. Nominal records can't be represented using
`sig` and `struct`-forms, as these forms are inherently open-ended. Let's
rewrite the `session` type structurally:

```clojure
(type session
  (sig
    (val id : string)
    (val name : string)))

;; Structural records do not unify with principal types automatically,
;; preserving decidable unification. They must be explicitly coerced.
(val first :> session)
(val first
  (struct
    (val id "Miru")
    (val name "The first session")))

;; This example is identical to writing structural records in literal form.
(type session
  { id : string, name : string, .. })

(val first :> session)
(val first { id "Miru", name "The first session", .. })
```

#### 6.11. Abstract types in records

Records can also hold arbitrary abstract types. The visibility and resolution of
these abstract types depend on the life-cycle of the containing record:

- **Path-Dependent Types:** If the enclosing record is bound to a known,
  immutable, and stable structural path, the abstract type is inferred as
  path-dependent.
- **Type Witnesses:** If the enclosing record is anonymous, unpacked locally, or
  otherwise loses its structural identity, the abstract type is treated as an
  opaque existential type witness.

We will discuss these mechanics in greater detail in later chapters,
specifically regarding their interactions with GADTs, applicative functors, and
generative functors.

```clojure
(type ORD
  { (type t) ; Records can hold abstract types.
    compare : t -> t -> int })

;; Or, we can use the `sig`-form.
(type ORD
  (sig
    (type t)
    (val compare : t -> t -> int)))
```

#### 6.12. Modular encapsulation

Fields are public by default, but we can take advantage of the row operator `..`
consuming unspecified fields to control visibility.

```clojure
(type session
  (sig
    (val greet : unit -> string)))

(val second :> session)
(val second
  (struct
    ;; The `id` field is not accessible outside because the `session` type
    ;; doesn't expose it.
    (val id "Miru")
    (val greet [()]
      (println f"Hello, {id}!"))))

(second/greet ()) ; Hello Miru!
(println (f"{}" second/id))
;;                     ^^ ERROR: Unbound field 'id'.
```

Miru additionally provides an `exposes`-form to perform the same encapsulation
but inside-out. This can only be used inside `sig` and `struct`-forms.

```clojure
(type session
  (sig
    ;; Defines two bindings but only exposes `greet`.
    (exposes greet)
    (val id : string)
    (val greet : unit -> string)))

(val second :> session)
(val second
  (struct
    ;; The `id` field is still not accessible outside.
    (val id "Miru")
    (val greet [()]
      (println f"Hello, {id}!"))))

(second/greet ()) ; Hello Miru!
(println (f"{}" second/id))
;;                     ^^ ERROR: Unbound field 'id'.
```

The `exposes`-form is unique because it breaks the general sequential scoping
rule. Because `exposes` is always evaluated after the entire scope has been
resolved, it can seamlessly reference values defined later in the body,
regardless of its literal position within that scope.

Consequently, the `exposes`-form mirrors top-level definitions. This is
intentional because it reflects how modules are implemented in Miru; at their
core, they are just structural records coupled with fancier syntax and an
additional ability to control encapsulation inside-out.

#### 6.13. Applicative and generative functors

Let's start by revisiting the `ORD` example, and implementing an additional
`SORTER` interface.

```clojure
(type ORD
  (sig
    (type t)
    (val compare : t -> t -> bool)))

(type SORTER
  (sig
    (type t)
    (val sort : (list t) -> (list t))))
```

Let's write a generic sorting function that uses the `compare` function.

```clojure
(val sort-generic : (a -> a -> bool) -> (list a) -> (list a))
(val sort-generic [compare lst]
  (val (rec insert) [x xs]
    (match xs
      '()       '(x)
      (:: y ys) (if (compare x y)
                  (:: x (:: y ys))
                  (:: y (insert x ys)))))
  (foldr insert '() lst))
;;              ^^^^^^^ The data last semantics hold here too.
```

Now, let's define a functor that takes in a module that implements `ORD`. Given
modules are first-class in Miru, functors are just simple functions.

```clojure
(val Make-sorter : (val M : ORD) -> (SORTER (type t M/t)))
;;                 ^^^^^^^^^^^^^            ^^^^^^^^^^^^
;; We define a path-dependent constraint, making this functor
;; applicative. `(SORTER (type t M/t))` is equivalent to
;; `SORTER with t = M.t` in OCaml.
(val Make-sorter [M]
  (val (struct
         (type t M/t)
         (val sort #(sort-generic M/compare %))) :> (SORTER (type t M/t))))
;;        Struct to nominal coercion is explicit ^^^^^^^^^^^^^^^^^^^^^^^^
```

This can get extremely tedious when multiple path-dependent constraints must be
defined at the same time. In such cases, we can use the path-threaded mapping
`=>` and by providing the target type to coerce to in the signature itself. `=>`
automatically tracks and resolves path-dependent constraints, making annotations
a lot easier to write and reason about.

```clojure
(val Make-sorter : ORD => (:> SORTER))
;;                        ^^^^^^^^^^^ Accepts anything that is coercible to
;;                                    `SORTER` and coerces it automatically.
(val Make-sorter [M]
  (struct
    (type t M/t)
    (val sort #(sort-generic M/compare %))))
```

Now, let's create two instances for sorting integers in ascending and descending
order.

```clojure
(val Int-asc :> (ORD (type t int)))
;;           ^^ For non-functional values, you can simply use direct explicit
;;              coercion.
(val Int-asc (struct
               (type t int)
               (val compare #(<= %1 %2))))

(val Int-desc :> (ORD (type t int)))
(val Int-desc (struct
                (type t int)
                (val compare #(>= %1 %2))))
```

We can use the functor to get our sorter implementations.

```clojure
(val Int-asc-sorter-1 (Make-sorter Int-asc))
(val Int-asc-sorter-2 (Make-sorter Int-asc))
;; Int-asc-sorter-1/t = Int-asc-sorter-2/t
(val Int-desc-sorter (Make-sorter Int-desc))
```

We can also build generative functors by removing the path-dependent constraint.

```clojure
(val Make-sorter-gen : ORD -> (:> SORTER))
;;                     ^^^^^^^^^^^^^^^^^^ Abstract to abstract makes use of type
;;                                        witness, making this functor generative. 
(val Make-sorter-gen [M]
  (struct
    (type t M/t)
    (val sort #(sort-generic M/compare %))))
```

Or, more concretely in 1ML terms, we seal the struct. Here is an inline
annotation version of what's actually happening.

```clojure
(val Make-sorter-gen [(val M : ORD)]
  (val (struct
         (type t M/t)
         (val sort #(sort-generic M/compare %))) :> SORTER))
;;             It's an explicit coercion indeed! ^^
```

Generativity is not an inherent property of the functor's evaluation, but a
consequence of coercion/sealing that actively severs the internal type path at
the module boundary.

Thus, the type `t` is minted uniquely for each functor call, making them
different.

```clojure
(val Int-asc-sorter-1 (Make-sorter-gen Int-asc))
(val Int-asc-sorter-2 (Make-sorter-gen Int-asc))
;; Int-asc-sorter-1/t != Int-asc-sorter-2/t
```

### 7. Within sum types

#### 7.1. Nominal variants

The `type`-form can also be used to define variant or sum types. Variants
constructors are explicitly nominal and must be capitalized. They are made
available in the global scope automatically.

```clojure
(type shape
  (Circle int)
  (Rectangle [int int]))

(val circle (Circle 10))
(val rectangle (Rectangle [10 10]))
;; This is not the same as:
(val rectangle [10 10])
```

Constructors can wrap both nominal and structural records.

```clojure
(type shape
  (Circle { radius : int, .. }))

(val basic { radius 5, .. })
(val fancy { basic.., color "red" })
(val basic-circle (Circle basic))
(val fancy-circle (Circle fancy)) ; Both work.
```

#### 7.2. Marker constructors

Marker constructors or constructors without payloads do not require enclosing
parentheses in type declarations. In this example, the reader treats `(Gray)`
and `Gray` identically.

```clojure
(type color
  (White)
  Gray ; Parens are optional for marker constructors.
  (Black)
  (RGB [int int int])
  (HSL { h int, s int, l int }))

(val a White) ; Same goes here.
(val b (RGB [240 80 40]))
(val c (HSL { h 240, s 80, l 40 }))
```

#### 7.3. `match`-form and variants

The `match`-form serves as the primary elimination construct for variants. It
provides structural pattern matching, payload extraction via field inspection
operator `/`, and pattern unions via the `|`-form often called the union.

```clojure
(match a
  (| White Gray Black)
    (println f"Got constructors with no payload!")

  (RGB t)
    (println (f"Got: {} * {} * {}" t/0 t/1 t/2))

  (HSL r)
    (println (f"Got: {{ h {}, s {}, l {} }}" r/h r/s r/l)))
    ;;               ^        <->        ^ {{ or }} to escape interpolation.
    ;; Notice it's f"..." and not ff"...".
```

In this example, we express trees using variants:

```clojure
(type (rec tree a)
  Empty
  (Node [(tree a) a (tree a)]))

(val example-tree
  (Node [
    (Node [Empty 7 Empty])
    5
    (Node [Empty 9 Empty])]))
```

#### 7.4. Structural variants

Nominal variants are closed by nature; we can't pass a variant with three tags
into a function expecting five tags without explicit conversion logic. Miru
solves this using structural variants which are conceptually identical to
polymorphic variants in OCaml. Structural variants use Clojure-inspired
`:Variant` syntax. They are open-ended, and governed by row-polymorphism across
sum tags.

```clojure
(type small { :A :B })
(type large { :A :B :C (:D string) .. }) ; They can have payloads as usual.
```

They are a drop-in replacement for a lot of cases where we'd traditionally use
keywords in other dynamically typed Lisps. Hence, the similar syntax. Functions
accepting structural variants specify the required tags in their signature.
Because subtyping in Miru is never implicit, passing a narrower structural
variant into a wider parameter requires the explicit coercion operator `:>`.

```clojure
(val process-large : large -> string)
(val process-large [x]
  (match x
    :A           "Alpha"
    :B           "Beta"
    :C           "Gamma"
    (:D payload) payload
    _            "?")))

(process-large (val :A : small))
;;             ^^^^^^^^^^^^^^^^ ERROR: Type `small` is not subtype compatible with
;;                              `large` without explicit coercion.

(process-large (val :A : small :> large))
;; Or, in this example, we could just:
(process-large (val :A : large))
```

#### 7.5. Generalized variants (GADTs)

Generalized variants allow individual constructors to specialize the return type
parameter of the variant itself. In Miru, GADTs are declared by placing a colon
`:` after the constructor name and providing an explicit function mapping to the
target specialized type.

```clojure
(type (expr' _) ; `expr` is an important builtin we shouldn't override.
;;           ^ The type hole to specialize.
  (Int     : int                       -> (expr' int))
  (Bool    : bool                      -> (expr' bool))
  (Add     : [(expr' int) (expr' int)] -> (expr' int))
  (Is-zero : (expr' int)               -> (expr' bool)))
```

To evaluate a GADT, standard unification variables are insufficient. Standard
type variables are flexible (they must unify across the entire function),
whereas GADT pattern matching requires locally abstract types.

In Miru, `(type a)` introduces a locally abstract type identifier `a`. Unlike
flexible type variables, locally abstract types introduce a rigid, newly-minted
type identity scoped strictly inside the function signature. This rigidity
allows the compiler to refine the identity of a branch-by-branch based on which
GADT constructor matched.

```clojure
(val eval : (type a) . (expr' a) -> a)
(val (rec eval) [e] ; Specifiers are a property of the binding not the type.
  (match e
    ;; Inside this branch, `a` is locally refined to `int`.
    (Int n)     n
    ;; Inside this branch, `a` is locally refined to `bool`.
    (Bool b)    b
    ;; Inside this branch, `(expr' a)` refines to `(expr' int)`, so `eval` returns
    ;; `int`.
    (Add [x y]) (+ (eval x) (eval y))
    ;; Inside this branch, `(expr' a)` refines to `(expr' bool)`, so `eval` returns
    ;; `bool`.
    (Is-zero x) (= (eval x) 0)))

(val safe-expr' (Add (Int 5) (Int 10)))
(eval safe-expr') ; 15
```

Malformed ASTs are caught at compile time before execution.

```clojure
(val bad-exp (Add (Int 5) (Bool true))) 
;;                        ^^^^^^^^^^^ Expected (exp int), got (exp bool)
```

### 8. Algebraic effects

Algebraic effects decouple the description of an effectful computation from its
interpretation. When a function performs an effect, it emits an to the
surrounding environment, leaving an enclosing handle to decide how that request
is fulfilled. Miru's effect system is modeled after the Koka programming
language and the similarities are canonical.

#### 8.1. Direct operations

Direct operations are used to perform an operation and return a value directly
to the perform site while having tail-resumption as a guarantee. They can resume
exactly once and have no access to a continuation because they do not allocate
one. They are typed and executed exactly like normal functions.

```clojure
(effect (some-state a)
  (val get : unit -> a)
  (val set : a -> unit)) ; They are defined using the `val`-form, just like
                         ; functions.
```

Now, we define a function that performs the `some-state` effect. Miru tracks the
set of effect types as effect rows. They are implemented using row-polymorphism.

```clojure
(val increment-by : int -> (some-state int) int)
(val increment-by [amount]
  (val current (get ())) ; Effect performs look exactly like function calls.
  (set (+ current amount))
  (get ()))
```

Now, let's write a handle for the function. It reduces the `some-state` effect
from the row using row variables.

```clojure
(val run-some-state : int -> (unit -> { (some-state int) ..e } int) -> e int)
(val run-some-state [init action]
  ;; Introduce the logical region `r` required by `ref`.
  (with run-state)
  (var internal-state init)

  ;; The `with`-form installs the effect handle, mapping operations to 
  ;; the variable `internal-state`.
  (with (handle
    (get _) internal-state
    (set x) (:= x internal-state)))
;;          ^^^^^^^^^^^^^^^^^^^^^ Both of these operations are tail-resumptive.

  ;; Execute the action safely within the handle and region scope.
  (action ()))
```

Now, let's call our function.

```clojure
(val res (run-some-state 10 #(increment-by 5)))
(println f"{res}") ; 15
```

In this example, we effectively modeled our own state transformer by composing
the language primitives.

#### 8.2. Control operations

Control operations are the most general for of operations that capture the
delimited continuation at the perform site. The continuation can either be
resumed once, many times or none at all. Let's model lazy iterators for an
example.

```clojure
;; We model two states and the suspension using thunks.
(type (iterator a)
  Done
  (Next [a (unit -> (iterator a))]))

(effect (yield a)
  (control yield : a -> unit))
;; ^^^^^^^ Control operations use the `control`-form.
```

Notice that an effect group and an operation can share the same name given it's
the only operation in that group. This allows us to shorten the definition to a
single line.

```clojure
(effect (control yield a) : a -> unit)
;;      ^^^^^^^^^^^^^^^^^ The `control`-form becomes a specifier.
```

Now, let's write a function to create the iterator.

```clojure
(val create-iterator : (unit -> { (yield a) ..e } unit) -> e (iterator a))
(val create-iterator [action]
  (with (handle
    (return _) Done
;;  ^^^^^^^^^^ Return allows us to work with the result right before returning it.
;;             Here, we discard the value itself, and return the `Done` constructor. 
    (yield x)  (Next [x #(resume ())])))
;;                      ^^^^^^^^^^^^ We call the continuation `resume` inside
;;                                   the thunk, making it lazy.

  (action ()))
```

And a function to drive the iterators.

```clojure
(val run-iterator : e (iterator int) -> e unit)
(val run-iterator [iter]
  (match iter
    (Done) ()
    (Next [item next]) (begin
;;        ^^^^^^^^^^^ We get a tuple with the current value and the thunk to
;;                    get the next value.  
                         (println f"Yielded: {item}")
                         (run-iterator (next ())))))
;;                                     ^^^^^^^^^ We call the thunk here.
```

And, we're ready to build some examples using our lazy iterators.

```clojure
(val my-iterator
  (create-iterator #(begin
    (yield 1)
;;  ^^^^^^^^^ These are effectively direct style iterators.
    (yield 2)
    (yield 3))))

(run-iterator my-iterator)
;; Yielded: 1
;; Yielded: 2
;; Yielded: 3
```

This was an example to utilize one-shot continuations. But, control allows us to
resume a continuations multiple times. Let's model the standard
non-deterministic choice or the ambiguous flip example. We start by defining a
simple control operation called `flip`.

```clojure
(effect (control flip) : unit -> bool)
```

Now, let's implement a `choices` function that chooses values depending on
`flip`'s value.

```clojure
(val choices : int -> flip int)
;;                    ^^^^ Since this function produces only one effect,
;;                        we don't need to wrap it in an effect row.
(val choices [x]
  (if (flip ())
;;    ^^^^^^^^^ `flip` is only performed once.
    (+ x 10)
    (+ x 0)))
```

And write a handle function for the `flip` effect.

```clojure
(val handle-flip : (unit -> { flip ..e } a) -> e (list a))
(val handle-flip [action]
  (with (handle
    (return v) '(v)
;;             ^^^^ Return the value of each branch as a list, so we can merge them.
    (flip ())
      (<> (resume true) (resume false))))
;;        ^^^^^^^^^^^^^ ^^^^^^^^^^^^^^ We are resuming the continuation two times and
;;                                     merging their values (lists).

  (action ()))
```

Now, we can run a simple example.

```clojure
(val res (handle-flip #(choices 5)))
(println f"{res}") ; '(15 5)
```

All of these examples made use of a deep handle. It automatically re-installs
itself around its continuation whenever an operation is intercepted. We'll look
into shallow handles in future chapters.

#### 8.3. Final operations

Final operations are explicitly non-resumptive operations i.e. they capture a
continuation just to discard it completely. They compile down to efficient
non-local jumps, where invoking resume is prohibited. They are a structural
generalization of exceptions, offering the same fast stack-unwinding behavior
without forcing a specific error type. Consequently, they are very well-suited
for modeling traditional exception systems, early-exit loops, and
short-circuiting searches. Let's model them.

```clojure
(effect (exn e)
  (final throw : e -> a))
;;                    ^ The output must be generic.
;; ^^^^^ We use the `final`-form to define final operations.
```

Let's write a simple function to validate age brackets.

```clojure
(val parse-age : int -> (exn string) int)
(val parse-age [age]
  (if (< age 0)
    (throw "Age can't be negative")
    age))
```

And a handle function to encode the effect into a `maybe` monad.

```clojure
(val handle-exn : (unit -> { (exn string) ..e } a) -> e (maybe a))
(val handle-exn [action]
  ; If we want to handle just one operation, we don't need to use
  ; the handle form. This is a neat shortcut.
  (with (throw err)
    (println f"Caught error: {err}")
    Nothing) ; We can't resume here.
  
  (Just (action ())))
```

And an example to go with it.

```clojure
(val res (handle-exn #(parse-age -5)))
(println f"{res}") ; Nothing
```

#### 8.4. Raw operations

Raw operations are unmanaged escape-hatches that provide direct access to raw
continuation fibers without automatic handle re-installation (often called a
shallow handle), designed specifically for building custom green-thread
schedulers and concurrency primitives. Let's reimplement the iterator example,
but this time with a `raw` yield. We're going to reuse the `iterator` data type.

```clojure
(effect (raw yield a) : a -> unit)
;;      ^^^^^^^^^^^^^ We use the `raw` specifier.
```

And the `create-iterator` function.

```clojure
(val create-iterator : (unit -> { (yield a) ..e } unit) -> e (iterator a))
(val create-iterator [action]
  (with (handle
    (return _) Done
    [(yield x) context]
;;  ^^^^^^^^^^^^^^^^^^^ Raw operations pass their raw context along.
      (Next [x #(context/resume ())])))
;;             ^^^^^^^^^^^^^^^^^^^^ We must use the `resume` from the context.

  (action ()))
```

Raw operations do not automatically finalize the execution path. All the
`(context/finalize ())` calls must be done manually. Consequently, it's possible
to leak memory if we are not careful, though it remains entirely memory safe.

### 9. The `with`-form.

We've been using it a lot. So, let's take a bit of our time to understand the
`with`-form. Here are some examples.

```clojure
(let count-steps [()]
  (scoped 0
    #(begin
       (:= (+ !% 1) %)
       (:= (+ !% 2) %)
       !%)))
```

We can address the nesting using the `with`-form, which allows us to eliminate
deeply nested code blocks caused by trailing closures. It is essentially a scope
re-writer.

```clojure
(let count-steps [()]
  (with s (scoped 0))

  ; Everything that follows is re-written into a lambda by the reader.
  (:= (+ !s 1) s)
  (:= (+ !s 2) s)
  !s)
```

`with`-form also defines special interactions with `handle`s and `given`s,
making them really nice to work with.

```clojure
(with (handle
  (emit msg) (begin
               (println f"{msg}")
               (resume ()))))

(emit "1st!")
(emit "2nd")
```

Without `with`-form, it would devolve into nested scopes.

```clojure
(handle
  (emit msg) (begin
               (println f"{msg}")
               (resume ()))
  #(begin
     (emit "1st!")
     (emit "2nd"))) ; This will get very tedious with nested handles.
```

### 10. Algebraic Co-effects

Miru implement two forms of co-effects: _flat_ (also called `contexts`) and
_structural_ (also called `modes`). A context tracks ambient environment
requirements as a single, global record shared across the entire computation,
whereas a structural co-effect tracks resource properties or usage constraints
individually for each specific variable in the context. So tracking properties
like linearity, portability, contention, locality etc. are what makes structural
co-effects very powerful. Miru tracks structural co-effects very similar to
modaities found in OxCaml (Jane Street's OCaml fork). Unlike flat co-effects,
structural co-effects do not make use of row-polymorphism but modality lattices.
Let's unpack them one by one, in their respective sections.

### 11. Contexts

To put it simply, contexts act as the ambient arguments of a function. These
parameters are implicitly expected by the function's execution environment and
are threaded automatically by the compiler. By abstracting away manual argument
passing, contexts provide an very clean and elegant primitive for type-directed
dependency injection. They are deeply intertwined with the module system and for
very good reasons. Let's start by implementing a `SHOW` signature.

```clojure
(type SHOW
  (sig
    (type t)
    (val show : t -> string)))
```

Miru tacks contexts using the context row `-{ ... }->`. Just like effects,
contexts make use of row-polymorphism, but do not expose a row operator `..`.
This is because, the type handles it behind the scenes implicitly. Additionally,
we can define a local alias for a context using the `val`-form.

```clojure
(val print-show : a -{ (val S (SHOW (type t a))) }-> unit)
;;                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
;; This reads as, "To produce `unit` from `a`, `S` must be provided ambiently."
(val print-show [x]
  (println (f"Printing {}!" (?S/show x))))
;;                           ^^ `?<id>` is how we extract a context from the
;;                              context row. They are like `%<named>` arguments
;;                              but ambient.
```

Let's implement the `SHOW` signature for integers and lists.

```clojure
(val Show-int :> (SHOW (type t int)))
(val Show-int (struct
                (type t int)
                (val show #(Int/into-string %))))

(val Show-list : SHOW => (:> SHOW))
(val Show-list [S]
  (struct
    (type t (list S/t))
    (val show #(String/from-format
                 (f"list({})" (List/join " " (List/map S/show %)))))))
```

We can't pass the modules or functors directly to the `print-show` function; it
expects them to ambiently available in the environment. This is where we use the
`given`-form.

```clojure
(with (given Show-int))
(print-show 4) ; Printing 4!

(with (given (Show-list Show-int)))
(print-show '(1 2 3)) ; Printing list(1 2 3)!
```

Beyond simple lookups, Miru’s context engine acts as a Horn clause solver. When
a function requires a context that depends on other types (such as `Show-list`
needing a `SHOW` instance for its element type), the compiler performs backward
chaining to logically derive the demand for the unspecified instance.

```clojure
(with (given Show-int Show-list))
(print-show '(1 2 3)) ; Printing list(1 2 3)!
```

### 12. Modalities

Modalities or modes define the structural constraints carried by a particular
value. This includes properties like locality (if a value is local to a scope),
linearity (if a value can be used multiple times), uniqueness (if a value can be
held uniquely), among others. Each of these properties are their own temporal
axes: they either define what already happened in the past, or what can happen
in the future. Unlike effects and contexts, modalities do not use
row-polymorphism, but use graded modal calculus using an ordered semiring.
Miru's modalities take heavy inspiration from Jane Street's work on OxCaml. Much
like OxCaml, modalities exist independently of standard types; they are
orthogonal.

#### 12.1. Locality

Locality controls where a value can live and flow. Values are categorized by
locality as either `local` or `global` with the latter being the default.

A `local` value is restricted to its enclosing region, forbidding it from
escaping into a return value, being captured by a escaping closure, or being
stored in long-lived data structures. Conversely, `global` values have no such
restriction and can be safely shared or returned.

```clojure
;; Function that processes local data within its stack frame.
(val sum-pairs : (list int) @ local -> int)
(val sum-pairs [pairs]
  (List/reduce + 0 pairs)) ; Works fine; `pairs` never leaves this scope.
```

If a `local` value attempts to cross its boundary, the compiler triggers a
static error.

```clojure
(val leak-array : (array int) @ local -> (array int)) 
(val leak-array [arr]
   arr) 
;; ^^^ ERROR: arr is `local` and can't escape its region.
```

> [!TODO] Document exclaves.

#### 12.2. Linearity

Linearity governs how many times a value can be used: `many` values can be
freely reused, whereas `once` values are affine. `once` values cannot be copied,
cloned, or borrowed; they can only be moved or consumed.

```clojure
(val x "Hello") ; Values by default are always `many`.
```

Modes can be introduced using various ways. The easiest way is to use the
`val`-annotation form and the `@ [ ... ]` mode tuple.

```clojure
(val x @ once)
;;       ^^^^ When using only one mode, the tuple `[ ... ]` isn't required.
(val x "Hello")
```

Or, inlining them is always a possibility.

```clojure
(val x (val "Hello" @ once))
```

This example implements a one-time cryptographic handshake token. Once the token
is used to authenticate, it must be consumed so it can never be reused or
leaked.

```clojure
;; Function that takes an unrestricted value.
(val log-attempt : string -> unit)
(val log-attempt [msg]
  (println (f"Auth attempted with message: {}" msg)))

;; Function that consumes a linear token.
(val auth : token @ once -> string)
(val auth [t]
  (Crypto/verify-and-burn t))
;; ^^^^^^^^^^^^^^^^^^^^^^ This is some random function that consumes `t`.
```

Let's try calling the first function multiple times with some value `msg`.

```clojure
(val msg "Initiating Handshake")

(log-attempt msg) ; This is fine.
(log-attempt msg) ; It's still fine because `msg` is `many`.
```

Now, let's try something similar, but for the latter function.

```clojure
;; Let's mint some token.
(val token @ once)
(val token (Crypto/generate-token ()))

;; And, authenticate using it.
(val auth-status-1 (auth token)) ; This is fine.
(val auth-status-2 (auth token))
;;                       ^^^^^ ERROR: `token` is `once`, and it was
;;                             already consumed.
```

#### 12.3. Uniqueness and Function-but-in-place (FBIP)

Values can either be `unique`ly owned or `aliased`. A `unique` value guarantees
that there are no other active aliases or references pointing to the same memory
at the point of access.

```clojure
(let msg @ unique)
(let msg "hello")

(aliased-use msg) ; `msg` used as aliased i.e. its uniqueness is lost.
(unique-use msg))
;;          ^^^ ERROR: Expected `msg` to be `unique` but it is `aliased`.
```

To solve this, we introduce borrowing `&<id>`.

```clojure
(let msg @ unique)
(let msg "hello")

(aliased-use &msg) ; Temporarily aliases `msg` for its scope.
(unique-use msg)) ; `msg` is uniquely owned, so it compiles.
```

The signature of the `aliased-use` is as follows:

```clojure
(val aliased-use : string @ [local aliased] -> unit)
;;                          ^^^^^^^^^^^^^^^ This makes it an immutable
;;                                          borrow.
(val aliased-use [msg]
  ...) ; `msg` can't escape this function i.e. you can't return it to
       ; the outside world.
```

A borrowed value is `aliased` so it can't be passed where a `unique` value is
expected. It is also `local`, because it can't escape its borrow region.

Uniqueness guarantees exclusive access, enabling functions to perform in-place
mutation without breaking referential transparency. This pattern is termed
**Functional-but-in-place (FBIP)**. If a parameter is typed as `unique`, the
compiler ensures that the caller passes an exclusive reference. The function can
then destructively update or reuse the underlying memory buffer, even if the
underlying data is inherently immutable.

```clojure
(val reverse-acc : (list a) @ unique -> (list a) -> (list a) @ unique)
(val reverse-acc [xs acc]
  (match xs
;;       ^^ Since it's uniquely owned, it's consumed destructively i.e.
;;          the memory is physically reused for the new `Cons` nodes
;;          being built for the accumulator.
    Nil acc)
    (Cons y ys) (reverse-acc ys (Cons y acc)))
```

> [!TODO] Document the remaining modalities.

> [!NOTE] The section below is yet to be serialized properly.

```clojure
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

;; MSP is phase-agnostic i.e. we could expand the expressions either at compile-time or
;; at runtime. So, how do we drive the context? We divide it. `lower` lowers the expression
;; at runtime, while `realize` realizes the expression at compile-time. Both are a form of
;; "lowering" values.

(let value (realize (unroll 4 `3))) ; It will be realized at compile-time unlike `lower`.

;; This allows us to mix and match code that evalues at compile-time with code that should evaluate
;; at runtime. That said, there is a specific rule that must be followed: we can lower an expression
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
;; we can prove that an index never leaves the array's bounds at compile-time!

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

;; We can also move the inline predicates to predicate definations! Very similar to
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
;; 1) We can bind names to positional types, thus making them referenceable.
;; 2) Mutability being a property of the data-structure makes mutation sets inferable.
;; 3) Pre-conditions and post-conditions can be merged into a single expression.

;; A more thorough e.g. of merged conditions:
(val safe-div : (num   : int)
             ;; The merger simply dissolves into the "conditions that matter" for a type.
             -> (denom : int | (!= denom 0))
             -> (res   : int | (== (* res denom) num)))

;; NOTE: While allowed, non-linear arithmetic like x * y is undecidable, but we
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
      ;; Note, we use { ... } to embed Miru values, which is a good distinction.
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

#![allow(dead-code)] ; We'll see them often when dealing with module level options.
```
