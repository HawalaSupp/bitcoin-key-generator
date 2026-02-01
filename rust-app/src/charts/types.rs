//! Price chart types and data structures

use std::fmt;

/// Time range for historical data
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TimeRange {
    Hour1,
    Hour24,
    Day7,
    Day30,
    Day90,
    Year1,
    All,
}

impl TimeRange {
    /// Get days for CoinGecko API
    pub fn days(&self) -> &str {
        match self {
            TimeRange::Hour1 => "1",
            TimeRange::Hour24 => "1",
            TimeRange::Day7 => "7",
            TimeRange::Day30 => "30",
            TimeRange::Day90 => "90",
            TimeRange::Year1 => "365",
            TimeRange::All => "max",
        }
    }
    
    /// Get interval for data points
    pub fn interval(&self) -> Option<&str> {
        match self {
            TimeRange::Hour1 => None, // 5-minute data
            TimeRange::Hour24 => None, // Hourly data
            TimeRange::Day7 => None, // Hourly data
            TimeRange::Day30 => Some("daily"),
            TimeRange::Day90 => Some("daily"),
            TimeRange::Year1 => Some("daily"),
            TimeRange::All => Some("daily"),
        }
    }
    
    pub fn display_name(&self) -> &str {
        match self {
            TimeRange::Hour1 => "1H",
            TimeRange::Hour24 => "24H",
            TimeRange::Day7 => "7D",
            TimeRange::Day30 => "30D",
            TimeRange::Day90 => "90D",
            TimeRange::Year1 => "1Y",
            TimeRange::All => "ALL",
        }
    }
}

impl fmt::Display for TimeRange {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

/// Single price point with timestamp
#[derive(Debug, Clone)]
pub struct PricePoint {
    /// Unix timestamp in milliseconds
    pub timestamp: u64,
    /// Price in fiat currency
    pub price: f64,
}

impl PricePoint {
    pub fn new(timestamp: u64, price: f64) -> Self {
        Self { timestamp, price }
    }
}

/// OHLC candlestick data
#[derive(Debug, Clone)]
pub struct Candlestick {
    /// Unix timestamp in milliseconds
    pub timestamp: u64,
    /// Opening price
    pub open: f64,
    /// Highest price
    pub high: f64,
    /// Lowest price
    pub low: f64,
    /// Closing price
    pub close: f64,
}

impl Candlestick {
    pub fn new(timestamp: u64, open: f64, high: f64, low: f64, close: f64) -> Self {
        Self { timestamp, open, high, low, close }
    }
    
    /// Check if bullish (close > open)
    pub fn is_bullish(&self) -> bool {
        self.close > self.open
    }
    
    /// Check if bearish (close < open)
    pub fn is_bearish(&self) -> bool {
        self.close < self.open
    }
    
    /// Get body size (absolute difference between open and close)
    pub fn body_size(&self) -> f64 {
        (self.close - self.open).abs()
    }
    
    /// Get wick size (high - max(open, close))
    pub fn upper_wick(&self) -> f64 {
        self.high - self.open.max(self.close)
    }
    
    /// Get tail size (min(open, close) - low)
    pub fn lower_wick(&self) -> f64 {
        self.open.min(self.close) - self.low
    }
}

/// Volume data point
#[derive(Debug, Clone)]
pub struct VolumePoint {
    /// Unix timestamp in milliseconds
    pub timestamp: u64,
    /// Trading volume in fiat
    pub volume: f64,
}

impl VolumePoint {
    pub fn new(timestamp: u64, volume: f64) -> Self {
        Self { timestamp, volume }
    }
}

/// Market cap data point
#[derive(Debug, Clone)]
pub struct MarketCapPoint {
    /// Unix timestamp in milliseconds
    pub timestamp: u64,
    /// Market cap in fiat
    pub market_cap: f64,
}

impl MarketCapPoint {
    pub fn new(timestamp: u64, market_cap: f64) -> Self {
        Self { timestamp, market_cap }
    }
}

/// Complete chart data response
#[derive(Debug, Clone)]
pub struct ChartData {
    /// Token ID (e.g., "bitcoin", "ethereum")
    pub token_id: String,
    /// Currency for prices (e.g., "usd", "eur")
    pub currency: String,
    /// Time range
    pub range: TimeRange,
    /// Price data points
    pub prices: Vec<PricePoint>,
    /// Volume data points
    pub volumes: Vec<VolumePoint>,
    /// Market cap data points
    pub market_caps: Vec<MarketCapPoint>,
}

impl ChartData {
    pub fn new(token_id: String, currency: String, range: TimeRange) -> Self {
        Self {
            token_id,
            currency,
            range,
            prices: Vec::new(),
            volumes: Vec::new(),
            market_caps: Vec::new(),
        }
    }
    
    /// Get current price (last data point)
    pub fn current_price(&self) -> Option<f64> {
        self.prices.last().map(|p| p.price)
    }
    
    /// Get price at start of period
    pub fn start_price(&self) -> Option<f64> {
        self.prices.first().map(|p| p.price)
    }
    
    /// Get highest price in range
    pub fn high_price(&self) -> Option<f64> {
        self.prices.iter().map(|p| p.price).reduce(f64::max)
    }
    
    /// Get lowest price in range
    pub fn low_price(&self) -> Option<f64> {
        self.prices.iter().map(|p| p.price).reduce(f64::min)
    }
    
    /// Get price change amount
    pub fn price_change(&self) -> Option<f64> {
        match (self.start_price(), self.current_price()) {
            (Some(start), Some(current)) => Some(current - start),
            _ => None,
        }
    }
    
    /// Get price change percentage
    pub fn price_change_percent(&self) -> Option<f64> {
        match (self.start_price(), self.current_price()) {
            (Some(start), Some(current)) if start > 0.0 => {
                Some(((current - start) / start) * 100.0)
            }
            _ => None,
        }
    }
    
    /// Check if price is up
    pub fn is_price_up(&self) -> bool {
        self.price_change().map(|c| c > 0.0).unwrap_or(false)
    }
    
    /// Get average volume
    pub fn average_volume(&self) -> Option<f64> {
        if self.volumes.is_empty() {
            return None;
        }
        let sum: f64 = self.volumes.iter().map(|v| v.volume).sum();
        Some(sum / self.volumes.len() as f64)
    }
}

/// OHLC chart data with candlesticks
#[derive(Debug, Clone)]
pub struct OHLCData {
    /// Token ID
    pub token_id: String,
    /// Currency
    pub currency: String,
    /// Time range
    pub range: TimeRange,
    /// Candlestick data
    pub candles: Vec<Candlestick>,
}

impl OHLCData {
    pub fn new(token_id: String, currency: String, range: TimeRange) -> Self {
        Self {
            token_id,
            currency,
            range,
            candles: Vec::new(),
        }
    }
    
    /// Get current price (last candle close)
    pub fn current_price(&self) -> Option<f64> {
        self.candles.last().map(|c| c.close)
    }
    
    /// Get highest price
    pub fn high_price(&self) -> Option<f64> {
        self.candles.iter().map(|c| c.high).reduce(f64::max)
    }
    
    /// Get lowest price
    pub fn low_price(&self) -> Option<f64> {
        self.candles.iter().map(|c| c.low).reduce(f64::min)
    }
}

/// Token info for chart display
#[derive(Debug, Clone)]
pub struct TokenInfo {
    pub id: String,
    pub symbol: String,
    pub name: String,
    pub current_price: f64,
    pub price_change_24h: f64,
    pub price_change_percentage_24h: f64,
    pub market_cap: f64,
    pub market_cap_rank: Option<u32>,
    pub total_volume: f64,
    pub high_24h: f64,
    pub low_24h: f64,
    pub ath: f64,
    pub ath_change_percentage: f64,
    pub atl: f64,
    pub atl_change_percentage: f64,
    pub circulating_supply: f64,
    pub total_supply: Option<f64>,
    pub max_supply: Option<f64>,
    pub image_url: Option<String>,
}

impl Default for TokenInfo {
    fn default() -> Self {
        Self {
            id: String::new(),
            symbol: String::new(),
            name: String::new(),
            current_price: 0.0,
            price_change_24h: 0.0,
            price_change_percentage_24h: 0.0,
            market_cap: 0.0,
            market_cap_rank: None,
            total_volume: 0.0,
            high_24h: 0.0,
            low_24h: 0.0,
            ath: 0.0,
            ath_change_percentage: 0.0,
            atl: 0.0,
            atl_change_percentage: 0.0,
            circulating_supply: 0.0,
            total_supply: None,
            max_supply: None,
            image_url: None,
        }
    }
}

/// Chart error types
#[derive(Debug, Clone)]
pub enum ChartError {
    NetworkError(String),
    ParseError(String),
    RateLimited,
    InvalidToken(String),
    NoData,
}

impl fmt::Display for ChartError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ChartError::NetworkError(msg) => write!(f, "Network error: {}", msg),
            ChartError::ParseError(msg) => write!(f, "Parse error: {}", msg),
            ChartError::RateLimited => write!(f, "Rate limited - try again later"),
            ChartError::InvalidToken(id) => write!(f, "Invalid token: {}", id),
            ChartError::NoData => write!(f, "No data available"),
        }
    }
}

impl std::error::Error for ChartError {}

/// Supported fiat currencies
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FiatCurrency {
    USD,
    EUR,
    GBP,
    JPY,
    CNY,
    KRW,
    CAD,
    AUD,
    CHF,
    INR,
}

impl FiatCurrency {
    pub fn code(&self) -> &str {
        match self {
            FiatCurrency::USD => "usd",
            FiatCurrency::EUR => "eur",
            FiatCurrency::GBP => "gbp",
            FiatCurrency::JPY => "jpy",
            FiatCurrency::CNY => "cny",
            FiatCurrency::KRW => "krw",
            FiatCurrency::CAD => "cad",
            FiatCurrency::AUD => "aud",
            FiatCurrency::CHF => "chf",
            FiatCurrency::INR => "inr",
        }
    }
    
    pub fn symbol(&self) -> &str {
        match self {
            FiatCurrency::USD => "$",
            FiatCurrency::EUR => "€",
            FiatCurrency::GBP => "£",
            FiatCurrency::JPY => "¥",
            FiatCurrency::CNY => "¥",
            FiatCurrency::KRW => "₩",
            FiatCurrency::CAD => "C$",
            FiatCurrency::AUD => "A$",
            FiatCurrency::CHF => "CHF",
            FiatCurrency::INR => "₹",
        }
    }
}

impl fmt::Display for FiatCurrency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.code().to_uppercase())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_time_range_days() {
        assert_eq!(TimeRange::Hour24.days(), "1");
        assert_eq!(TimeRange::Day7.days(), "7");
        assert_eq!(TimeRange::Day30.days(), "30");
        assert_eq!(TimeRange::Year1.days(), "365");
        assert_eq!(TimeRange::All.days(), "max");
    }
    
    #[test]
    fn test_candlestick() {
        let bullish = Candlestick::new(1000, 100.0, 110.0, 95.0, 105.0);
        assert!(bullish.is_bullish());
        assert!(!bullish.is_bearish());
        assert_eq!(bullish.body_size(), 5.0);
        
        let bearish = Candlestick::new(1000, 105.0, 110.0, 95.0, 100.0);
        assert!(!bearish.is_bullish());
        assert!(bearish.is_bearish());
    }
    
    #[test]
    fn test_chart_data_calculations() {
        let mut data = ChartData::new("bitcoin".into(), "usd".into(), TimeRange::Day7);
        data.prices.push(PricePoint::new(1000, 100.0));
        data.prices.push(PricePoint::new(2000, 110.0));
        data.prices.push(PricePoint::new(3000, 105.0));
        
        assert_eq!(data.current_price(), Some(105.0));
        assert_eq!(data.start_price(), Some(100.0));
        assert_eq!(data.high_price(), Some(110.0));
        assert_eq!(data.low_price(), Some(100.0));
        assert_eq!(data.price_change(), Some(5.0));
        assert_eq!(data.price_change_percent(), Some(5.0));
        assert!(data.is_price_up());
    }
    
    #[test]
    fn test_fiat_currency() {
        assert_eq!(FiatCurrency::USD.code(), "usd");
        assert_eq!(FiatCurrency::USD.symbol(), "$");
        assert_eq!(FiatCurrency::EUR.symbol(), "€");
        assert_eq!(FiatCurrency::GBP.symbol(), "£");
    }
}
