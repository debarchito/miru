use ocaml_interop::{OCaml, OCamlInt64, OCamlRuntime, ToOCaml};

#[ocaml_interop::export]
pub fn square(cr: &mut OCamlRuntime, num: OCaml<OCamlInt64>) -> OCaml<OCamlInt64> {
  let num = num.to_rust::<i64>();
  ((num * 2) as i64).to_ocaml(cr)
}
