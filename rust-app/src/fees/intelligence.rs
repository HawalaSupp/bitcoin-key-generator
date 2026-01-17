//! Fee Intelligence
//!
//! Smart fee analysis and recommendations.
//! Analyzes current fees vs historical patterns.

use crate::error::HawalaResult;
use crate::types::*;
use serde::{Deserialize, Serialize};

/// Fee intelligence analysis result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeeIntelligence {
    pub chain: Chain,
    pub recommended_level: RecommendedFeeLevel,
    pub confidence: f64,
    pub congestion: CongestionLevel,
    pub time_estimates: TimeEstimates,
    pub analysis: String,
}

/// Recommended fee level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecommendedFeeLevel {
    Low,
    Medium,
    High,
    Urgent,
}

/// Network congestion level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CongestionLevel {
    Low,
    Normal,
    High,
    Extreme,
}

/// Time estimates for different fee levels
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeEstimates {
    pub low_minutes: u32,
    pub medium_minutes: u32,
    pub high_minutes: u32,
}

/// Analyze Bitcoin fees and provide recommendations
pub fn analyze_bitcoin_fees(estimate: &BitcoinFeeEstimate) -> HawalaResult<FeeIntelligence> {
    // Calculate congestion from fee spread
    let fee_spread = estimate.fastest.rate as f64 / estimate.slow.rate.max(1) as f64;
    
    let congestion = if fee_spread > 10.0 {
        CongestionLevel::Extreme
    } else if fee_spread > 5.0 {
        CongestionLevel::High
    } else if fee_spread > 2.0 {
        CongestionLevel::Normal
    } else {
        CongestionLevel::Low
    };
    
    // Recommend fee level based on congestion
    let recommended = match congestion {
        CongestionLevel::Extreme => RecommendedFeeLevel::Urgent,
        CongestionLevel::High => RecommendedFeeLevel::High,
        CongestionLevel::Normal => RecommendedFeeLevel::Medium,
        CongestionLevel::Low => RecommendedFeeLevel::Low,
    };
    
    // Confidence based on fee data quality
    let confidence = if estimate.fastest.rate > 0 && estimate.slow.rate > 0 {
        0.9
    } else {
        0.5
    };
    
    let analysis = format!(
        "Network {} congested. Fee spread: {:.1}x. Recommended: {} priority.",
        match congestion {
            CongestionLevel::Extreme => "extremely",
            CongestionLevel::High => "highly",
            CongestionLevel::Normal => "moderately",
            CongestionLevel::Low => "minimally",
        },
        fee_spread,
        match recommended {
            RecommendedFeeLevel::Urgent => "urgent",
            RecommendedFeeLevel::High => "high",
            RecommendedFeeLevel::Medium => "medium",
            RecommendedFeeLevel::Low => "low",
        }
    );
    
    Ok(FeeIntelligence {
        chain: Chain::Bitcoin,
        recommended_level: recommended,
        confidence,
        congestion,
        time_estimates: TimeEstimates {
            low_minutes: estimate.slow.estimated_minutes,
            medium_minutes: estimate.medium.estimated_minutes,
            high_minutes: estimate.fast.estimated_minutes,
        },
        analysis,
    })
}

/// Analyze EVM fees and provide recommendations
pub fn analyze_evm_fees(estimate: &EvmFeeEstimate, chain: Chain) -> HawalaResult<FeeIntelligence> {
    // Parse base fee
    let base_fee: u64 = estimate.base_fee.parse().unwrap_or(0);
    let base_fee_gwei = base_fee as f64 / 1_000_000_000.0;
    
    // Determine congestion based on base fee (for Ethereum mainnet)
    let congestion = if chain.chain_id() == Some(1) {
        if base_fee_gwei > 100.0 {
            CongestionLevel::Extreme
        } else if base_fee_gwei > 50.0 {
            CongestionLevel::High
        } else if base_fee_gwei > 20.0 {
            CongestionLevel::Normal
        } else {
            CongestionLevel::Low
        }
    } else {
        // L2s and sidechains typically have low congestion
        CongestionLevel::Low
    };
    
    let recommended = match congestion {
        CongestionLevel::Extreme => RecommendedFeeLevel::Urgent,
        CongestionLevel::High => RecommendedFeeLevel::High,
        CongestionLevel::Normal => RecommendedFeeLevel::Medium,
        CongestionLevel::Low => RecommendedFeeLevel::Low,
    };
    
    let analysis = format!(
        "Base fee: {:.1} Gwei. Network {}. Use {} priority for optimal confirmation.",
        base_fee_gwei,
        match congestion {
            CongestionLevel::Extreme => "extremely congested",
            CongestionLevel::High => "congested",
            CongestionLevel::Normal => "normal",
            CongestionLevel::Low => "uncongested",
        },
        match recommended {
            RecommendedFeeLevel::Urgent => "urgent",
            RecommendedFeeLevel::High => "high",
            RecommendedFeeLevel::Medium => "medium",
            RecommendedFeeLevel::Low => "low",
        }
    );
    
    Ok(FeeIntelligence {
        chain,
        recommended_level: recommended,
        confidence: 0.85,
        congestion,
        time_estimates: TimeEstimates {
            low_minutes: 5,
            medium_minutes: 2,
            high_minutes: 1,
        },
        analysis,
    })
}

/// Analyze Solana fees
pub fn analyze_solana_fees(estimate: &SolanaFeeEstimate) -> HawalaResult<FeeIntelligence> {
    // Solana generally has low congestion
    let congestion = if estimate.priority_fee_high > 1_000_000 {
        CongestionLevel::High
    } else if estimate.priority_fee_high > 100_000 {
        CongestionLevel::Normal
    } else {
        CongestionLevel::Low
    };
    
    let analysis = format!(
        "Solana network {}. Base fee: {} lamports, priority fees available.",
        match congestion {
            CongestionLevel::High => "busy",
            CongestionLevel::Normal => "normal",
            CongestionLevel::Low | CongestionLevel::Extreme => "fast",
        },
        estimate.base_fee_lamports
    );
    
    Ok(FeeIntelligence {
        chain: Chain::Solana,
        recommended_level: RecommendedFeeLevel::Medium,
        confidence: 0.8,
        congestion,
        time_estimates: TimeEstimates {
            low_minutes: 1,
            medium_minutes: 1,
            high_minutes: 1,
        },
        analysis,
    })
}

/// Analyze XRP fees
pub fn analyze_xrp_fees(estimate: &XrpFeeEstimate) -> HawalaResult<FeeIntelligence> {
    // XRP congestion based on queue size
    let congestion = if estimate.current_queue_size > 1000 {
        CongestionLevel::High
    } else if estimate.current_queue_size > 100 {
        CongestionLevel::Normal
    } else {
        CongestionLevel::Low
    };
    
    let analysis = format!(
        "XRP ledger queue: {} transactions. Open ledger fee: {} drops.",
        estimate.current_queue_size,
        estimate.open_ledger_fee_drops
    );
    
    Ok(FeeIntelligence {
        chain: Chain::Xrp,
        recommended_level: RecommendedFeeLevel::Medium,
        confidence: 0.9,
        congestion,
        time_estimates: TimeEstimates {
            low_minutes: 1,
            medium_minutes: 1,
            high_minutes: 1,
        },
        analysis,
    })
}

/// Unified fee analysis
pub fn analyze_fees(estimate: &FeeEstimate) -> HawalaResult<FeeIntelligence> {
    match estimate {
        FeeEstimate::Bitcoin(btc) => analyze_bitcoin_fees(btc),
        FeeEstimate::Litecoin(ltc) => {
            // Convert to Bitcoin-style analysis
            let btc_estimate = BitcoinFeeEstimate {
                fastest: ltc.fast.clone(),
                fast: ltc.fast.clone(),
                medium: ltc.medium.clone(),
                slow: ltc.slow.clone(),
                minimum: ltc.slow.clone(),
            };
            let mut intel = analyze_bitcoin_fees(&btc_estimate)?;
            intel.chain = Chain::Litecoin;
            Ok(intel)
        }
        FeeEstimate::Evm(evm) => {
            let chain = match evm.chain_id {
                1 => Chain::Ethereum,
                11155111 => Chain::EthereumSepolia,
                56 => Chain::Bnb,
                137 => Chain::Polygon,
                42161 => Chain::Arbitrum,
                10 => Chain::Optimism,
                8453 => Chain::Base,
                43114 => Chain::Avalanche,
                _ => Chain::Ethereum,
            };
            analyze_evm_fees(evm, chain)
        }
        FeeEstimate::Solana(sol) => analyze_solana_fees(sol),
        FeeEstimate::Xrp(xrp) => analyze_xrp_fees(xrp),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_bitcoin_congestion_detection() {
        let high_congestion = BitcoinFeeEstimate {
            fastest: FeeLevel { label: "".to_string(), rate: 100, estimated_minutes: 10 },
            fast: FeeLevel { label: "".to_string(), rate: 80, estimated_minutes: 30 },
            medium: FeeLevel { label: "".to_string(), rate: 50, estimated_minutes: 60 },
            slow: FeeLevel { label: "".to_string(), rate: 10, estimated_minutes: 120 },
            minimum: FeeLevel { label: "".to_string(), rate: 5, estimated_minutes: 1440 },
        };
        
        let intel = analyze_bitcoin_fees(&high_congestion).unwrap();
        assert!(matches!(intel.congestion, CongestionLevel::High | CongestionLevel::Extreme));
    }
}
