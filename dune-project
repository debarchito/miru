(lang dune 3.22)

(name miru)

(generate_opam_files true)

(cram enable)

(source
 (sourcehut debarchito/miru))

(authors "Debarchito Nath <debarchiton@proton.me>")

(maintainers "Debarchito Nath <debarchiton@proton.me>")

(package
 (name miru-core)
 (description "Miru's core library")
 (depends
  (ocaml
   (>= "5.4.1"))
  (asai
   (>= "0.3.1"))
  (alcotest
   (>= "1.9.1")))
 (tags
  ("miru-core" "miru")))

(package
 (name miru-repl)
 (description "Miru's interactive REPL")
 (depends
  (ocaml
   (>= "5.4.1"))
  (miru
   (= :version)))
 (tags
  ("miru-repl" "miru")))

(package
 (name miru)
 (synopsis "My take on a specialized statically typed Lisp+ML hybrid")
 (description "My take on a specialized statically typed Lisp+ML hybrid")
 (depends
  (ocaml
   (>= "5.4.1"))
  (miru-core
   (= :version))
  (asai
   (>= "0.3.1"))
  (alcotest
   (>= "1.9.1"))
  (dune-cargo-build
   (>= "0.2.2")))
 (tags ("miru")))
