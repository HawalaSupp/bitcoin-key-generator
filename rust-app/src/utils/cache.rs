//! Simple In-Memory Cache
//!
//! Provides time-based caching for API responses.

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Simple time-based cache
pub struct Cache<T> {
    data: HashMap<String, (T, Instant)>,
    ttl: Duration,
}

impl<T: Clone> Cache<T> {
    pub fn new(ttl_seconds: u64) -> Self {
        Self {
            data: HashMap::new(),
            ttl: Duration::from_secs(ttl_seconds),
        }
    }

    pub fn get(&self, key: &str) -> Option<T> {
        self.data.get(key).and_then(|(value, inserted)| {
            if inserted.elapsed() < self.ttl {
                Some(value.clone())
            } else {
                None
            }
        })
    }

    pub fn set(&mut self, key: String, value: T) {
        self.data.insert(key, (value, Instant::now()));
    }

    pub fn invalidate(&mut self, key: &str) {
        self.data.remove(key);
    }

    pub fn clear(&mut self) {
        self.data.clear();
    }

    /// Remove expired entries
    pub fn cleanup(&mut self) {
        self.data.retain(|_, (_, inserted)| inserted.elapsed() < self.ttl);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread::sleep;

    #[test]
    fn test_cache_basic() {
        let mut cache: Cache<String> = Cache::new(10);
        
        cache.set("key1".to_string(), "value1".to_string());
        assert_eq!(cache.get("key1"), Some("value1".to_string()));
        assert_eq!(cache.get("key2"), None);
    }

    #[test]
    fn test_cache_expiry() {
        let mut cache: Cache<String> = Cache::new(1);
        
        cache.set("key1".to_string(), "value1".to_string());
        assert_eq!(cache.get("key1"), Some("value1".to_string()));
        
        sleep(Duration::from_millis(1100));
        assert_eq!(cache.get("key1"), None);
    }
}
