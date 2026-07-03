//! This module defines a 64-bit metadata header. Bits 0-7 store an 8-bit
//! semantic type tag, bits 8-9 track a 2-bit tricolor GC color, and the
//! remaining 54-bits track allocation size (word size).

#[repr(transparent)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct Header(pub u64);

impl Header {
  pub const TAG_SHIFT: u64 = 0;
  pub const COLOR_SHIFT: u64 = 8;
  pub const SIZE_SHIFT: u64 = 10;

  pub const TAG_MASK: u64 = 0xFF << Self::TAG_SHIFT; // bits 0 through 7.
  pub const COLOR_MASK: u64 = 0x3 << Self::COLOR_SHIFT; // bits 8 through 9.
  pub const SIZE_MASK: u64 = !0 << Self::SIZE_SHIFT; // bits 10 through 63.

  // tag 0 is the standard block tag for tuples, records and arrays.
  // tag 1 through 245 are for variant constructors.
  pub const TAG_LAZY: u8 = 246;
  pub const TAG_CLOSURE: u8 = 247;
  pub const TAG_INFIX: u8 = 248;
  pub const TAG_FORWARD: u8 = 249;
  pub const TAG_NO_SCAN: u8 = 250; // >= 250 are treated as opaque objects by GC.
  pub const TAG_BYTES: u8 = 251;
  pub const TAG_STRING: u8 = 252; // unlike OCaml, Miru strings are UTF-8 encoded.
  pub const TAG_FLOAT: u8 = 253;
  pub const TAG_FLOAT_ARRAY: u8 = 254;
  pub const TAG_CUSTOM: u8 = 255;

  // these colors use the same OCaml convention.
  pub const COLOR_WHITE: u8 = 0;
  pub const COLOR_BLACK: u8 = 1;
  pub const COLOR_GRAY: u8 = 2;
  pub const COLOR_BLUE: u8 = 3;

  #[inline(always)]
  pub fn new(size: u64, color: u64, tag: u64) -> Self {
    debug_assert!(
      size <= (Self::SIZE_MASK >> Self::SIZE_SHIFT),
      "size overflows 54-bit field"
    );
    debug_assert!(
      color <= (Self::COLOR_MASK >> Self::COLOR_SHIFT),
      "color overflows 2-bit field"
    );
    debug_assert!(
      tag <= (Self::TAG_MASK >> Self::TAG_SHIFT),
      "tag overflows 8-bit field"
    );

    let size_part = (size << Self::SIZE_SHIFT) & Self::SIZE_MASK;
    let color_part = (color << Self::COLOR_SHIFT) & Self::COLOR_MASK;
    let tag_part = (tag << Self::TAG_SHIFT) & Self::TAG_MASK;
    Header(size_part | color_part | tag_part)
  }

  #[inline(always)]
  pub fn get_tag(self) -> u64 {
    (self.0 & Self::TAG_MASK) >> Self::TAG_SHIFT
  }

  #[inline(always)]
  pub fn get_color(self) -> u64 {
    (self.0 & Self::COLOR_MASK) >> Self::COLOR_SHIFT
  }

  #[inline(always)]
  pub fn get_size(self) -> u64 {
    (self.0 & Self::SIZE_MASK) >> Self::SIZE_SHIFT
  }

  #[inline(always)]
  pub fn set_tag(&mut self, tag: u64) {
    debug_assert!(
      tag <= (Self::TAG_MASK >> Self::TAG_SHIFT),
      "tag overflows 8-bit field"
    );

    self.0 = (self.0 & !Self::TAG_MASK) | ((tag << Self::TAG_SHIFT) & Self::TAG_MASK);
  }

  #[inline(always)]
  pub fn set_color(&mut self, color: u64) {
    debug_assert!(
      color <= (Self::COLOR_MASK >> Self::COLOR_SHIFT),
      "color overflows 2-bit field"
    );

    self.0 = (self.0 & !Self::COLOR_MASK) | ((color << Self::COLOR_SHIFT) & Self::COLOR_MASK);
  }

  #[inline(always)]
  pub fn set_size(&mut self, size: u64) {
    debug_assert!(
      size <= (Self::SIZE_MASK >> Self::SIZE_SHIFT),
      "size overflows 54-bit field"
    );

    self.0 = (self.0 & !Self::SIZE_MASK) | ((size << Self::SIZE_SHIFT) & Self::SIZE_MASK);
  }
}
