//! Session Management
//!
//! Secure wallet session management with:
//! - Configurable session timeouts
//! - Activity-based session extension
//! - Secure session token generation
//! - Session state tracking
//! - Automatic cleanup

use crate::error::{HawalaError, HawalaResult};
use rand::{RngCore, rngs::OsRng};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, Instant};

/// Session manager for wallet security
pub struct SessionManager {
    /// Active sessions
    sessions: RwLock<HashMap<String, Session>>,
    /// Session configuration
    config: SessionConfig,
}

/// Session configuration
#[derive(Debug, Clone)]
pub struct SessionConfig {
    /// Default session timeout (inactivity)
    pub timeout: Duration,
    /// Maximum session duration (absolute)
    pub max_duration: Duration,
    /// Whether to extend session on activity
    pub extend_on_activity: bool,
    /// Maximum concurrent sessions per wallet
    pub max_concurrent: usize,
    /// Require re-authentication for sensitive operations
    pub require_reauth_for_sensitive: bool,
    /// Sensitive operation timeout (shorter than session)
    pub sensitive_op_timeout: Duration,
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(15 * 60),           // 15 minutes inactivity
            max_duration: Duration::from_secs(24 * 60 * 60), // 24 hours max
            extend_on_activity: true,
            max_concurrent: 1,
            require_reauth_for_sensitive: true,
            sensitive_op_timeout: Duration::from_secs(5 * 60), // 5 minutes for sensitive ops
        }
    }
}

/// Individual session
#[derive(Debug, Clone)]
pub struct Session {
    /// Unique session ID
    pub id: String,
    /// Wallet ID this session is for
    pub wallet_id: String,
    /// Session creation time
    pub created_at: Instant,
    /// Last activity time
    pub last_activity: Instant,
    /// Session state
    pub state: SessionState,
    /// Last sensitive operation authentication
    pub last_sensitive_auth: Option<Instant>,
    /// Session metadata
    pub metadata: SessionMetadata,
}

/// Session state
#[derive(Debug, Clone, PartialEq)]
pub enum SessionState {
    Active,
    Locked,
    Expired,
    Revoked,
}

/// Session metadata
#[derive(Debug, Clone, Default)]
pub struct SessionMetadata {
    /// Device identifier
    pub device_id: Option<String>,
    /// IP address (if tracked)
    pub ip_address: Option<String>,
    /// User agent
    pub user_agent: Option<String>,
    /// Number of operations performed
    pub operation_count: u64,
    /// Number of sensitive operations
    pub sensitive_op_count: u64,
}

/// Session validation result
#[derive(Debug, Clone)]
pub struct SessionValidation {
    pub is_valid: bool,
    pub state: SessionState,
    pub time_remaining: Option<Duration>,
    pub requires_reauth: bool,
    pub message: Option<String>,
}

impl SessionManager {
    /// Create a new session manager with default config
    pub fn new() -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
            config: SessionConfig::default(),
        }
    }

    /// Create with custom configuration
    pub fn with_config(config: SessionConfig) -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
            config,
        }
    }

    /// Create a new session for a wallet
    pub fn create_session(&self, wallet_id: &str) -> HawalaResult<Session> {
        // Check concurrent session limit
        self.enforce_concurrent_limit(wallet_id)?;

        // Generate secure session ID
        let session_id = generate_session_id();

        let session = Session {
            id: session_id.clone(),
            wallet_id: wallet_id.to_string(),
            created_at: Instant::now(),
            last_activity: Instant::now(),
            state: SessionState::Active,
            last_sensitive_auth: None,
            metadata: SessionMetadata::default(),
        };

        let mut sessions = self.sessions.write().unwrap();
        sessions.insert(session_id, session.clone());

        Ok(session)
    }

    /// Validate a session
    pub fn validate_session(&self, session_id: &str) -> SessionValidation {
        let sessions = self.sessions.read().unwrap();
        
        match sessions.get(session_id) {
            None => SessionValidation {
                is_valid: false,
                state: SessionState::Expired,
                time_remaining: None,
                requires_reauth: true,
                message: Some("Session not found".to_string()),
            },
            Some(session) => {
                // Check if session is revoked
                if session.state == SessionState::Revoked {
                    return SessionValidation {
                        is_valid: false,
                        state: SessionState::Revoked,
                        time_remaining: None,
                        requires_reauth: true,
                        message: Some("Session has been revoked".to_string()),
                    };
                }

                // Check if session is locked
                if session.state == SessionState::Locked {
                    return SessionValidation {
                        is_valid: false,
                        state: SessionState::Locked,
                        time_remaining: None,
                        requires_reauth: true,
                        message: Some("Session is locked".to_string()),
                    };
                }

                // Check inactivity timeout
                let inactive_duration = session.last_activity.elapsed();
                if inactive_duration > self.config.timeout {
                    return SessionValidation {
                        is_valid: false,
                        state: SessionState::Expired,
                        time_remaining: None,
                        requires_reauth: true,
                        message: Some("Session expired due to inactivity".to_string()),
                    };
                }

                // Check absolute timeout
                let total_duration = session.created_at.elapsed();
                if total_duration > self.config.max_duration {
                    return SessionValidation {
                        is_valid: false,
                        state: SessionState::Expired,
                        time_remaining: None,
                        requires_reauth: true,
                        message: Some("Session expired (maximum duration)".to_string()),
                    };
                }

                // Calculate time remaining
                let time_remaining = self.config.timeout
                    .checked_sub(inactive_duration)
                    .unwrap_or(Duration::ZERO);

                SessionValidation {
                    is_valid: true,
                    state: SessionState::Active,
                    time_remaining: Some(time_remaining),
                    requires_reauth: false,
                    message: None,
                }
            }
        }
    }

    /// Check if session is valid for sensitive operations
    pub fn validate_for_sensitive_op(&self, session_id: &str) -> SessionValidation {
        let mut validation = self.validate_session(session_id);
        
        if !validation.is_valid {
            return validation;
        }

        if self.config.require_reauth_for_sensitive {
            let sessions = self.sessions.read().unwrap();
            if let Some(session) = sessions.get(session_id) {
                let needs_reauth = match session.last_sensitive_auth {
                    None => true,
                    Some(last_auth) => last_auth.elapsed() > self.config.sensitive_op_timeout,
                };

                if needs_reauth {
                    validation.requires_reauth = true;
                    validation.message = Some(
                        "Re-authentication required for sensitive operation".to_string()
                    );
                }
            }
        }

        validation
    }

    /// Record activity (extends session if configured)
    pub fn record_activity(&self, session_id: &str) -> HawalaResult<()> {
        let mut sessions = self.sessions.write().unwrap();
        
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| HawalaError::auth_error("Session not found"))?;

        if self.config.extend_on_activity {
            session.last_activity = Instant::now();
        }
        
        session.metadata.operation_count += 1;
        Ok(())
    }

    /// Record sensitive operation authentication
    pub fn record_sensitive_auth(&self, session_id: &str) -> HawalaResult<()> {
        let mut sessions = self.sessions.write().unwrap();
        
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| HawalaError::auth_error("Session not found"))?;

        session.last_sensitive_auth = Some(Instant::now());
        session.metadata.sensitive_op_count += 1;
        session.last_activity = Instant::now();
        
        Ok(())
    }

    /// Lock a session (require re-authentication to unlock)
    pub fn lock_session(&self, session_id: &str) -> HawalaResult<()> {
        let mut sessions = self.sessions.write().unwrap();
        
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| HawalaError::auth_error("Session not found"))?;

        session.state = SessionState::Locked;
        Ok(())
    }

    /// Unlock a session (after re-authentication)
    pub fn unlock_session(&self, session_id: &str) -> HawalaResult<()> {
        let mut sessions = self.sessions.write().unwrap();
        
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| HawalaError::auth_error("Session not found"))?;

        if session.state != SessionState::Locked {
            return Err(HawalaError::auth_error("Session is not locked"));
        }

        session.state = SessionState::Active;
        session.last_activity = Instant::now();
        session.last_sensitive_auth = Some(Instant::now());
        
        Ok(())
    }

    /// Revoke a session
    pub fn revoke_session(&self, session_id: &str) -> HawalaResult<()> {
        let mut sessions = self.sessions.write().unwrap();
        
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| HawalaError::auth_error("Session not found"))?;

        session.state = SessionState::Revoked;
        Ok(())
    }

    /// Revoke all sessions for a wallet
    pub fn revoke_all_sessions(&self, wallet_id: &str) {
        let mut sessions = self.sessions.write().unwrap();
        
        for session in sessions.values_mut() {
            if session.wallet_id == wallet_id {
                session.state = SessionState::Revoked;
            }
        }
    }

    /// Clean up expired sessions
    pub fn cleanup_expired(&self) -> usize {
        let mut sessions = self.sessions.write().unwrap();
        let initial_count = sessions.len();

        sessions.retain(|_, session| {
            let is_expired = session.last_activity.elapsed() > self.config.timeout
                || session.created_at.elapsed() > self.config.max_duration;
            let is_revoked = session.state == SessionState::Revoked;
            
            !is_expired && !is_revoked
        });

        initial_count - sessions.len()
    }

    /// Get session info
    pub fn get_session(&self, session_id: &str) -> Option<Session> {
        let sessions = self.sessions.read().unwrap();
        sessions.get(session_id).cloned()
    }

    /// Get all sessions for a wallet
    pub fn get_wallet_sessions(&self, wallet_id: &str) -> Vec<Session> {
        let sessions = self.sessions.read().unwrap();
        sessions.values()
            .filter(|s| s.wallet_id == wallet_id)
            .cloned()
            .collect()
    }

    /// Enforce concurrent session limit
    fn enforce_concurrent_limit(&self, wallet_id: &str) -> HawalaResult<()> {
        let sessions = self.sessions.read().unwrap();
        
        let active_count = sessions.values()
            .filter(|s| s.wallet_id == wallet_id && s.state == SessionState::Active)
            .count();

        if active_count >= self.config.max_concurrent {
            return Err(HawalaError::auth_error(format!(
                "Maximum concurrent sessions ({}) reached for this wallet",
                self.config.max_concurrent
            )));
        }

        Ok(())
    }

    /// Get configuration
    pub fn config(&self) -> &SessionConfig {
        &self.config
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Generate a secure random session ID
fn generate_session_id() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Global session manager instance
static SESSION_MANAGER: std::sync::OnceLock<SessionManager> = std::sync::OnceLock::new();

/// Get the global session manager
pub fn get_session_manager() -> &'static SessionManager {
    SESSION_MANAGER.get_or_init(SessionManager::new)
}

/// Convenience functions
pub fn create_session(wallet_id: &str) -> HawalaResult<Session> {
    get_session_manager().create_session(wallet_id)
}

pub fn validate_session(session_id: &str) -> SessionValidation {
    get_session_manager().validate_session(session_id)
}

pub fn require_valid_session(session_id: &str) -> HawalaResult<()> {
    let validation = get_session_manager().validate_session(session_id);
    if !validation.is_valid {
        return Err(HawalaError::auth_error(
            validation.message.unwrap_or_else(|| "Invalid session".to_string())
        ));
    }
    get_session_manager().record_activity(session_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_session() {
        let manager = SessionManager::new();
        let session = manager.create_session("wallet_123").unwrap();
        
        assert_eq!(session.wallet_id, "wallet_123");
        assert_eq!(session.state, SessionState::Active);
        assert_eq!(session.id.len(), 64); // 32 bytes hex
    }

    #[test]
    fn test_validate_session() {
        let manager = SessionManager::new();
        let session = manager.create_session("wallet_123").unwrap();
        
        let validation = manager.validate_session(&session.id);
        assert!(validation.is_valid);
        assert_eq!(validation.state, SessionState::Active);
        assert!(validation.time_remaining.is_some());
    }

    #[test]
    fn test_invalid_session() {
        let manager = SessionManager::new();
        let validation = manager.validate_session("nonexistent");
        
        assert!(!validation.is_valid);
        assert_eq!(validation.state, SessionState::Expired);
    }

    #[test]
    fn test_lock_unlock_session() {
        let manager = SessionManager::new();
        let session = manager.create_session("wallet_123").unwrap();
        
        manager.lock_session(&session.id).unwrap();
        let validation = manager.validate_session(&session.id);
        assert!(!validation.is_valid);
        assert_eq!(validation.state, SessionState::Locked);
        
        manager.unlock_session(&session.id).unwrap();
        let validation = manager.validate_session(&session.id);
        assert!(validation.is_valid);
        assert_eq!(validation.state, SessionState::Active);
    }

    #[test]
    fn test_revoke_session() {
        let manager = SessionManager::new();
        let session = manager.create_session("wallet_123").unwrap();
        
        manager.revoke_session(&session.id).unwrap();
        let validation = manager.validate_session(&session.id);
        
        assert!(!validation.is_valid);
        assert_eq!(validation.state, SessionState::Revoked);
    }

    #[test]
    fn test_concurrent_session_limit() {
        let config = SessionConfig {
            max_concurrent: 2,
            ..Default::default()
        };
        let manager = SessionManager::with_config(config);
        
        manager.create_session("wallet_123").unwrap();
        manager.create_session("wallet_123").unwrap();
        
        let result = manager.create_session("wallet_123");
        assert!(result.is_err());
    }

    #[test]
    fn test_sensitive_op_requires_reauth() {
        let config = SessionConfig {
            require_reauth_for_sensitive: true,
            ..Default::default()
        };
        let manager = SessionManager::with_config(config);
        let session = manager.create_session("wallet_123").unwrap();
        
        // New session requires reauth for sensitive ops
        let validation = manager.validate_for_sensitive_op(&session.id);
        assert!(validation.requires_reauth);
        
        // After recording auth, no longer requires it
        manager.record_sensitive_auth(&session.id).unwrap();
        let validation = manager.validate_for_sensitive_op(&session.id);
        assert!(!validation.requires_reauth);
    }

    #[test]
    fn test_session_id_uniqueness() {
        let id1 = generate_session_id();
        let id2 = generate_session_id();
        assert_ne!(id1, id2);
    }
}
