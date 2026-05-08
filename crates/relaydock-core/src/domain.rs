use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt;

macro_rules! define_id {
    ($name:ident) => {
        #[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
        pub struct $name(String);

        impl $name {
            pub fn new(value: impl Into<String>) -> Self {
                Self(value.into())
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self::new(value)
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self::new(value)
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(&self.0)
            }
        }
    };
}

define_id!(HostId);
define_id!(ProviderTargetId);
define_id!(RuleId);
define_id!(PresetId);
define_id!(RuntimeInstanceId);

pub type Metadata = BTreeMap<String, String>;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Host {
    pub id: HostId,
    pub name: String,
    pub address: String,
    pub port: Option<u16>,
    pub user: Option<String>,
    pub tags: Vec<String>,
    pub os_family: OsFamily,
    pub os_distro: Option<String>,
    pub status_hint: HostStatusHint,
    pub provider_targets: Vec<ProviderTarget>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum OsFamily {
    MacOS,
    Linux,
    Windows,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum HostStatusHint {
    Unknown,
    Online,
    Offline,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderTarget {
    pub id: ProviderTargetId,
    pub host_id: HostId,
    pub target_type: ProviderTargetType,
    pub label: String,
    pub target_address: String,
    pub target_port: Option<u16>,
    pub auth_ref: Option<String>,
    pub meta: Metadata,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProviderTargetType {
    Ssh,
    Tailscale,
    Other(String),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rule {
    pub id: RuleId,
    pub host_id: HostId,
    pub name: String,
    pub alias: Option<LocalAlias>,
    #[serde(default)]
    pub access_mode: RuleAccessMode,
    #[serde(default)]
    pub provider_target_id: Option<ProviderTargetId>,
    pub remote_host: String,
    pub main_port: PortMapping,
    pub secondary_ports: Vec<PortMapping>,
    pub kind: Option<String>,
    pub icon_hint: Option<String>,
    pub tags: Vec<String>,
    pub notes: Option<String>,
}

pub type Service = Rule;

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RuleAccessMode {
    #[default]
    Forwarded,
    Direct,
    Local,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Preset {
    pub id: PresetId,
    pub name: String,
    pub host_id: HostId,
    pub base_preset_id: Option<PresetId>,
    pub items: Vec<PresetItem>,
    pub description: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PresetItem {
    pub rule_id: RuleId,
    pub provider_target_override: Option<ProviderTargetId>,
    pub local_port_overrides: Vec<PortMappingOverride>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortMapping {
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

impl PortMapping {
    pub fn new(local_port: u16, remote_host: impl Into<String>, remote_port: u16) -> Self {
        Self {
            local_port,
            remote_host: remote_host.into(),
            remote_port,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortMappingOverride {
    pub remote_host: String,
    pub remote_port: u16,
    pub effective_local_port: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalAlias {
    pub hostname: String,
    pub rule_id: RuleId,
    pub generated: bool,
    pub editable: bool,
}
