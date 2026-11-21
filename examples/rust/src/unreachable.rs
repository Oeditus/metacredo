//! Code after an early return.

pub fn fetch(id: u32) -> u32 {
    if id == 0 {
        return 0;
    }
    let cached = id * 2;
    cached
}

pub fn unreachable_tail(id: u32) -> u32 {
    return id;
    let dead = id + 1;
    dead
}
