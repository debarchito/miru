## 1. What is Miru about?

Miru is a research project and yet another attempt at unifying Lisp and the ML
families. While OCaml and Clojure are the spiritual predecessor of Miru, this
doesn't mean porting features 1:1. Miru does inherit a lot of their aspects but
also tries to extend and experiment where it makes sense. Some of these include:
type-informed macros, row polymorphic records, algebraic effects as the only
non-local control flow with effect types and capabilities etc. I like to divide
Miru into two different parts: the base language and the cover language. The
base language is the reduced form of Miru which contains a very small set of
features the rest of the language (cover) is bootstrapped around.

## 2. Get started!

It's a fresh project with lots of aspirations. I can't guarantee if it'll be
complete in few months, years or decades. I want to take it slow and implement
things mindfully. This means a lot of experimentation and what could be better
than a REPL for such situations? To try out the repl:

```fish
direnv allow
dune exec miru-repl
```

## 3. What's happening?

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
