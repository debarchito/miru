## 1. What is Miru about?

Miru is a research language and yet another attempt at unifying Lisp and the ML
families.

While OCaml and Clojure are the primary inspirations, this doesn't mean porting
features 1:1.While Miru inherits a lot of their aspects, it also tries to extend
and experiment where it makes sense. Some of these include:

- type-informed macros
- row polymorphic records
- algebraic effects as the only non-local control flow with effect types and
  capabilities
- and, many others that i'll rigorously document.

I like to conceptually divide Miru into two distinct parts: the base language
and the cover language. The base language is a reduced form which contains a
very small set of features which, the rest of the language is bootstrapped
around (hence the name "cover"; the term is derived from topological covers).

## 2. Get started!

> NOTE: A major migration is under-way. The original memory representation
> primitives were written as an OCaml-library. But, I've decided to port the RTL
> (runtime library) to Rust and use OCaml for the lowering pipeline and bytecode
> construction. Thus, the register machine will also be implemented in Rust for
> more control over performance and memory allocation. I've already migrated
> [flake.nix](/flake.nix) to support the Rust-to-OCaml FFI scenario starting
> with the [miru-rtl](/miru-rtl) library. It was very complicated but I ended up
> with conditional compilation staging that worked wonders for me.

It's a fresh project with lots of aspirations. I want to take my time and
implement things mindfully. This means a lot of experimentation and what could
be better than a REPL for such situations? To try out the repl:

```fish
# Scaffold the development environment
direnv allow

# Build and run the REPL
dune exec miru-repl
```

Alternatively, Miru integrates deeply with the Nix ecosystem (partly cause I use
Nix for everything). So, you can build and run the REPL directly using:

```fish
nix run sourcehut:~debarchito/miru#miru-repl
```

I'll attach a document explaining the syntax in the upcoming days, so you have a
reference to evaluate the REPL against.

## 3. What's happening right now?

> NOTE: `miru-core` will be removed in favor of `miru-rtl` and the
> `Miru_rtl_bridge.Rtl` bindings.

- Uniform representation and header layout. See
  [miru-core/lib/repr](./miru-core/lib/repr).
- Generational heap. See [miru-core/lib/memory](./miru-core/lib/memory).
- Reader, readtables and reader macros. See
  [miru/lib/reader](./miru/lib/reader).
- Register machine ISA. See [miru/lib/vm](./miru/lib/vm).
- A rudimentary REPL (reader expansion only) with nice error reporting. See
  [miru-repl/lib](./miru-repl/lib).

## 4. Licensing.

Miru is licensed under [GPLv3-only](./LICENSE).
