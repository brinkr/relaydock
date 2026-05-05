use crate::domain::{Host, Preset, Rule};
use crate::runtime::{LocalPortOverride, ProviderProcessRecord, RecoveryItem, RuntimeInstance};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

pub const SCHEMA_VERSION: i32 = 1;

const CURRENT_SNAPSHOT_KEY: &str = "current";

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConfigurationSnapshot {
    pub hosts: Vec<Host>,
    pub rules: Vec<Rule>,
    pub presets: Vec<Preset>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeSnapshot {
    pub instances: Vec<RuntimeInstance>,
    #[serde(default)]
    pub provider_processes: Vec<ProviderProcessRecord>,
    pub local_port_overrides: Vec<LocalPortOverride>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoveryCollection {
    pub items: Vec<RecoveryItem>,
}

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("sqlite storage error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("storage JSON serialization error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("storage validation failed: {0}")]
    Validation(#[from] StorageValidationError),
}

#[derive(Clone, Debug, PartialEq, Eq, Error)]
pub enum StorageValidationError {
    #[error("duplicate {entity} id `{id}`")]
    DuplicateId { entity: &'static str, id: String },
    #[error("{entity} `{id}` references missing {field} `{referenced_id}`")]
    MissingReference {
        entity: &'static str,
        id: String,
        field: &'static str,
        referenced_id: String,
    },
    #[error("rule `{rule_id}` uses provider target `{provider_target_id}` from host `{provider_target_host_id}`, not rule host `{host_id}`")]
    CrossHostProviderTarget {
        rule_id: String,
        host_id: String,
        provider_target_id: String,
        provider_target_host_id: String,
    },
    #[error("rule `{rule_id}` has a local alias pointing at `{alias_rule_id}`")]
    AliasRuleMismatch {
        rule_id: String,
        alias_rule_id: String,
    },
    #[error("provider target `{provider_target_id}` metadata key `{key}` looks like a credential and must not be stored in SQLite")]
    SensitiveCredentialMetadata {
        provider_target_id: String,
        key: String,
    },
    #[error(
        "duplicate recovery item for rule `{rule_id}` and provider target `{provider_target_id}`"
    )]
    DuplicateRecoveryItem {
        rule_id: String,
        provider_target_id: String,
    },
    #[error("duplicate provider process record for runtime instance `{runtime_instance_id}`")]
    DuplicateProviderProcess { runtime_instance_id: String },
}

pub struct RelayDockStore {
    connection: Connection,
}

impl RelayDockStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StorageError> {
        let store = Self {
            connection: Connection::open(path)?,
        };
        store.migrate()?;
        Ok(store)
    }

    pub fn in_memory() -> Result<Self, StorageError> {
        let store = Self {
            connection: Connection::open_in_memory()?,
        };
        store.migrate()?;
        Ok(store)
    }

    pub fn schema_version(&self) -> Result<i32, StorageError> {
        Ok(self
            .connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))?)
    }

    pub fn migration_versions(&self) -> Result<Vec<i32>, StorageError> {
        let mut statement = self
            .connection
            .prepare("SELECT version FROM schema_migrations ORDER BY version")?;
        let versions = statement
            .query_map([], |row| row.get(0))?
            .collect::<Result<Vec<i32>, _>>()?;

        Ok(versions)
    }

    pub fn save_configuration(
        &mut self,
        snapshot: &ConfigurationSnapshot,
    ) -> Result<(), StorageError> {
        validate_configuration(snapshot)?;

        let document = serde_json::to_string(snapshot)?;
        self.connection.execute(
            "INSERT INTO config_snapshots (snapshot_key, document, updated_at_ms)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(snapshot_key) DO UPDATE SET
               document = excluded.document,
               updated_at_ms = excluded.updated_at_ms",
            params![CURRENT_SNAPSHOT_KEY, document, current_time_millis()],
        )?;

        Ok(())
    }

    pub fn load_configuration(&self) -> Result<Option<ConfigurationSnapshot>, StorageError> {
        load_current_snapshot(&self.connection, "config_snapshots")
    }

    pub fn save_runtime_snapshot(
        &mut self,
        snapshot: &RuntimeSnapshot,
    ) -> Result<(), StorageError> {
        validate_runtime_snapshot(snapshot)?;

        let document = serde_json::to_string(snapshot)?;
        let override_rows = snapshot
            .local_port_overrides
            .iter()
            .map(|override_record| {
                serde_json::to_string(override_record).map(|document| (override_record, document))
            })
            .collect::<Result<Vec<_>, _>>()?;

        let updated_at_ms = current_time_millis();
        let transaction = self.connection.transaction()?;
        transaction.execute(
            "INSERT INTO runtime_snapshots (snapshot_key, document, updated_at_ms)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(snapshot_key) DO UPDATE SET
               document = excluded.document,
               updated_at_ms = excluded.updated_at_ms",
            params![CURRENT_SNAPSHOT_KEY, document, updated_at_ms],
        )?;
        transaction.execute("DELETE FROM runtime_local_port_overrides", [])?;

        for (override_record, document) in override_rows {
            transaction.execute(
                "INSERT INTO runtime_local_port_overrides (
                   runtime_instance_id,
                   original_port,
                   effective_port,
                   persisted,
                   document,
                   updated_at_ms
                 )
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    override_record.runtime_instance_id.as_str(),
                    override_record.original_port,
                    override_record.effective_port,
                    override_record.persisted,
                    document,
                    updated_at_ms,
                ],
            )?;
        }

        transaction.commit()?;
        Ok(())
    }

    pub fn load_runtime_snapshot(&self) -> Result<Option<RuntimeSnapshot>, StorageError> {
        load_current_snapshot(&self.connection, "runtime_snapshots")
    }

    pub fn save_recovery_collection(
        &mut self,
        collection: &RecoveryCollection,
    ) -> Result<(), StorageError> {
        validate_recovery_collection(collection)?;

        let rows = collection
            .items
            .iter()
            .map(|item| serde_json::to_string(item).map(|document| (item, document)))
            .collect::<Result<Vec<_>, _>>()?;
        let updated_at_ms = current_time_millis();

        let transaction = self.connection.transaction()?;
        transaction.execute("DELETE FROM recovery_items", [])?;

        for (item, document) in rows {
            transaction.execute(
                "INSERT INTO recovery_items (
                   rule_id,
                   host_id,
                   provider_target_id,
                   recoverable_since_ms,
                   document,
                   updated_at_ms
                 )
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    item.rule_id.as_str(),
                    item.host_id.as_str(),
                    item.provider_target_id.as_str(),
                    system_time_millis(item.recoverable_since),
                    document,
                    updated_at_ms,
                ],
            )?;
        }

        transaction.commit()?;
        Ok(())
    }

    pub fn load_recovery_collection(&self) -> Result<RecoveryCollection, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT document FROM recovery_items ORDER BY recoverable_since_ms ASC, rule_id ASC",
        )?;
        let mut rows = statement.query([])?;
        let mut items = Vec::new();

        while let Some(row) = rows.next()? {
            let document: String = row.get(0)?;
            items.push(serde_json::from_str(&document)?);
        }

        Ok(RecoveryCollection { items })
    }

    pub fn clear_recovery_item(
        &mut self,
        rule_id: impl AsRef<str>,
        provider_target_id: impl AsRef<str>,
    ) -> Result<(), StorageError> {
        self.connection.execute(
            "DELETE FROM recovery_items WHERE rule_id = ?1 AND provider_target_id = ?2",
            params![rule_id.as_ref(), provider_target_id.as_ref()],
        )?;

        Ok(())
    }

    fn migrate(&self) -> Result<(), StorageError> {
        self.connection.execute_batch(
            "
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              applied_at_ms INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS config_snapshots (
              snapshot_key TEXT PRIMARY KEY CHECK (snapshot_key = 'current'),
              document TEXT NOT NULL,
              updated_at_ms INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS runtime_snapshots (
              snapshot_key TEXT PRIMARY KEY CHECK (snapshot_key = 'current'),
              document TEXT NOT NULL,
              updated_at_ms INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS runtime_local_port_overrides (
              runtime_instance_id TEXT NOT NULL,
              original_port INTEGER NOT NULL CHECK (original_port BETWEEN 0 AND 65535),
              effective_port INTEGER NOT NULL CHECK (effective_port BETWEEN 0 AND 65535),
              persisted INTEGER NOT NULL CHECK (persisted IN (0, 1)),
              document TEXT NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              PRIMARY KEY (runtime_instance_id, original_port)
            );

            CREATE TABLE IF NOT EXISTS recovery_items (
              rule_id TEXT NOT NULL,
              host_id TEXT NOT NULL,
              provider_target_id TEXT NOT NULL,
              recoverable_since_ms INTEGER NOT NULL,
              document TEXT NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              PRIMARY KEY (rule_id, provider_target_id)
            );

            CREATE INDEX IF NOT EXISTS recovery_items_host_idx
              ON recovery_items(host_id);
            ",
        )?;
        self.connection.execute(
            "INSERT OR IGNORE INTO schema_migrations (version, applied_at_ms) VALUES (?1, ?2)",
            params![SCHEMA_VERSION, current_time_millis()],
        )?;
        self.connection
            .pragma_update(None, "user_version", SCHEMA_VERSION)?;

        Ok(())
    }
}

pub fn validate_configuration(
    snapshot: &ConfigurationSnapshot,
) -> Result<(), StorageValidationError> {
    let mut host_ids = BTreeSet::new();
    let mut provider_target_ids = BTreeSet::new();
    let mut provider_target_hosts = Vec::new();

    for host in &snapshot.hosts {
        insert_unique(&mut host_ids, "host", host.id.as_str())?;

        for target in &host.provider_targets {
            insert_unique(
                &mut provider_target_ids,
                "provider target",
                target.id.as_str(),
            )?;

            if target.host_id != host.id {
                return Err(StorageValidationError::MissingReference {
                    entity: "provider target",
                    id: target.id.to_string(),
                    field: "host_id",
                    referenced_id: target.host_id.to_string(),
                });
            }

            for key in target.meta.keys() {
                if looks_like_sensitive_key(key) {
                    return Err(StorageValidationError::SensitiveCredentialMetadata {
                        provider_target_id: target.id.to_string(),
                        key: key.clone(),
                    });
                }
            }

            provider_target_hosts.push((target.id.as_str(), host.id.as_str()));
        }
    }

    let mut rule_ids = BTreeSet::new();
    for rule in &snapshot.rules {
        insert_unique(&mut rule_ids, "rule", rule.id.as_str())?;

        if !host_ids.contains(rule.host_id.as_str()) {
            return Err(StorageValidationError::MissingReference {
                entity: "rule",
                id: rule.id.to_string(),
                field: "host_id",
                referenced_id: rule.host_id.to_string(),
            });
        }

        let provider_target_host_id = provider_target_hosts
            .iter()
            .find_map(|(target_id, host_id)| {
                (*target_id == rule.provider_target_id.as_str()).then_some(*host_id)
            })
            .ok_or_else(|| StorageValidationError::MissingReference {
                entity: "rule",
                id: rule.id.to_string(),
                field: "provider_target_id",
                referenced_id: rule.provider_target_id.to_string(),
            })?;

        if provider_target_host_id != rule.host_id.as_str() {
            return Err(StorageValidationError::CrossHostProviderTarget {
                rule_id: rule.id.to_string(),
                host_id: rule.host_id.to_string(),
                provider_target_id: rule.provider_target_id.to_string(),
                provider_target_host_id: provider_target_host_id.to_string(),
            });
        }

        if let Some(alias) = &rule.alias {
            if alias.rule_id != rule.id {
                return Err(StorageValidationError::AliasRuleMismatch {
                    rule_id: rule.id.to_string(),
                    alias_rule_id: alias.rule_id.to_string(),
                });
            }
        }
    }

    let mut preset_ids = BTreeSet::new();
    for preset in &snapshot.presets {
        insert_unique(&mut preset_ids, "preset", preset.id.as_str())?;

        if !host_ids.contains(preset.host_id.as_str()) {
            return Err(StorageValidationError::MissingReference {
                entity: "preset",
                id: preset.id.to_string(),
                field: "host_id",
                referenced_id: preset.host_id.to_string(),
            });
        }

        if let Some(base_preset_id) = &preset.base_preset_id {
            if !preset_ids.contains(base_preset_id.as_str())
                && !snapshot
                    .presets
                    .iter()
                    .any(|candidate| candidate.id == *base_preset_id)
            {
                return Err(StorageValidationError::MissingReference {
                    entity: "preset",
                    id: preset.id.to_string(),
                    field: "base_preset_id",
                    referenced_id: base_preset_id.to_string(),
                });
            }
        }

        for item in &preset.items {
            if !rule_ids.contains(item.rule_id.as_str()) {
                return Err(StorageValidationError::MissingReference {
                    entity: "preset item",
                    id: preset.id.to_string(),
                    field: "rule_id",
                    referenced_id: item.rule_id.to_string(),
                });
            }

            if let Some(provider_target_override) = &item.provider_target_override {
                if !provider_target_ids.contains(provider_target_override.as_str()) {
                    return Err(StorageValidationError::MissingReference {
                        entity: "preset item",
                        id: preset.id.to_string(),
                        field: "provider_target_override",
                        referenced_id: provider_target_override.to_string(),
                    });
                }
            }
        }
    }

    Ok(())
}

pub fn validate_runtime_snapshot(snapshot: &RuntimeSnapshot) -> Result<(), StorageValidationError> {
    let mut runtime_ids = BTreeSet::new();

    for instance in &snapshot.instances {
        insert_unique(&mut runtime_ids, "runtime instance", instance.id.as_str())?;
    }

    for override_record in &snapshot.local_port_overrides {
        if !runtime_ids.contains(override_record.runtime_instance_id.as_str()) {
            return Err(StorageValidationError::MissingReference {
                entity: "local port override",
                id: override_record.runtime_instance_id.to_string(),
                field: "runtime_instance_id",
                referenced_id: override_record.runtime_instance_id.to_string(),
            });
        }
    }

    let mut provider_process_ids = BTreeSet::new();
    for process in &snapshot.provider_processes {
        if !provider_process_ids.insert(process.runtime_instance_id.as_str().to_string()) {
            return Err(StorageValidationError::DuplicateProviderProcess {
                runtime_instance_id: process.runtime_instance_id.to_string(),
            });
        }

        if !runtime_ids.contains(process.runtime_instance_id.as_str()) {
            return Err(StorageValidationError::MissingReference {
                entity: "provider process",
                id: process.runtime_instance_id.to_string(),
                field: "runtime_instance_id",
                referenced_id: process.runtime_instance_id.to_string(),
            });
        }
    }

    Ok(())
}

pub fn validate_recovery_collection(
    collection: &RecoveryCollection,
) -> Result<(), StorageValidationError> {
    let mut recovery_keys = BTreeSet::new();

    for item in &collection.items {
        let key = (
            item.rule_id.as_str().to_string(),
            item.provider_target_id.as_str().to_string(),
        );

        if !recovery_keys.insert(key.clone()) {
            return Err(StorageValidationError::DuplicateRecoveryItem {
                rule_id: key.0,
                provider_target_id: key.1,
            });
        }
    }

    Ok(())
}

fn insert_unique(
    ids: &mut BTreeSet<String>,
    entity: &'static str,
    id: &str,
) -> Result<(), StorageValidationError> {
    if !ids.insert(id.to_string()) {
        return Err(StorageValidationError::DuplicateId {
            entity,
            id: id.to_string(),
        });
    }

    Ok(())
}

fn load_current_snapshot<T>(
    connection: &Connection,
    table_name: &'static str,
) -> Result<Option<T>, StorageError>
where
    T: DeserializeOwned,
{
    let document = connection
        .query_row(
            &format!("SELECT document FROM {table_name} WHERE snapshot_key = ?1"),
            params![CURRENT_SNAPSHOT_KEY],
            |row| row.get::<_, String>(0),
        )
        .optional()?;

    document
        .map(|document| serde_json::from_str(&document))
        .transpose()
        .map_err(StorageError::from)
}

fn current_time_millis() -> i64 {
    system_time_millis(SystemTime::now())
}

fn system_time_millis(time: SystemTime) -> i64 {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn looks_like_sensitive_key(key: &str) -> bool {
    let normalized = key.to_ascii_lowercase();
    ["password", "private_key", "secret", "token", "credential"]
        .iter()
        .any(|needle| normalized.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        HostId, HostStatusHint, LocalAlias, Metadata, OsFamily, PortMapping, PresetId, PresetItem,
        ProviderTarget, ProviderTargetId, ProviderTargetType, RuleId, RuntimeInstanceId,
    };
    use crate::ports::{PortOwnerType, PortProtocol, PortUsage};
    use crate::runtime::{
        LocalPortBinding, OverrideReason, RuntimeErrorCode, RuntimeErrorInfo, RuntimeStatus,
    };

    fn ssh_target(host_id: &HostId) -> ProviderTarget {
        ProviderTarget {
            id: ProviderTargetId::from("target-1"),
            host_id: host_id.clone(),
            target_type: ProviderTargetType::Ssh,
            label: "SSH · 家庭宽带".to_string(),
            target_address: "192.168.1.5".to_string(),
            target_port: Some(22),
            auth_ref: Some("keychain://ssh/home".to_string()),
            meta: Metadata::new(),
        }
    }

    fn configuration() -> ConfigurationSnapshot {
        let host_id = HostId::from("host-1");
        let target = ssh_target(&host_id);
        let rule_id = RuleId::from("rule-1");

        ConfigurationSnapshot {
            hosts: vec![Host {
                id: host_id.clone(),
                name: "Mac mini".to_string(),
                address: "192.168.1.5".to_string(),
                port: Some(22),
                user: Some("admin".to_string()),
                tags: vec!["home".to_string()],
                os_family: OsFamily::MacOS,
                os_distro: None,
                status_hint: HostStatusHint::Unknown,
                provider_targets: vec![target.clone()],
            }],
            rules: vec![Rule {
                id: rule_id.clone(),
                host_id: host_id.clone(),
                name: "React 前端".to_string(),
                alias: Some(LocalAlias {
                    hostname: "react.home.localhost".to_string(),
                    rule_id: rule_id.clone(),
                    generated: true,
                    editable: true,
                }),
                provider_target_id: target.id,
                remote_host: "127.0.0.1".to_string(),
                main_port: PortMapping::new(3000, "127.0.0.1", 3000),
                secondary_ports: Vec::new(),
                kind: Some("web".to_string()),
                icon_hint: None,
                tags: Vec::new(),
                notes: None,
            }],
            presets: vec![crate::domain::Preset {
                id: PresetId::from("preset-1"),
                name: "日常开发".to_string(),
                host_id,
                base_preset_id: None,
                items: vec![PresetItem {
                    rule_id,
                    provider_target_override: None,
                    local_port_overrides: Vec::new(),
                }],
                description: None,
            }],
        }
    }

    fn runtime_with_override() -> (RuntimeSnapshot, ConfigurationSnapshot) {
        let mut runtime = RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-1"),
            RuleId::from("rule-1"),
            HostId::from("host-1"),
            ProviderTargetId::from("target-1"),
            vec![LocalPortBinding::new(3000, "127.0.0.1", 3000)],
        );
        runtime.mark_error(
            RuntimeErrorInfo::new(RuntimeErrorCode::PortConflict, "local port conflict")
                .with_detail("3000 is already used by node"),
        );

        let override_record = runtime
            .apply_local_port_override(
                3000,
                3001,
                OverrideReason::Conflict {
                    usage: Box::new(PortUsage {
                        port: 3000,
                        protocol: PortProtocol::Tcp,
                        pid: Some(2233),
                        process_name: Some("node".to_string()),
                        command: Some("npm run dev".to_string()),
                        owner_type: PortOwnerType::LocalProcess,
                        owner_ref: None,
                        killable: true,
                    }),
                },
            )
            .expect("binding exists");

        (
            RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: Vec::new(),
                local_port_overrides: vec![override_record],
            },
            configuration(),
        )
    }

    #[test]
    fn migration_creates_schema_version() {
        let store = RelayDockStore::in_memory().expect("store opens");

        assert_eq!(
            store.schema_version().expect("schema version"),
            SCHEMA_VERSION
        );
        assert_eq!(store.migration_versions().expect("migration rows"), vec![1]);
    }

    #[test]
    fn configuration_snapshot_round_trips() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let snapshot = configuration();

        store
            .save_configuration(&snapshot)
            .expect("configuration saves");
        let loaded = store
            .load_configuration()
            .expect("configuration loads")
            .expect("configuration exists");

        assert_eq!(loaded, snapshot);
    }

    #[test]
    fn sensitive_provider_metadata_is_rejected() {
        let mut snapshot = configuration();
        snapshot.hosts[0].provider_targets[0]
            .meta
            .insert("password".to_string(), "plain-text".to_string());

        let error = validate_configuration(&snapshot).expect_err("password must be rejected");

        assert!(matches!(
            error,
            StorageValidationError::SensitiveCredentialMetadata { .. }
        ));
    }

    #[test]
    fn runtime_override_persists_without_mutating_saved_rule_configuration() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let (runtime_snapshot, configuration_snapshot) = runtime_with_override();

        store
            .save_configuration(&configuration_snapshot)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&runtime_snapshot)
            .expect("runtime saves");

        let loaded_configuration = store
            .load_configuration()
            .expect("configuration loads")
            .expect("configuration exists");
        let loaded_runtime = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");

        assert_eq!(loaded_configuration.rules[0].main_port.local_port, 3000);
        assert_eq!(
            loaded_runtime.instances[0].local_bindings[0].local_port,
            3001
        );
        assert!(loaded_runtime.instances[0].local_bindings[0].temporary_override);
        assert!(!loaded_runtime.local_port_overrides[0].persisted);
    }

    #[test]
    fn recovery_collection_round_trips_and_can_clear_one_item() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let recovery = RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-1"),
            RuleId::from("rule-1"),
            HostId::from("host-1"),
            ProviderTargetId::from("target-1"),
            vec![LocalPortBinding::new(3000, "127.0.0.1", 3000)],
        )
        .stop(UNIX_EPOCH);

        store
            .save_recovery_collection(&RecoveryCollection {
                items: vec![recovery],
            })
            .expect("recovery saves");
        assert_eq!(
            store
                .load_recovery_collection()
                .expect("recovery loads")
                .items
                .len(),
            1
        );

        store
            .clear_recovery_item("rule-1", "target-1")
            .expect("recovery clears");
        assert!(store
            .load_recovery_collection()
            .expect("recovery reloads")
            .items
            .is_empty());
    }

    #[test]
    fn rule_cannot_reference_provider_target_from_another_host() {
        let mut snapshot = configuration();
        snapshot.hosts.push(Host {
            id: HostId::from("host-2"),
            name: "Jump host".to_string(),
            address: "jump.example.com".to_string(),
            port: Some(22),
            user: Some("admin".to_string()),
            tags: Vec::new(),
            os_family: OsFamily::Linux,
            os_distro: None,
            status_hint: HostStatusHint::Unknown,
            provider_targets: vec![ProviderTarget {
                id: ProviderTargetId::from("target-2"),
                host_id: HostId::from("host-2"),
                target_type: ProviderTargetType::Ssh,
                label: "SSH · 跳板".to_string(),
                target_address: "jump.example.com".to_string(),
                target_port: Some(22),
                auth_ref: Some("keychain://ssh/jump".to_string()),
                meta: Metadata::new(),
            }],
        });
        snapshot.rules[0].provider_target_id = ProviderTargetId::from("target-2");

        let error = validate_configuration(&snapshot).expect_err("cross-host target is invalid");

        assert!(matches!(
            error,
            StorageValidationError::CrossHostProviderTarget { .. }
        ));
    }

    #[test]
    fn runtime_override_must_reference_an_existing_runtime_instance() {
        let (mut snapshot, _) = runtime_with_override();
        snapshot.local_port_overrides[0].runtime_instance_id = RuntimeInstanceId::from("missing");

        let error = validate_runtime_snapshot(&snapshot).expect_err("runtime id is missing");

        assert!(matches!(
            error,
            StorageValidationError::MissingReference {
                entity: "local port override",
                ..
            }
        ));
    }

    #[test]
    fn provider_process_must_reference_an_existing_runtime_instance() {
        let (mut snapshot, _) = runtime_with_override();
        snapshot.provider_processes.push(ProviderProcessRecord {
            runtime_instance_id: RuntimeInstanceId::from("missing"),
            provider_kind: crate::runtime::ProviderProcessKind::OpenSsh,
            pid: 4242,
            command_summary: "ssh -N -T".to_string(),
            target_label: "SSH · 家庭宽带".to_string(),
            started_at: None,
            last_observed_at: UNIX_EPOCH,
        });

        let error = validate_runtime_snapshot(&snapshot).expect_err("runtime id is missing");

        assert!(matches!(
            error,
            StorageValidationError::MissingReference {
                entity: "provider process",
                ..
            }
        ));
    }

    #[test]
    fn duplicate_provider_process_records_are_rejected() {
        let (mut snapshot, _) = runtime_with_override();
        snapshot.provider_processes.push(ProviderProcessRecord {
            runtime_instance_id: RuntimeInstanceId::from("runtime-1"),
            provider_kind: crate::runtime::ProviderProcessKind::OpenSsh,
            pid: 4242,
            command_summary: "ssh -N -T".to_string(),
            target_label: "SSH · 家庭宽带".to_string(),
            started_at: None,
            last_observed_at: UNIX_EPOCH,
        });
        snapshot
            .provider_processes
            .push(snapshot.provider_processes[0].clone());

        let error = validate_runtime_snapshot(&snapshot).expect_err("duplicate process is invalid");

        assert!(matches!(
            error,
            StorageValidationError::DuplicateProviderProcess { .. }
        ));
    }

    #[test]
    fn duplicate_recovery_items_are_rejected() {
        let item = RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-1"),
            RuleId::from("rule-1"),
            HostId::from("host-1"),
            ProviderTargetId::from("target-1"),
            vec![LocalPortBinding::new(3000, "127.0.0.1", 3000)],
        )
        .stop(UNIX_EPOCH);
        let collection = RecoveryCollection {
            items: vec![item.clone(), item],
        };

        let error =
            validate_recovery_collection(&collection).expect_err("duplicate recovery is invalid");

        assert!(matches!(
            error,
            StorageValidationError::DuplicateRecoveryItem { .. }
        ));
    }

    #[test]
    fn recovery_item_keeps_last_seen_runtime_status() {
        let mut runtime = RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-1"),
            RuleId::from("rule-1"),
            HostId::from("host-1"),
            ProviderTargetId::from("target-1"),
            vec![LocalPortBinding::new(3000, "127.0.0.1", 3000)],
        );
        runtime.mark_reconnecting("network changed");

        let recovery = runtime.stop(UNIX_EPOCH);

        assert_eq!(recovery.last_seen_status, RuntimeStatus::Reconnecting);
    }
}
