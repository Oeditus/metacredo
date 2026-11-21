//! Deeply nested conditionals.

pub fn classify(a: i32, b: i32, c: i32, d: i32) -> i32 {
    if a > 0 {
        if b > 0 {
            if c > 0 {
                if d > 0 {
                    if a > b {
                        1
                    } else {
                        2
                    }
                } else {
                    3
                }
            } else {
                4
            }
        } else {
            5
        }
    } else {
        6
    }
}
