//! Price Alert Manager
//!
//! Monitor asset prices and trigger notifications when targets are hit.
//! Supports multiple alert types: above, below, percent change.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// Type of price alert
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AlertType {
    /// Alert when price goes above target
    Above,
    /// Alert when price goes below target
    Below,
    /// Alert on percent increase
    PercentIncrease,
    /// Alert on percent decrease
    PercentDecrease,
    /// Alert on any significant move (up or down)
    PercentChange,
}

/// Alert status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AlertStatus {
    /// Alert is active and monitoring
    Active,
    /// Alert was triggered
    Triggered,
    /// Alert is paused
    Paused,
    /// Alert expired
    Expired,
    /// Alert was cancelled
    Cancelled,
}

/// Price alert configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceAlert {
    /// Unique alert ID
    pub id: String,
    /// Asset symbol (e.g., "BTC", "ETH")
    pub symbol: String,
    /// Alert type
    pub alert_type: AlertType,
    /// Target price (for Above/Below) or percent (for PercentChange)
    pub target_value: f64,
    /// Base price when alert was created (for percent alerts)
    pub base_price: Option<f64>,
    /// Status
    pub status: AlertStatus,
    /// Created timestamp
    pub created_at: u64,
    /// Triggered timestamp (if triggered)
    pub triggered_at: Option<u64>,
    /// Price when triggered
    pub triggered_price: Option<f64>,
    /// Optional note/label
    pub note: Option<String>,
    /// Whether to auto-reset after triggering
    pub repeat: bool,
    /// Expiration timestamp (optional)
    pub expires_at: Option<u64>,
}

/// Request to create a price alert
#[derive(Debug, Clone, Deserialize)]
pub struct CreateAlertRequest {
    /// Asset symbol
    pub symbol: String,
    /// Alert type
    pub alert_type: AlertType,
    /// Target value
    pub target_value: f64,
    /// Optional note
    pub note: Option<String>,
    /// Whether to repeat
    pub repeat: bool,
    /// Optional expiration (Unix timestamp)
    pub expires_at: Option<u64>,
}

/// Triggered alert notification
#[derive(Debug, Clone, Serialize)]
pub struct AlertNotification {
    /// Alert that was triggered
    pub alert: PriceAlert,
    /// Current price
    pub current_price: f64,
    /// Message for notification
    pub message: String,
}

/// Current price data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceData {
    pub symbol: String,
    pub price: f64,
    pub change_24h: f64,
    pub change_24h_percent: f64,
    pub updated_at: u64,
}

// =============================================================================
// Price Alert Manager
// =============================================================================

/// Manages price alerts
pub struct PriceAlertManager {
    /// Active alerts
    alerts: HashMap<String, PriceAlert>,
    /// Price cache
    price_cache: HashMap<String, PriceData>,
    /// Next alert ID
    next_id: u64,
}

impl PriceAlertManager {
    /// Create a new price alert manager
    pub fn new() -> Self {
        Self {
            alerts: HashMap::new(),
            price_cache: HashMap::new(),
            next_id: 1,
        }
    }

    /// Create a new price alert
    pub fn create_alert(&mut self, request: CreateAlertRequest) -> HawalaResult<PriceAlert> {
        // Validate
        if request.symbol.is_empty() {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Symbol required"));
        }

        if request.target_value <= 0.0 {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Target value must be positive"));
        }

        // Get current price for percent-based alerts
        let base_price = match request.alert_type {
            AlertType::PercentIncrease | AlertType::PercentDecrease | AlertType::PercentChange => {
                let current = self.get_current_price(&request.symbol)?;
                Some(current)
            }
            _ => None,
        };

        let id = format!("alert_{}", self.next_id);
        self.next_id += 1;

        let alert = PriceAlert {
            id: id.clone(),
            symbol: request.symbol.to_uppercase(),
            alert_type: request.alert_type,
            target_value: request.target_value,
            base_price,
            status: AlertStatus::Active,
            created_at: current_timestamp(),
            triggered_at: None,
            triggered_price: None,
            note: request.note,
            repeat: request.repeat,
            expires_at: request.expires_at,
        };

        self.alerts.insert(id, alert.clone());
        Ok(alert)
    }

    /// Get an alert by ID
    pub fn get_alert(&self, id: &str) -> Option<&PriceAlert> {
        self.alerts.get(id)
    }

    /// Get all alerts for a symbol
    pub fn get_alerts_for_symbol(&self, symbol: &str) -> Vec<&PriceAlert> {
        let symbol_upper = symbol.to_uppercase();
        self.alerts
            .values()
            .filter(|a| a.symbol == symbol_upper)
            .collect()
    }

    /// Get all active alerts
    pub fn get_active_alerts(&self) -> Vec<&PriceAlert> {
        self.alerts
            .values()
            .filter(|a| a.status == AlertStatus::Active)
            .collect()
    }

    /// Pause an alert
    pub fn pause_alert(&mut self, id: &str) -> HawalaResult<()> {
        let alert = self.alerts.get_mut(id)
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Alert not found"))?;
        
        alert.status = AlertStatus::Paused;
        Ok(())
    }

    /// Resume an alert
    pub fn resume_alert(&mut self, id: &str) -> HawalaResult<()> {
        let alert = self.alerts.get_mut(id)
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Alert not found"))?;
        
        if alert.status == AlertStatus::Paused {
            alert.status = AlertStatus::Active;
        }
        Ok(())
    }

    /// Delete an alert
    pub fn delete_alert(&mut self, id: &str) -> HawalaResult<()> {
        self.alerts.remove(id)
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Alert not found"))?;
        Ok(())
    }

    /// Check all alerts against current prices
    /// Returns list of triggered alerts
    pub fn check_alerts(&mut self) -> Vec<AlertNotification> {
        let mut notifications = Vec::new();
        let now = current_timestamp();

        // Get unique symbols
        let symbols: Vec<String> = self.alerts
            .values()
            .filter(|a| a.status == AlertStatus::Active)
            .map(|a| a.symbol.clone())
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();

        // Fetch prices
        for symbol in &symbols {
            if let Ok(price) = self.fetch_price(symbol) {
                self.price_cache.insert(symbol.clone(), price);
            }
        }

        // Check each alert
        let alert_ids: Vec<String> = self.alerts.keys().cloned().collect();
        
        for id in alert_ids {
            if let Some(alert) = self.alerts.get_mut(&id) {
                // Skip non-active alerts
                if alert.status != AlertStatus::Active {
                    continue;
                }

                // Check expiration
                if let Some(expires) = alert.expires_at {
                    if now > expires {
                        alert.status = AlertStatus::Expired;
                        continue;
                    }
                }

                // Get current price
                let current_price = match self.price_cache.get(&alert.symbol) {
                    Some(data) => data.price,
                    None => continue,
                };

                // Check if triggered
                let triggered = match alert.alert_type {
                    AlertType::Above => current_price >= alert.target_value,
                    AlertType::Below => current_price <= alert.target_value,
                    AlertType::PercentIncrease => {
                        if let Some(base) = alert.base_price {
                            let pct_change = ((current_price - base) / base) * 100.0;
                            pct_change >= alert.target_value
                        } else {
                            false
                        }
                    }
                    AlertType::PercentDecrease => {
                        if let Some(base) = alert.base_price {
                            let pct_change = ((base - current_price) / base) * 100.0;
                            pct_change >= alert.target_value
                        } else {
                            false
                        }
                    }
                    AlertType::PercentChange => {
                        if let Some(base) = alert.base_price {
                            let pct_change = ((current_price - base).abs() / base) * 100.0;
                            pct_change >= alert.target_value
                        } else {
                            false
                        }
                    }
                };

                if triggered {
                    alert.triggered_at = Some(now);
                    alert.triggered_price = Some(current_price);
                    
                    // Clone the alert for the notification before further modification
                    let alert_clone = alert.clone();
                    let message = format_alert_message_static(&alert_clone, current_price);
                    
                    notifications.push(AlertNotification {
                        alert: alert_clone,
                        current_price,
                        message,
                    });

                    if alert.repeat {
                        // Reset for next trigger
                        alert.triggered_at = None;
                        alert.triggered_price = None;
                        // Update base price for percent alerts
                        if alert.base_price.is_some() {
                            alert.base_price = Some(current_price);
                        }
                    } else {
                        alert.status = AlertStatus::Triggered;
                    }
                }
            }
        }

        notifications
    }

    /// Get current price for an asset
    pub fn get_current_price(&self, symbol: &str) -> HawalaResult<f64> {
        // Check cache first
        if let Some(data) = self.price_cache.get(&symbol.to_uppercase()) {
            // Cache valid for 60 seconds
            if current_timestamp() - data.updated_at < 60 {
                return Ok(data.price);
            }
        }

        // Fetch fresh price
        let data = self.fetch_price(symbol)?;
        Ok(data.price)
    }

    /// Get price data with 24h change
    pub fn get_price_data(&mut self, symbol: &str) -> HawalaResult<PriceData> {
        let data = self.fetch_price(symbol)?;
        self.price_cache.insert(symbol.to_uppercase(), data.clone());
        Ok(data)
    }

    /// Get statistics
    pub fn get_stats(&self) -> AlertStats {
        let total = self.alerts.len();
        let active = self.alerts.values().filter(|a| a.status == AlertStatus::Active).count();
        let triggered = self.alerts.values().filter(|a| a.status == AlertStatus::Triggered).count();
        let paused = self.alerts.values().filter(|a| a.status == AlertStatus::Paused).count();

        let mut by_symbol: HashMap<String, usize> = HashMap::new();
        for alert in self.alerts.values() {
            *by_symbol.entry(alert.symbol.clone()).or_default() += 1;
        }

        AlertStats {
            total,
            active,
            triggered,
            paused,
            by_symbol,
        }
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn fetch_price(&self, symbol: &str) -> HawalaResult<PriceData> {
        // Use CoinGecko API
        let symbol_lower = symbol.to_lowercase();
        let coin_id = match symbol_lower.as_str() {
            "btc" | "bitcoin" => "bitcoin",
            "eth" | "ethereum" => "ethereum",
            "sol" | "solana" => "solana",
            "bnb" => "binancecoin",
            "xrp" | "ripple" => "ripple",
            "ada" | "cardano" => "cardano",
            "doge" | "dogecoin" => "dogecoin",
            "dot" | "polkadot" => "polkadot",
            "avax" | "avalanche" => "avalanche-2",
            "matic" | "polygon" => "matic-network",
            "link" | "chainlink" => "chainlink",
            "uni" | "uniswap" => "uniswap",
            "atom" | "cosmos" => "cosmos",
            "ltc" | "litecoin" => "litecoin",
            _ => &symbol_lower,
        };

        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| HawalaError::network_error(e.to_string()))?;

        let url = format!(
            "https://api.coingecko.com/api/v3/simple/price?ids={}&vs_currencies=usd&include_24hr_change=true",
            coin_id
        );

        let response: serde_json::Value = client
            .get(&url)
            .send()
            .map_err(|e| HawalaError::network_error(e.to_string()))?
            .json()
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;

        let price = response[coin_id]["usd"].as_f64()
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Price not found"))?;

        let change_24h_percent = response[coin_id]["usd_24h_change"].as_f64().unwrap_or(0.0);
        let change_24h = price * (change_24h_percent / 100.0);

        Ok(PriceData {
            symbol: symbol.to_uppercase(),
            price,
            change_24h,
            change_24h_percent,
            updated_at: current_timestamp(),
        })
    }

    #[allow(dead_code)]
    fn format_alert_message(&self, alert: &PriceAlert, current_price: f64) -> String {
        match alert.alert_type {
            AlertType::Above => {
                format!(
                    "🔔 {} is now above ${:.2}! Current: ${:.2}",
                    alert.symbol, alert.target_value, current_price
                )
            }
            AlertType::Below => {
                format!(
                    "🔔 {} dropped below ${:.2}! Current: ${:.2}",
                    alert.symbol, alert.target_value, current_price
                )
            }
            AlertType::PercentIncrease => {
                let base = alert.base_price.unwrap_or(0.0);
                let pct = ((current_price - base) / base) * 100.0;
                format!(
                    "📈 {} is up {:.1}%! ${:.2} → ${:.2}",
                    alert.symbol, pct, base, current_price
                )
            }
            AlertType::PercentDecrease => {
                let base = alert.base_price.unwrap_or(0.0);
                let pct = ((base - current_price) / base) * 100.0;
                format!(
                    "📉 {} is down {:.1}%! ${:.2} → ${:.2}",
                    alert.symbol, pct, base, current_price
                )
            }
            AlertType::PercentChange => {
                let base = alert.base_price.unwrap_or(0.0);
                let pct = ((current_price - base) / base) * 100.0;
                let direction = if pct > 0.0 { "up" } else { "down" };
                format!(
                    "🔔 {} moved {:.1}% {}! ${:.2} → ${:.2}",
                    alert.symbol, pct.abs(), direction, base, current_price
                )
            }
        }
    }
}

/// Static version of format_alert_message for use in borrow-sensitive contexts
fn format_alert_message_static(alert: &PriceAlert, current_price: f64) -> String {
    match alert.alert_type {
        AlertType::Above => {
            format!(
                "🔔 {} is now above ${:.2}! Current: ${:.2}",
                alert.symbol, alert.target_value, current_price
            )
        }
        AlertType::Below => {
            format!(
                "🔔 {} dropped below ${:.2}! Current: ${:.2}",
                alert.symbol, alert.target_value, current_price
            )
        }
        AlertType::PercentIncrease => {
            let base = alert.base_price.unwrap_or(0.0);
            let pct = ((current_price - base) / base) * 100.0;
            format!(
                "📈 {} is up {:.1}%! ${:.2} → ${:.2}",
                alert.symbol, pct, base, current_price
            )
        }
        AlertType::PercentDecrease => {
            let base = alert.base_price.unwrap_or(0.0);
            let pct = ((base - current_price) / base) * 100.0;
            format!(
                "📉 {} is down {:.1}%! ${:.2} → ${:.2}",
                alert.symbol, pct, base, current_price
            )
        }
        AlertType::PercentChange => {
            let base = alert.base_price.unwrap_or(0.0);
            let pct = ((current_price - base) / base) * 100.0;
            let direction = if pct > 0.0 { "up" } else { "down" };
            format!(
                "🔔 {} moved {:.1}% {}! ${:.2} → ${:.2}",
                alert.symbol, pct.abs(), direction, base, current_price
            )
        }
    }
}

impl Default for PriceAlertManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Alert statistics
#[derive(Debug, Clone, Serialize)]
pub struct AlertStats {
    pub total: usize,
    pub active: usize,
    pub triggered: usize,
    pub paused: usize,
    pub by_symbol: HashMap<String, usize>,
}

// =============================================================================
// Helper Functions
// =============================================================================

fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_alert() {
        let mut manager = PriceAlertManager::new();
        
        let request = CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            note: Some("Moon target".to_string()),
            repeat: false,
            expires_at: None,
        };

        let alert = manager.create_alert(request).unwrap();
        assert_eq!(alert.symbol, "BTC");
        assert_eq!(alert.alert_type, AlertType::Above);
        assert_eq!(alert.target_value, 100000.0);
        assert_eq!(alert.status, AlertStatus::Active);
    }

    #[test]
    fn test_get_alert() {
        let mut manager = PriceAlertManager::new();
        
        let request = CreateAlertRequest {
            symbol: "ETH".to_string(),
            alert_type: AlertType::Below,
            target_value: 2000.0,
            note: None,
            repeat: false,
            expires_at: None,
        };

        let created = manager.create_alert(request).unwrap();
        let fetched = manager.get_alert(&created.id);
        
        assert!(fetched.is_some());
        assert_eq!(fetched.unwrap().symbol, "ETH");
    }

    #[test]
    fn test_pause_resume_alert() {
        let mut manager = PriceAlertManager::new();
        
        let request = CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            note: None,
            repeat: false,
            expires_at: None,
        };

        let alert = manager.create_alert(request).unwrap();
        
        manager.pause_alert(&alert.id).unwrap();
        assert_eq!(manager.get_alert(&alert.id).unwrap().status, AlertStatus::Paused);
        
        manager.resume_alert(&alert.id).unwrap();
        assert_eq!(manager.get_alert(&alert.id).unwrap().status, AlertStatus::Active);
    }

    #[test]
    fn test_delete_alert() {
        let mut manager = PriceAlertManager::new();
        
        let request = CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            note: None,
            repeat: false,
            expires_at: None,
        };

        let alert = manager.create_alert(request).unwrap();
        assert!(manager.get_alert(&alert.id).is_some());
        
        manager.delete_alert(&alert.id).unwrap();
        assert!(manager.get_alert(&alert.id).is_none());
    }

    #[test]
    fn test_get_active_alerts() {
        let mut manager = PriceAlertManager::new();
        
        // Create two alerts
        manager.create_alert(CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            note: None,
            repeat: false,
            expires_at: None,
        }).unwrap();

        let eth_alert = manager.create_alert(CreateAlertRequest {
            symbol: "ETH".to_string(),
            alert_type: AlertType::Below,
            target_value: 2000.0,
            note: None,
            repeat: false,
            expires_at: None,
        }).unwrap();

        // Pause one
        manager.pause_alert(&eth_alert.id).unwrap();

        // Only one should be active
        let active = manager.get_active_alerts();
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].symbol, "BTC");
    }

    #[test]
    fn test_get_stats() {
        let mut manager = PriceAlertManager::new();
        
        manager.create_alert(CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            note: None,
            repeat: false,
            expires_at: None,
        }).unwrap();

        manager.create_alert(CreateAlertRequest {
            symbol: "BTC".to_string(),
            alert_type: AlertType::Below,
            target_value: 50000.0,
            note: None,
            repeat: false,
            expires_at: None,
        }).unwrap();

        manager.create_alert(CreateAlertRequest {
            symbol: "ETH".to_string(),
            alert_type: AlertType::Above,
            target_value: 5000.0,
            note: None,
            repeat: false,
            expires_at: None,
        }).unwrap();

        let stats = manager.get_stats();
        assert_eq!(stats.total, 3);
        assert_eq!(stats.active, 3);
        assert_eq!(stats.by_symbol.get("BTC"), Some(&2));
        assert_eq!(stats.by_symbol.get("ETH"), Some(&1));
    }

    #[test]
    fn test_format_alert_messages() {
        let manager = PriceAlertManager::new();
        
        let above_alert = PriceAlert {
            id: "test".to_string(),
            symbol: "BTC".to_string(),
            alert_type: AlertType::Above,
            target_value: 100000.0,
            base_price: None,
            status: AlertStatus::Active,
            created_at: 0,
            triggered_at: None,
            triggered_price: None,
            note: None,
            repeat: false,
            expires_at: None,
        };

        let msg = manager.format_alert_message(&above_alert, 105000.0);
        assert!(msg.contains("BTC"));
        assert!(msg.contains("above"));
    }
}
