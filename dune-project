(lang dune 3.24)

(name miru)

(generate_opam_files true)

(cram enable)

(source
 (sourcehut debarchito/miru))

(authors "Debarchito Nath <debarchiton@proton.me>")

(maintainers "Debarchito Nath <debarchiton@proton.me>")

(package
 (name miru)
 (synopsis "My take on a specialized statically typed Lisp+ML hybrid")
 (description "My take on a specialized statically typed Lisp+ML hybrid")
 (depends
  (ocaml
   (>= "5.5.0"))
  (zarith
   (= "1.14"))
  (floatml
   (= "0.2.1"))
  (ppx_deriving
   (= "6.1.3"))
  (asai
   (= "0.3.1"))
  (alcotest
   (= "1.9.1"))
  (dune-cargo-build
   (= "0.2.2")))
 (tags ("miru")))

(package
 (name miru-repl)
 (description "Miru's interactive REPL")
 (depends
  (ocaml
   (>= "5.5.0"))
  (miru
   (= :version)))
 (tags
  ("miru-repl" "miru")))
