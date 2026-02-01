//! Price charts and historical data module
//! 
//! Provides:
//! - Historical price data from CoinGecko
//! - Candlestick (OHLC) data
//! - Price change calculations
//! - Volume data
//! - Multiple time ranges

pub mod types;
pub mod coingecko;
pub mod calculator;
#[cfg(test)]
pub mod tests;

pub use types::*;
pub use coingecko::*;
pub use calculator::*;
