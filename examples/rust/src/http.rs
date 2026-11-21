//! HTTP helper with a hardcoded endpoint.

pub fn fetch_users() -> String {
    let endpoint = "https://api.example.com/v1/users";
    let backup = "https://10.20.30.40/v1/users";
    format!("{} {}", endpoint, backup)
}
