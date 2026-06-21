## What is it about?

This is a research project and an attempt at unifying some of my favorite
features and paradigms from languages such as OCaml, Clojure, Haskell, Rust,
Zig, Koka, Carp, Shen, etc. It inherits a lot of aspects from OCaml like it's
unified representation model, effect handlers, etc. It's currently in a very
early and experimental stage (I started worked on it very recently!).

## How to make sense of the project?

There are currently three components: `miru-core`, `miru` and `miru-repl`.
`miru-core` holds the core details and values like the memory representation
primitives etc. while `miru` holds the language and register machine
implementation. `miru-repl` is a small but useful REPL implementation for miru
and is the primary tool for interacting with the language in the development
phase. To get started run:

```fish
direnv allow
dune exec miru-repl
```

## Licensing

Miru is licensed under [GPLv3-only](./LICENSE).
