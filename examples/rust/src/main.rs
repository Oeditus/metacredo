//! Example crate for exercising `metacredo` against Rust source.
//!
//! Every module here is deliberately flawed so that a single `mix metacredo`
//! run produces findings across several categories. See `README.md` in this
//! directory for the expected findings and how to run the analysis.

mod config;
mod dedup;
mod http;
mod naming;
mod nesting;
mod numbers;
mod unreachable;

fn main() {
    let settings = config::Settings::load();
    println!("starting with {} retries", settings.retries);
}
