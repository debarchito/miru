//! This module defines a uniform value representation identical to OCaml. The
//! least significant bit is used to differentiate between an int and a heap
//! ptr. This as a consequence, makes all unboxed integers signed 63-bit.

// NOTE: Once kinds are implemented in the language, a special layout kind can
// be utilized for unboxed value representation.

#[repr(transparent)]
#[derive(Copy, Clone, PartialEq, Eq)]
pub struct Word(pub i64);

impl Word {
  #[inline(always)]
  pub fn is_ptr(self) -> bool {
    (self.0 & 1) == 0
  }

  #[inline(always)]
  pub fn is_int(self) -> bool {
    (self.0 & 1) == 1
  }

  #[inline(always)]
  pub fn from_ptr<T>(ptr: *const T) -> Self {
    let addr = ptr as i64;
    debug_assert!((addr & 1) == 0, "pointers must be word-aligned");
    Word(addr)
  }

  #[inline(always)]
  pub fn to_ptr<T>(self) -> *mut T {
    debug_assert!(self.is_ptr());
    self.0 as *mut T
  }

  #[inline(always)]
  pub fn from_int(n: i64) -> Self {
    Word((n << 1) | 1)
  }

  #[inline(always)]
  pub fn to_int(self) -> i64 {
    self.0 >> 1
  }
}
