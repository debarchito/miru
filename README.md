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

## 2. What are the components?

> NOTE: All components are not yet complete.

- [miru-rtl](./miru-rtl) or Miru runtime library is written in Rust. It is built
  to be embedable. (This replaced `miru-core` in case you are trying to find
  it).
- [miru](./miru) holds the lowering tools (source -> bytecode, and source ->
  assembly in future), macro engine, type checker, etc. all written in OCaml.
- [miru-machine](./miru-machine) is the register machine written in Rust. This
  also powers the macro engine and is bridged to OCaml.
- [miru-repl](./miru-repl) is the Read-Eval-Print-Loop and the primary way to
  interact with Miru right now.

## 3. Get started!

It's a fresh project with lots of aspirations. I want to take my time to learn
and implement things mindfully. This means a lot of experimentation and what
could be better than a REPL for such situations? To try out the repl:

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

Take a look at [DRAFT.md](./DRAFT.md) for a quick guide on the syntax of the
language.

## 5. Licensing.

This repository is dual-licensed under either the [MIT License](./LICENSE-MIT)
or the [Apache 2.0 License](./LICENSE-APACHE-2.0), at your option.
