(lang dune 3.22)

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
   (>= "5.4.1")))
 (tags ("miru")))
