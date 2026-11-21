//! Magic numbers and unseparated large integers.

pub fn retry_delay(attempt: u64) -> u64 {
    attempt * 3600
}

pub fn max_connections() -> u64 {
    100000
}

pub fn budget() -> u64 {
    1250000
}
