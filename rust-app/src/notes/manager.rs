//! Transaction Notes Manager
//!
//! Store and retrieve personal notes attached to transactions.
//! Supports searching and tagging.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// =============================================================================
// Types
// =============================================================================

/// A note attached to a transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionNote {
    /// Transaction hash
    pub tx_hash: String,
    /// Chain the transaction is on
    pub chain: Chain,
    /// Note content
    pub content: String,
    /// Tags for categorization
    pub tags: Vec<String>,
    /// Created timestamp
    pub created_at: u64,
    /// Updated timestamp
    pub updated_at: u64,
    /// Whether the note is pinned
    pub is_pinned: bool,
    /// Category (income, expense, transfer, etc.)
    pub category: Option<NoteCategory>,
}

/// Category for transaction notes
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NoteCategory {
    Income,
    Expense,
    Transfer,
    Swap,
    Nft,
    Airdrop,
    Stake,
    Unstake,
    Gas,
    Fee,
    Other,
}

/// Request to add a note
#[derive(Debug, Clone, Deserialize)]
pub struct AddNoteRequest {
    /// Transaction hash
    pub tx_hash: String,
    /// Chain
    pub chain: Chain,
    /// Note content
    pub content: String,
    /// Optional tags
    pub tags: Option<Vec<String>>,
    /// Optional category
    pub category: Option<NoteCategory>,
}

/// Request to search notes
#[derive(Debug, Clone, Deserialize)]
pub struct SearchNotesRequest {
    /// Search query (searches content and tags)
    pub query: Option<String>,
    /// Filter by chain
    pub chain: Option<Chain>,
    /// Filter by tags
    pub tags: Option<Vec<String>>,
    /// Filter by category
    pub category: Option<NoteCategory>,
    /// Only pinned notes
    pub pinned_only: bool,
    /// Maximum results
    pub limit: Option<usize>,
    /// Offset for pagination
    pub offset: Option<usize>,
}

/// Search results
#[derive(Debug, Clone, Serialize)]
pub struct SearchNotesResult {
    /// Matching notes
    pub notes: Vec<TransactionNote>,
    /// Total count (before pagination)
    pub total_count: usize,
    /// Whether there are more results
    pub has_more: bool,
}

/// Export format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFormat {
    Json,
    Csv,
}

// =============================================================================
// Notes Manager
// =============================================================================

/// Manages transaction notes
pub struct NotesManager {
    /// Notes indexed by tx_hash
    notes: HashMap<String, TransactionNote>,
    /// Index by chain
    chain_index: HashMap<Chain, Vec<String>>,
    /// Index by tag
    tag_index: HashMap<String, Vec<String>>,
}

impl NotesManager {
    /// Create a new notes manager
    pub fn new() -> Self {
        Self {
            notes: HashMap::new(),
            chain_index: HashMap::new(),
            tag_index: HashMap::new(),
        }
    }

    /// Add or update a note
    pub fn add_note(&mut self, request: AddNoteRequest) -> HawalaResult<TransactionNote> {
        if request.tx_hash.is_empty() {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Transaction hash required"));
        }

        if request.content.is_empty() {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Note content required"));
        }

        let now = current_timestamp();
        let tags = request.tags.unwrap_or_default();

        // Check if updating existing note
        let (created_at, is_pinned) = if let Some(existing) = self.notes.get(&request.tx_hash) {
            (existing.created_at, existing.is_pinned)
        } else {
            (now, false)
        };

        let note = TransactionNote {
            tx_hash: request.tx_hash.clone(),
            chain: request.chain,
            content: request.content,
            tags: tags.clone(),
            created_at,
            updated_at: now,
            is_pinned,
            category: request.category,
        };

        // Update indices
        self.chain_index
            .entry(request.chain)
            .or_default()
            .push(request.tx_hash.clone());

        for tag in &tags {
            self.tag_index
                .entry(tag.to_lowercase())
                .or_default()
                .push(request.tx_hash.clone());
        }

        self.notes.insert(request.tx_hash, note.clone());
        Ok(note)
    }

    /// Get a note by transaction hash
    pub fn get_note(&self, tx_hash: &str) -> Option<&TransactionNote> {
        self.notes.get(tx_hash)
    }

    /// Delete a note
    pub fn delete_note(&mut self, tx_hash: &str) -> HawalaResult<()> {
        if let Some(note) = self.notes.remove(tx_hash) {
            // Remove from chain index
            if let Some(hashes) = self.chain_index.get_mut(&note.chain) {
                hashes.retain(|h| h != tx_hash);
            }

            // Remove from tag indices
            for tag in &note.tags {
                if let Some(hashes) = self.tag_index.get_mut(&tag.to_lowercase()) {
                    hashes.retain(|h| h != tx_hash);
                }
            }

            Ok(())
        } else {
            Err(HawalaError::new(ErrorCode::InvalidInput, "Note not found"))
        }
    }

    /// Toggle pin status
    pub fn toggle_pin(&mut self, tx_hash: &str) -> HawalaResult<bool> {
        if let Some(note) = self.notes.get_mut(tx_hash) {
            note.is_pinned = !note.is_pinned;
            note.updated_at = current_timestamp();
            Ok(note.is_pinned)
        } else {
            Err(HawalaError::new(ErrorCode::InvalidInput, "Note not found"))
        }
    }

    /// Update note tags
    pub fn update_tags(&mut self, tx_hash: &str, tags: Vec<String>) -> HawalaResult<()> {
        if let Some(note) = self.notes.get_mut(tx_hash) {
            // Remove from old tag indices
            for old_tag in &note.tags {
                if let Some(hashes) = self.tag_index.get_mut(&old_tag.to_lowercase()) {
                    hashes.retain(|h| h != tx_hash);
                }
            }

            // Add to new tag indices
            for new_tag in &tags {
                self.tag_index
                    .entry(new_tag.to_lowercase())
                    .or_default()
                    .push(tx_hash.to_string());
            }

            note.tags = tags;
            note.updated_at = current_timestamp();
            Ok(())
        } else {
            Err(HawalaError::new(ErrorCode::InvalidInput, "Note not found"))
        }
    }

    /// Search notes
    pub fn search(&self, request: &SearchNotesRequest) -> SearchNotesResult {
        let limit = request.limit.unwrap_or(50);
        let offset = request.offset.unwrap_or(0);

        let mut results: Vec<&TransactionNote> = self.notes.values().collect();

        // Filter by chain
        if let Some(chain) = request.chain {
            results.retain(|n| n.chain == chain);
        }

        // Filter by pinned
        if request.pinned_only {
            results.retain(|n| n.is_pinned);
        }

        // Filter by category
        if let Some(category) = request.category {
            results.retain(|n| n.category == Some(category));
        }

        // Filter by tags
        if let Some(ref tags) = request.tags {
            results.retain(|n| {
                tags.iter().any(|t| n.tags.iter().any(|nt| nt.to_lowercase() == t.to_lowercase()))
            });
        }

        // Filter by query (search content and tags)
        if let Some(ref query) = request.query {
            let query_lower = query.to_lowercase();
            results.retain(|n| {
                n.content.to_lowercase().contains(&query_lower)
                    || n.tags.iter().any(|t| t.to_lowercase().contains(&query_lower))
            });
        }

        // Sort by updated_at (newest first)
        results.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));

        let total_count = results.len();
        let has_more = offset + limit < total_count;

        let notes: Vec<TransactionNote> = results
            .into_iter()
            .skip(offset)
            .take(limit)
            .cloned()
            .collect();

        SearchNotesResult {
            notes,
            total_count,
            has_more,
        }
    }

    /// Get all tags with usage count
    pub fn get_all_tags(&self) -> Vec<(String, usize)> {
        self.tag_index
            .iter()
            .map(|(tag, hashes)| (tag.clone(), hashes.len()))
            .collect()
    }

    /// Export notes
    pub fn export(&self, format: ExportFormat) -> HawalaResult<String> {
        match format {
            ExportFormat::Json => {
                let notes: Vec<&TransactionNote> = self.notes.values().collect();
                serde_json::to_string_pretty(&notes)
                    .map_err(|e| HawalaError::parse_error(e.to_string()))
            }
            ExportFormat::Csv => {
                let mut csv = String::from("tx_hash,chain,content,tags,category,created_at,updated_at,is_pinned\n");
                
                for note in self.notes.values() {
                    let tags = note.tags.join(";");
                    let category = note.category.map(|c| format!("{:?}", c)).unwrap_or_default();
                    csv.push_str(&format!(
                        "{},{:?},\"{}\",\"{}\",{},{},{},{}\n",
                        note.tx_hash,
                        note.chain,
                        note.content.replace('"', "\"\""),
                        tags,
                        category,
                        note.created_at,
                        note.updated_at,
                        note.is_pinned
                    ));
                }
                
                Ok(csv)
            }
        }
    }

    /// Import notes from JSON
    pub fn import(&mut self, json: &str) -> HawalaResult<usize> {
        let notes: Vec<TransactionNote> = serde_json::from_str(json)
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;

        let count = notes.len();
        
        for note in notes {
            // Update indices
            self.chain_index
                .entry(note.chain)
                .or_default()
                .push(note.tx_hash.clone());

            for tag in &note.tags {
                self.tag_index
                    .entry(tag.to_lowercase())
                    .or_default()
                    .push(note.tx_hash.clone());
            }

            self.notes.insert(note.tx_hash.clone(), note);
        }

        Ok(count)
    }

    /// Get statistics
    pub fn get_stats(&self) -> NotesStats {
        let total = self.notes.len();
        let pinned = self.notes.values().filter(|n| n.is_pinned).count();
        
        let mut by_category: HashMap<String, usize> = HashMap::new();
        for note in self.notes.values() {
            let cat = note.category.map(|c| format!("{:?}", c)).unwrap_or("uncategorized".to_string());
            *by_category.entry(cat).or_default() += 1;
        }

        let mut by_chain: HashMap<String, usize> = HashMap::new();
        for note in self.notes.values() {
            *by_chain.entry(format!("{:?}", note.chain)).or_default() += 1;
        }

        NotesStats {
            total,
            pinned,
            by_category,
            by_chain,
            total_tags: self.tag_index.len(),
        }
    }
}

impl Default for NotesManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Notes statistics
#[derive(Debug, Clone, Serialize)]
pub struct NotesStats {
    pub total: usize,
    pub pinned: usize,
    pub by_category: HashMap<String, usize>,
    pub by_chain: HashMap<String, usize>,
    pub total_tags: usize,
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

    fn create_test_manager() -> NotesManager {
        let mut manager = NotesManager::new();
        
        manager.add_note(AddNoteRequest {
            tx_hash: "0xabc123".to_string(),
            chain: Chain::Ethereum,
            content: "Payment to Alice".to_string(),
            tags: Some(vec!["payment".to_string(), "friend".to_string()]),
            category: Some(NoteCategory::Expense),
        }).unwrap();

        manager.add_note(AddNoteRequest {
            tx_hash: "0xdef456".to_string(),
            chain: Chain::Ethereum,
            content: "Uniswap swap".to_string(),
            tags: Some(vec!["swap".to_string(), "defi".to_string()]),
            category: Some(NoteCategory::Swap),
        }).unwrap();

        manager
    }

    #[test]
    fn test_add_note() {
        let mut manager = NotesManager::new();
        
        let request = AddNoteRequest {
            tx_hash: "0x123".to_string(),
            chain: Chain::Ethereum,
            content: "Test note".to_string(),
            tags: Some(vec!["test".to_string()]),
            category: None,
        };

        let note = manager.add_note(request).unwrap();
        assert_eq!(note.tx_hash, "0x123");
        assert_eq!(note.content, "Test note");
        assert!(!note.is_pinned);
    }

    #[test]
    fn test_get_note() {
        let manager = create_test_manager();
        
        let note = manager.get_note("0xabc123");
        assert!(note.is_some());
        assert_eq!(note.unwrap().content, "Payment to Alice");
    }

    #[test]
    fn test_delete_note() {
        let mut manager = create_test_manager();
        
        assert!(manager.get_note("0xabc123").is_some());
        manager.delete_note("0xabc123").unwrap();
        assert!(manager.get_note("0xabc123").is_none());
    }

    #[test]
    fn test_toggle_pin() {
        let mut manager = create_test_manager();
        
        let is_pinned = manager.toggle_pin("0xabc123").unwrap();
        assert!(is_pinned);
        
        let note = manager.get_note("0xabc123").unwrap();
        assert!(note.is_pinned);
    }

    #[test]
    fn test_search_by_query() {
        let manager = create_test_manager();
        
        let results = manager.search(&SearchNotesRequest {
            query: Some("Alice".to_string()),
            chain: None,
            tags: None,
            category: None,
            pinned_only: false,
            limit: None,
            offset: None,
        });

        assert_eq!(results.notes.len(), 1);
        assert_eq!(results.notes[0].content, "Payment to Alice");
    }

    #[test]
    fn test_search_by_tag() {
        let manager = create_test_manager();
        
        let results = manager.search(&SearchNotesRequest {
            query: None,
            chain: None,
            tags: Some(vec!["defi".to_string()]),
            category: None,
            pinned_only: false,
            limit: None,
            offset: None,
        });

        assert_eq!(results.notes.len(), 1);
        assert!(results.notes[0].tags.contains(&"defi".to_string()));
    }

    #[test]
    fn test_search_by_category() {
        let manager = create_test_manager();
        
        let results = manager.search(&SearchNotesRequest {
            query: None,
            chain: None,
            tags: None,
            category: Some(NoteCategory::Swap),
            pinned_only: false,
            limit: None,
            offset: None,
        });

        assert_eq!(results.notes.len(), 1);
        assert_eq!(results.notes[0].category, Some(NoteCategory::Swap));
    }

    #[test]
    fn test_export_json() {
        let manager = create_test_manager();
        let json = manager.export(ExportFormat::Json).unwrap();
        assert!(json.contains("0xabc123"));
        assert!(json.contains("Payment to Alice"));
    }

    #[test]
    fn test_export_csv() {
        let manager = create_test_manager();
        let csv = manager.export(ExportFormat::Csv).unwrap();
        assert!(csv.contains("tx_hash,chain,content"));
        assert!(csv.contains("0xabc123"));
    }

    #[test]
    fn test_get_stats() {
        let manager = create_test_manager();
        let stats = manager.get_stats();
        
        assert_eq!(stats.total, 2);
        assert_eq!(stats.pinned, 0);
        assert!(stats.total_tags > 0);
    }

    #[test]
    fn test_get_all_tags() {
        let manager = create_test_manager();
        let tags = manager.get_all_tags();
        
        assert!(!tags.is_empty());
        assert!(tags.iter().any(|(t, _)| t == "payment"));
        assert!(tags.iter().any(|(t, _)| t == "swap"));
    }
}
