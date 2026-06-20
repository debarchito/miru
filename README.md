## What is it about?

This is a research project and an attempt at unifying some of my favorite
features and paradigms from languages such as OCaml, Clojure, Haskell, Rust,
Zig, Koka, Carp, Shen, etc. It inherits a lot of aspects from OCaml like it's
unified representation model, effect handlers, etc. It's currently in a very
early and experimental stage (I started worked on it very recently!). I try to
document my decisions in the code as doc comments. There are currently two
components: `miru-core` and `miru`. `miru-core` holds the core details and
values like the memory representation primitives etc. while `miru` holds the
language and register machine implementation. I'll document more things as the
project progresses.

## Licensing

Miru is licensed under [GPLv3-only](./LICENSE).
