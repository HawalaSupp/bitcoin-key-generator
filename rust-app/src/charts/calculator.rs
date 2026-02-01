//! Chart calculations and technical indicators

#[allow(unused_imports)]
use super::types::*;

/// Technical analysis calculator
pub struct ChartCalculator;

impl ChartCalculator {
    /// Calculate Simple Moving Average (SMA)
    pub fn sma(prices: &[f64], period: usize) -> Vec<f64> {
        if prices.len() < period || period == 0 {
            return vec![];
        }
        
        let mut result = Vec::with_capacity(prices.len() - period + 1);
        let mut sum: f64 = prices[..period].iter().sum();
        result.push(sum / period as f64);
        
        for i in period..prices.len() {
            sum = sum - prices[i - period] + prices[i];
            result.push(sum / period as f64);
        }
        
        result
    }
    
    /// Calculate Exponential Moving Average (EMA)
    pub fn ema(prices: &[f64], period: usize) -> Vec<f64> {
        if prices.len() < period || period == 0 {
            return vec![];
        }
        
        let multiplier = 2.0 / (period as f64 + 1.0);
        let mut result = Vec::with_capacity(prices.len() - period + 1);
        
        // First EMA is SMA
        let sma: f64 = prices[..period].iter().sum::<f64>() / period as f64;
        result.push(sma);
        
        // Calculate EMA for remaining prices
        for i in period..prices.len() {
            let ema = (prices[i] - result.last().unwrap()) * multiplier + result.last().unwrap();
            result.push(ema);
        }
        
        result
    }
    
    /// Calculate Bollinger Bands
    pub fn bollinger_bands(prices: &[f64], period: usize, std_dev: f64) -> BollingerBands {
        let sma = Self::sma(prices, period);
        
        if sma.is_empty() {
            return BollingerBands::default();
        }
        
        let mut upper = Vec::with_capacity(sma.len());
        let mut lower = Vec::with_capacity(sma.len());
        
        for (i, &middle) in sma.iter().enumerate() {
            let start = i;
            let end = i + period;
            
            if end <= prices.len() {
                let slice = &prices[start..end];
                let variance: f64 = slice.iter().map(|&x| (x - middle).powi(2)).sum::<f64>() / period as f64;
                let std = variance.sqrt();
                
                upper.push(middle + std_dev * std);
                lower.push(middle - std_dev * std);
            }
        }
        
        BollingerBands { middle: sma, upper, lower }
    }
    
    /// Calculate RSI (Relative Strength Index)
    pub fn rsi(prices: &[f64], period: usize) -> Vec<f64> {
        if prices.len() <= period {
            return vec![];
        }
        
        let mut gains = Vec::new();
        let mut losses = Vec::new();
        
        // Calculate price changes
        for i in 1..prices.len() {
            let change = prices[i] - prices[i - 1];
            if change > 0.0 {
                gains.push(change);
                losses.push(0.0);
            } else {
                gains.push(0.0);
                losses.push(-change);
            }
        }
        
        if gains.len() < period {
            return vec![];
        }
        
        // Calculate initial averages
        let mut avg_gain: f64 = gains[..period].iter().sum::<f64>() / period as f64;
        let mut avg_loss: f64 = losses[..period].iter().sum::<f64>() / period as f64;
        
        let mut result = Vec::new();
        
        // First RSI
        let rs = if avg_loss == 0.0 { 100.0 } else { avg_gain / avg_loss };
        result.push(100.0 - (100.0 / (1.0 + rs)));
        
        // Smoothed RSI
        for i in period..gains.len() {
            avg_gain = (avg_gain * (period - 1) as f64 + gains[i]) / period as f64;
            avg_loss = (avg_loss * (period - 1) as f64 + losses[i]) / period as f64;
            
            let rs = if avg_loss == 0.0 { 100.0 } else { avg_gain / avg_loss };
            result.push(100.0 - (100.0 / (1.0 + rs)));
        }
        
        result
    }
    
    /// Calculate MACD (Moving Average Convergence Divergence)
    pub fn macd(prices: &[f64], fast: usize, slow: usize, signal: usize) -> MACD {
        if prices.len() < slow {
            return MACD::default();
        }
        
        let fast_ema = Self::ema(prices, fast);
        let slow_ema = Self::ema(prices, slow);
        
        // Align EMAs (slow has fewer points)
        let offset = fast_ema.len() - slow_ema.len();
        let fast_aligned = &fast_ema[offset..];
        
        // MACD line = fast EMA - slow EMA
        let mut macd_line: Vec<f64> = fast_aligned.iter()
            .zip(slow_ema.iter())
            .map(|(&f, &s)| f - s)
            .collect();
        
        // Signal line = EMA of MACD line
        let signal_line = Self::ema(&macd_line, signal);
        
        // Histogram = MACD - Signal
        let offset2 = macd_line.len() - signal_line.len();
        macd_line = macd_line[offset2..].to_vec();
        
        let histogram: Vec<f64> = macd_line.iter()
            .zip(signal_line.iter())
            .map(|(&m, &s)| m - s)
            .collect();
        
        MACD { macd_line, signal_line, histogram }
    }
    
    /// Calculate percentage change
    pub fn percentage_change(old: f64, new: f64) -> f64 {
        if old == 0.0 {
            return 0.0;
        }
        ((new - old) / old) * 100.0
    }
    
    /// Calculate volatility (standard deviation of returns)
    pub fn volatility(prices: &[f64]) -> f64 {
        if prices.len() < 2 {
            return 0.0;
        }
        
        let returns: Vec<f64> = prices.windows(2)
            .map(|w| (w[1] - w[0]) / w[0])
            .collect();
        
        let mean: f64 = returns.iter().sum::<f64>() / returns.len() as f64;
        let variance: f64 = returns.iter().map(|&r| (r - mean).powi(2)).sum::<f64>() / returns.len() as f64;
        
        variance.sqrt()
    }
    
    /// Normalize prices to 0-100 range for chart display
    pub fn normalize(prices: &[f64]) -> Vec<f64> {
        if prices.is_empty() {
            return vec![];
        }
        
        let min = prices.iter().cloned().reduce(f64::min).unwrap_or(0.0);
        let max = prices.iter().cloned().reduce(f64::max).unwrap_or(0.0);
        let range = max - min;
        
        if range == 0.0 {
            return vec![50.0; prices.len()];
        }
        
        prices.iter().map(|&p| ((p - min) / range) * 100.0).collect()
    }
    
    /// Calculate support and resistance levels
    pub fn support_resistance(prices: &[f64], num_levels: usize) -> SupportResistance {
        if prices.is_empty() || num_levels == 0 {
            return SupportResistance::default();
        }
        
        let current = *prices.last().unwrap();
        
        // Find local minima (support) and maxima (resistance)
        let mut supports = Vec::new();
        let mut resistances = Vec::new();
        
        for i in 1..prices.len().saturating_sub(1) {
            let prev = prices[i - 1];
            let curr = prices[i];
            let next = prices[i + 1];
            
            if curr < prev && curr < next && curr < current {
                supports.push(curr);
            } else if curr > prev && curr > next && curr > current {
                resistances.push(curr);
            }
        }
        
        // Sort and take top levels
        supports.sort_by(|a, b| b.partial_cmp(a).unwrap()); // Descending (nearest first)
        resistances.sort_by(|a, b| a.partial_cmp(b).unwrap()); // Ascending (nearest first)
        
        supports.truncate(num_levels);
        resistances.truncate(num_levels);
        
        SupportResistance { supports, resistances }
    }
}

/// Bollinger Bands result
#[derive(Debug, Clone, Default)]
pub struct BollingerBands {
    pub middle: Vec<f64>,
    pub upper: Vec<f64>,
    pub lower: Vec<f64>,
}

/// MACD result
#[derive(Debug, Clone, Default)]
pub struct MACD {
    pub macd_line: Vec<f64>,
    pub signal_line: Vec<f64>,
    pub histogram: Vec<f64>,
}

/// Support and resistance levels
#[derive(Debug, Clone, Default)]
pub struct SupportResistance {
    pub supports: Vec<f64>,
    pub resistances: Vec<f64>,
}

/// Price statistics
#[derive(Debug, Clone)]
pub struct PriceStats {
    pub current: f64,
    pub open: f64,
    pub high: f64,
    pub low: f64,
    pub change: f64,
    pub change_percent: f64,
    pub volatility: f64,
}

impl PriceStats {
    pub fn from_prices(prices: &[f64]) -> Option<Self> {
        if prices.is_empty() {
            return None;
        }
        
        let current = *prices.last().unwrap();
        let open = *prices.first().unwrap();
        let high = prices.iter().cloned().reduce(f64::max).unwrap();
        let low = prices.iter().cloned().reduce(f64::min).unwrap();
        let change = current - open;
        let change_percent = ChartCalculator::percentage_change(open, current);
        let volatility = ChartCalculator::volatility(prices);
        
        Some(Self {
            current,
            open,
            high,
            low,
            change,
            change_percent,
            volatility,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_sma() {
        let prices = vec![10.0, 11.0, 12.0, 13.0, 14.0, 15.0];
        let sma = ChartCalculator::sma(&prices, 3);
        
        assert_eq!(sma.len(), 4);
        assert!((sma[0] - 11.0).abs() < 0.001); // (10+11+12)/3 = 11
        assert!((sma[1] - 12.0).abs() < 0.001); // (11+12+13)/3 = 12
        assert!((sma[2] - 13.0).abs() < 0.001);
        assert!((sma[3] - 14.0).abs() < 0.001);
    }
    
    #[test]
    fn test_ema() {
        let prices = vec![10.0, 11.0, 12.0, 13.0, 14.0];
        let ema = ChartCalculator::ema(&prices, 3);
        
        assert!(!ema.is_empty());
        // First EMA = SMA = 11
        assert!((ema[0] - 11.0).abs() < 0.001);
    }
    
    #[test]
    fn test_rsi() {
        // Simple uptrend
        let prices = vec![10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0];
        let rsi = ChartCalculator::rsi(&prices, 5);
        
        assert!(!rsi.is_empty());
        // In uptrend, RSI should be high
        assert!(rsi[0] > 50.0);
    }
    
    #[test]
    fn test_percentage_change() {
        assert!((ChartCalculator::percentage_change(100.0, 110.0) - 10.0).abs() < 0.001);
        assert!((ChartCalculator::percentage_change(100.0, 90.0) - (-10.0)).abs() < 0.001);
        assert_eq!(ChartCalculator::percentage_change(0.0, 100.0), 0.0);
    }
    
    #[test]
    fn test_normalize() {
        let prices = vec![100.0, 150.0, 200.0];
        let normalized = ChartCalculator::normalize(&prices);
        
        assert_eq!(normalized.len(), 3);
        assert!((normalized[0] - 0.0).abs() < 0.001);
        assert!((normalized[1] - 50.0).abs() < 0.001);
        assert!((normalized[2] - 100.0).abs() < 0.001);
    }
    
    #[test]
    fn test_volatility() {
        let stable = vec![100.0, 100.0, 100.0, 100.0];
        let volatile = vec![100.0, 110.0, 90.0, 120.0];
        
        assert!(ChartCalculator::volatility(&stable) < 0.001);
        assert!(ChartCalculator::volatility(&volatile) > 0.1);
    }
    
    #[test]
    fn test_bollinger_bands() {
        let prices = vec![10.0, 11.0, 12.0, 11.5, 12.5, 13.0, 12.0, 11.0, 12.0, 13.0];
        let bands = ChartCalculator::bollinger_bands(&prices, 5, 2.0);
        
        assert!(!bands.middle.is_empty());
        assert!(!bands.upper.is_empty());
        assert!(!bands.lower.is_empty());
        
        // Upper should be above middle, lower below
        for i in 0..bands.middle.len() {
            assert!(bands.upper[i] > bands.middle[i]);
            assert!(bands.lower[i] < bands.middle[i]);
        }
    }
    
    #[test]
    fn test_price_stats() {
        let prices = vec![100.0, 110.0, 90.0, 120.0, 105.0];
        let stats = PriceStats::from_prices(&prices).unwrap();
        
        assert_eq!(stats.current, 105.0);
        assert_eq!(stats.open, 100.0);
        assert_eq!(stats.high, 120.0);
        assert_eq!(stats.low, 90.0);
        assert_eq!(stats.change, 5.0);
        assert!((stats.change_percent - 5.0).abs() < 0.001);
    }
}
