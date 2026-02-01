//! Ordinals and BRC-20 integration tests

#[cfg(test)]
mod tests {
    use crate::ordinals::types::*;
    use crate::ordinals::indexer::*;
    use crate::ordinals::parser::*;

    // ===================
    // Inscription Tests
    // ===================

    #[test]
    fn test_inscription_creation() {
        let inscription = Inscription {
            id: "abc123i0".to_string(),
            number: 12345,
            content_type: "image/png".to_string(),
            content_length: 1024,
            genesis_tx: "abc123".to_string(),
            genesis_height: 800000,
            sat: 1234567890,
            output: "abc123:0".to_string(),
            offset: 0,
            address: Some("bc1qtest".to_string()),
            timestamp: 1699999999,
        };

        assert_eq!(inscription.id, "abc123i0");
        assert_eq!(inscription.number, 12345);
        assert!(inscription.is_image());
    }

    #[test]
    fn test_inscription_content_type_detection() {
        let image_types = vec!["image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml"];
        for content_type in image_types {
            let inscription = create_inscription_with_type(content_type);
            assert!(inscription.is_image(), "Failed for {}", content_type);
        }

        let text_types = vec!["text/plain", "application/json"];
        for content_type in text_types {
            let inscription = create_inscription_with_type(content_type);
            assert!(inscription.is_text(), "Failed for {}", content_type);
        }

        let html_type = "text/html";
        let inscription = create_inscription_with_type(html_type);
        assert!(inscription.is_html(), "Failed for {}", html_type);
    }

    #[test]
    fn test_inscription_file_extension() {
        assert_eq!(
            create_inscription_with_type("image/png").file_extension(),
            "png"
        );
        assert_eq!(
            create_inscription_with_type("image/jpeg").file_extension(),
            "jpg"
        );
        assert_eq!(
            create_inscription_with_type("text/plain").file_extension(),
            "txt"
        );
        assert_eq!(
            create_inscription_with_type("application/json").file_extension(),
            "json"
        );
        assert_eq!(
            create_inscription_with_type("video/mp4").file_extension(),
            "mp4"
        );
    }

    #[test]
    fn test_inscription_urls() {
        let inscription = create_inscription_with_type("image/png");
        let content_url = inscription.content_url("https://ordinals.com");
        let preview_url = inscription.preview_url("https://ordinals.com");

        assert!(content_url.contains(&inscription.id));
        assert!(preview_url.contains(&inscription.id));
    }

    // ===================
    // BRC-20 Tests
    // ===================

    #[test]
    fn test_brc20_deploy() {
        let brc20 = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Deploy,
            tick: "ordi".to_string(),
            max: Some("21000000".to_string()),
            lim: Some("1000".to_string()),
            amt: None,
            dec: Some("18".to_string()),
        };

        assert!(brc20.is_valid());
        assert_eq!(brc20.max_supply(), Some(21000000.0));
        assert_eq!(brc20.mint_limit(), Some(1000.0));
        assert_eq!(brc20.decimals(), 18);
    }

    #[test]
    fn test_brc20_mint() {
        let brc20 = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Mint,
            tick: "ordi".to_string(),
            max: None,
            lim: None,
            amt: Some("1000".to_string()),
            dec: None,
        };

        assert!(brc20.is_valid());
        assert_eq!(brc20.amount(), Some(1000.0));
    }

    #[test]
    fn test_brc20_transfer() {
        let brc20 = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Transfer,
            tick: "ordi".to_string(),
            max: None,
            lim: None,
            amt: Some("500".to_string()),
            dec: None,
        };

        assert!(brc20.is_valid());
        assert_eq!(brc20.amount(), Some(500.0));
    }

    #[test]
    fn test_brc20_validation_invalid_tick() {
        let brc20 = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Transfer,
            tick: "toolong".to_string(), // Invalid: more than 4 chars
            max: None,
            lim: None,
            amt: Some("500".to_string()),
            dec: None,
        };

        assert!(!brc20.is_valid());
    }

    #[test]
    fn test_brc20_token_progress() {
        let token = Brc20Token {
            tick: "ordi".to_string(),
            max_supply: "21000000".to_string(),
            minted: "10500000".to_string(),
            limit_per_mint: "1000".to_string(),
            decimals: 18,
            deploy_inscription: "abc123i0".to_string(),
            deploy_height: 800000,
            holders: 5000,
            transactions: 100000,
        };

        assert!((token.mint_progress() - 50.0).abs() < 0.01);
        assert!(!token.is_fully_minted());
        assert!((token.remaining_supply() - 10500000.0).abs() < 0.01);
    }

    #[test]
    fn test_brc20_balance() {
        let balance = Brc20Balance {
            tick: "ordi".to_string(),
            available: "500".to_string(),
            transferable: "500".to_string(),
            total: "1000".to_string(),
        };

        assert_eq!(balance.total_f64(), 1000.0);
        assert_eq!(balance.transferable_f64(), 500.0);
    }

    // ===================
    // Satoshi Rarity Tests
    // ===================

    #[test]
    fn test_satoshi_rarity_common() {
        let rarity = SatoshiRarity::from_sat(1234567890);
        assert_eq!(rarity, SatoshiRarity::Common);
        assert_eq!(rarity.name(), "Common");
    }

    #[test]
    fn test_satoshi_rarity_mythic() {
        let rarity = SatoshiRarity::from_sat(0);
        assert_eq!(rarity, SatoshiRarity::Mythic);
        assert_eq!(rarity.name(), "Mythic");
        assert_eq!(rarity.emoji(), "🔴");
    }

    #[test]
    fn test_satoshi_rarity_legendary() {
        // Legendary: sat % 2_100_000_000_000_000 == 0
        let legendary_sat = 2_100_000_000_000_000;
        let rarity = SatoshiRarity::from_sat(legendary_sat);
        assert_eq!(rarity, SatoshiRarity::Legendary);
    }

    #[test]
    fn test_satoshi_rarity_uncommon() {
        // Uncommon: sat % 6_250_000_000 == 0 (first sat of each block)
        let uncommon_sat = 6_250_000_000;
        let rarity = SatoshiRarity::from_sat(uncommon_sat);
        assert_eq!(rarity, SatoshiRarity::Uncommon);
    }

    // ===================
    // Indexer URL Tests
    // ===================

    #[test]
    fn test_hiro_inscriptions_url() {
        let client = HiroOrdinalsClient::new();
        let url = client.inscriptions_by_address_url("bc1qtest");
        assert!(url.contains("api.hiro.so"));
        assert!(url.contains("bc1qtest"));
    }

    #[test]
    fn test_hiro_inscription_url() {
        let client = HiroOrdinalsClient::new();
        let url = client.inscription_url("abc123i0");
        assert!(url.contains("api.hiro.so"));
        assert!(url.contains("abc123i0"));
    }

    #[test]
    fn test_hiro_brc20_tokens_url() {
        let client = HiroOrdinalsClient::new();
        let url = client.brc20_tokens_url();
        assert!(url.contains("api.hiro.so"));
        assert!(url.contains("brc-20/tokens"));
    }

    #[test]
    fn test_hiro_brc20_balances_url() {
        let client = HiroOrdinalsClient::new();
        let url = client.brc20_balances_url("bc1qtest");
        assert!(url.contains("api.hiro.so"));
        assert!(url.contains("bc1qtest"));
    }

    #[test]
    fn test_unisat_brc20_summary_url() {
        let client = UnisatClient::new();
        let url = client.brc20_summary_url("bc1qtest");
        assert!(url.contains("unisat"));
        assert!(url.contains("bc1qtest"));
    }

    #[test]
    fn test_magic_eden_collection_url() {
        let client = MagicEdenClient::new();
        let url = client.collection_stats_url("test-collection");
        assert!(url.contains("magiceden"));
        assert!(url.contains("test-collection"));
    }

    // ===================
    // Parser Tests
    // ===================

    #[test]
    fn test_inscription_id_parsing() {
        // Test colon format
        let (txid, index) = InscriptionParser::parse_inscription_id("abc123def:0").unwrap();
        assert_eq!(txid, "abc123def");
        assert_eq!(index, 0);

        // Test i format
        let (txid, index) = InscriptionParser::parse_inscription_id("abc123defi5").unwrap();
        assert_eq!(txid, "abc123def");
        assert_eq!(index, 5);
    }

    #[test]
    fn test_inscription_id_formatting() {
        let id = InscriptionParser::format_inscription_id("abc123", 0);
        assert_eq!(id, "abc123i0");

        let id = InscriptionParser::format_inscription_id("xyz789", 5);
        assert_eq!(id, "xyz789i5");
    }

    #[test]
    fn test_content_type_detection() {
        // Test various magic bytes
        let png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        assert_eq!(InscriptionParser::detect_content_type(&png), "image/png");

        let jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
        assert_eq!(InscriptionParser::detect_content_type(&jpeg), "image/jpeg");

        let gif87 = b"GIF87a......";
        assert_eq!(InscriptionParser::detect_content_type(gif87), "image/gif");

        let gif89 = b"GIF89a......";
        assert_eq!(InscriptionParser::detect_content_type(gif89), "image/gif");

        let json = b"{\"test\": true}";
        assert_eq!(InscriptionParser::detect_content_type(json), "application/json");

        let html = b"<!DOCTYPE html><html>";
        assert_eq!(InscriptionParser::detect_content_type(html), "text/html");
    }

    #[test]
    fn test_brc20_content_detection() {
        let brc20_content = br#"{"p":"brc-20","op":"transfer","tick":"ordi","amt":"100"}"#;
        assert!(InscriptionParser::is_likely_brc20("text/plain", brc20_content));
        assert!(InscriptionParser::is_likely_brc20("application/json", brc20_content));

        let not_brc20 = b"Just some text";
        assert!(!InscriptionParser::is_likely_brc20("text/plain", not_brc20));

        let wrong_protocol = br#"{"p":"other","op":"test"}"#;
        assert!(!InscriptionParser::is_likely_brc20("application/json", wrong_protocol));
    }

    #[test]
    fn test_brc20_parsing() {
        let deploy = br#"{"p":"brc-20","op":"deploy","tick":"test","max":"21000000","lim":"1000"}"#;
        let result = InscriptionParser::parse_brc20(deploy);
        assert!(result.is_ok());
        let brc20 = result.unwrap();
        assert_eq!(brc20.tick, "test");
        assert_eq!(brc20.operation, Brc20Operation::Deploy);
        assert_eq!(brc20.max_supply(), Some(21000000.0));
    }

    #[test]
    fn test_satoshi_calculations() {
        // Block 0
        assert_eq!(SatoshiUtils::block_of_sat(0), 0);
        assert_eq!(SatoshiUtils::first_sat_of_block(0), 0);

        // Block 1
        assert_eq!(SatoshiUtils::first_sat_of_block(1), 5_000_000_000);
        assert_eq!(SatoshiUtils::block_of_sat(5_000_000_000), 1);

        // Epoch calculations
        assert_eq!(SatoshiUtils::epoch_of_sat(0), 0);
    }

    #[test]
    fn test_format_sat() {
        assert_eq!(SatoshiUtils::format_sat(0), "Sat 0");
        assert_eq!(SatoshiUtils::format_sat(1000), "Sat 1,000");
        assert_eq!(SatoshiUtils::format_sat(1234567890), "Sat 1,234,567,890");
    }

    #[test]
    fn test_vintage_detection() {
        assert!(SatoshiUtils::is_vintage(0)); // Block 0
        assert!(SatoshiUtils::is_vintage(100)); // Still block 0
    }

    #[test]
    fn test_brc20_transfer_builder() {
        let builder = Brc20TransferBuilder::new("ordi", "1000");
        let content = builder.build().unwrap();

        assert!(content.contains("brc-20"));
        assert!(content.contains("transfer"));
        assert!(content.contains("ordi"));
        assert!(content.contains("1000"));

        // Invalid ticker
        let invalid_builder = Brc20TransferBuilder::new("toolong", "100");
        assert!(invalid_builder.build().is_err());
    }

    #[test]
    fn test_text_preview_extraction() {
        let short_text = b"Hello";
        let preview = InscriptionParser::extract_text_preview(short_text, 100);
        assert_eq!(preview, Some("Hello".to_string()));

        let long_text = b"This is a very long text that should definitely be truncated";
        let preview = InscriptionParser::extract_text_preview(long_text, 20);
        assert!(preview.is_some());
        let p = preview.unwrap();
        assert!(p.ends_with("..."));
        assert!(p.len() <= 23); // 20 + "..."
    }

    // ===================
    // Collection Tests
    // ===================

    #[test]
    fn test_ordinals_collection() {
        let collection = OrdinalsCollection {
            id: "test-collection".to_string(),
            name: "Test Collection".to_string(),
            description: Some("A test collection".to_string()),
            supply: 100,
            floor_price: Some(0.001),
            total_volume: Some(10.0),
            inscription_range: Some((1000, 1100)),
            icon: None,
        };

        assert_eq!(collection.id, "test-collection");
        assert_eq!(collection.supply, 100);
    }

    // ===================
    // Error Handling Tests
    // ===================

    #[test]
    fn test_ordinals_errors() {
        let api_error = OrdinalsError::ApiError("Connection failed".to_string());
        assert!(format!("{:?}", api_error).contains("Connection failed"));

        let parse_error = OrdinalsError::ParseError("Invalid JSON".to_string());
        assert!(format!("{:?}", parse_error).contains("Invalid JSON"));

        let invalid_id = OrdinalsError::InvalidInscriptionId("bad-id".to_string());
        assert!(format!("{:?}", invalid_id).contains("bad-id"));
    }

    #[test]
    fn test_invalid_inscription_id() {
        let result = InscriptionParser::parse_inscription_id("invalid");
        assert!(result.is_err());

        let result = InscriptionParser::parse_inscription_id("");
        assert!(result.is_err());
    }

    // ===================
    // API Response Parsing Tests
    // ===================

    #[test]
    fn test_parse_inscriptions_response() {
        let json = serde_json::json!({
            "results": [
                {
                    "id": "abc123i0",
                    "number": 12345,
                    "content_type": "image/png",
                    "content_length": 1024,
                    "genesis_tx_id": "abc123",
                    "genesis_block_height": 800000,
                    "timestamp": 1699999999,
                    "sat_ordinal": 1234567890,
                    "output": "abc123:0",
                    "offset": 0,
                    "address": "bc1qtest"
                }
            ]
        });

        let inscriptions = HiroOrdinalsClient::parse_inscriptions_response(&json);
        assert_eq!(inscriptions.len(), 1);
        assert_eq!(inscriptions[0].id, "abc123i0");
        assert_eq!(inscriptions[0].number, 12345);
    }

    #[test]
    fn test_parse_brc20_balances() {
        let json = serde_json::json!({
            "results": [
                {
                    "ticker": "ordi",
                    "available_balance": "500",
                    "transferrable_balance": "500",
                    "overall_balance": "1000"
                }
            ]
        });

        let balances = HiroOrdinalsClient::parse_brc20_balances(&json);
        assert_eq!(balances.len(), 1);
        assert_eq!(balances[0].tick, "ordi");
        assert_eq!(balances[0].total_f64(), 1000.0);
    }

    #[test]
    fn test_parse_brc20_token() {
        let json = serde_json::json!({
            "token": {
                "ticker": "ordi",
                "max_supply": "21000000",
                "minted_supply": "21000000",
                "mint_limit": "1000",
                "decimals": 18,
                "deploy_inscription_id": "abc123i0",
                "block_height": 800000
            },
            "holders": 5000,
            "tx_count": 100000
        });

        let token = HiroOrdinalsClient::parse_brc20_token(&json);
        assert!(token.is_some());
        let t = token.unwrap();
        assert_eq!(t.tick, "ordi");
        assert!(t.is_fully_minted());
    }

    // ===================
    // Helper Functions
    // ===================

    fn create_inscription_with_type(content_type: &str) -> Inscription {
        Inscription {
            id: "test123i0".to_string(),
            number: 1,
            content_type: content_type.to_string(),
            content_length: 100,
            genesis_tx: "test123".to_string(),
            genesis_height: 800000,
            sat: 1234567890,
            output: "test123:0".to_string(),
            offset: 0,
            address: Some("bc1qtest".to_string()),
            timestamp: 1699999999,
        }
    }
}
