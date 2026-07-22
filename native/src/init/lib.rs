// Kyubi's magiskinit is a minimal sepolicy patcher (see init.cpp). The Rust lib
// exists only to pull the magiskpolicy symbols into the linked binary.
// Has to be pub so all symbols in that crate are included.
pub use magiskpolicy;
