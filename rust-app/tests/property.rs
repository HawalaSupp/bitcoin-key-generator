use bitcoin::hashes::{Hash, sha256d};
use bitcoin::secp256k1::SecretKey;
use proptest::prelude::*;
use rust_app::{encode_litecoin_wif, keccak256, to_checksum_address};

fn any_secret_key() -> impl Strategy<Value = SecretKey> {
    prop::array::uniform32(any::<u8>()).prop_filter_map("valid secp256k1 scalar", |bytes| {
        SecretKey::from_slice(&bytes).ok()
    })
}

proptest! {
    #[test]
    fn checksum_addresses_roundtrip(bytes in prop::array::uniform20(any::<u8>())) {
        let checksummed = to_checksum_address(&bytes);
        prop_assert!(checksummed.starts_with("0x"));

        let tail = checksummed.trim_start_matches("0x");
    let lower_expected = hex::encode(bytes);
    let lower_tail = tail.to_ascii_lowercase();
    prop_assert_eq!(lower_tail.as_str(), lower_expected.as_str());

    let hash = keccak256(lower_expected.as_bytes());
        let mut expected = String::from("0x");
        for (i, ch) in lower_expected.chars().enumerate() {
            let byte = hash[i / 2];
            let nibble = if i % 2 == 0 { byte >> 4 } else { byte & 0x0f };
            if ch.is_ascii_digit() || nibble < 8 {
                expected.push(ch);
            } else {
                expected.push(ch.to_ascii_uppercase());
            }
        }
        prop_assert_eq!(checksummed, expected);
    }

    #[test]
    fn litecoin_wif_checksums_hold(secret in any_secret_key()) {
        let encoded = encode_litecoin_wif(&secret);
        prop_assert!(encoded.starts_with('T'));

        let decoded = bs58::decode(&encoded).into_vec().expect("decode base58");
        prop_assert_eq!(decoded.len(), 38);
        prop_assert_eq!(decoded[0], 0xB0);
        prop_assert_eq!(decoded[33], 0x01);

        let checksum = sha256d::Hash::hash(&decoded[..34]);
        prop_assert_eq!(&decoded[34..], &checksum[..4]);
    }
}
