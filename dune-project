(lang dune 3.22)

(name sirome)

(generate_opam_files true)

(cram enable)

(source
 (sourcehut debarchito/sirome))

(authors "Debarchito Nath <debarchiton@proton.me>")

(maintainers "Debarchito Nath <debarchiton@proton.me>")

(package
 (name sirome)
 (synopsis "My opinionated take on a Clojure-esque Lisp with ML schematics")
 (description "My opinionated take on a Clojure-esque Lisp with ML schematics")
 (depends
  (ocaml (>= "5.4.1")))
 (tags
  ("sirome")))
