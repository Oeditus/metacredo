//! Configuration loading with hardcoded values.

pub struct Settings {
    pub api_url: String,
    pub retries: u32,
}

impl Settings {
    pub fn load() -> Settings {
        Settings {
            api_url: String::from("https://api.example.com/v1/users"),
            retries: 5,
        }
    }
}
