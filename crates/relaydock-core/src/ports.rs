use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortUsage {
    pub port: u16,
    pub protocol: PortProtocol,
    pub pid: Option<u32>,
    pub process_name: Option<String>,
    pub command: Option<String>,
    pub owner_type: PortOwnerType,
    pub owner_ref: Option<String>,
    pub killable: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PortProtocol {
    Tcp,
    Udp,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PortOwnerType {
    RelayDockRuntime,
    LocalProcess,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortClaim {
    pub port: u16,
    pub protocol: PortProtocol,
    pub owner_type: PortOwnerType,
    pub owner_ref: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortConflict {
    pub requested: PortClaim,
    pub usage: PortUsage,
}

pub fn find_usage(usages: &[PortUsage], protocol: PortProtocol, port: u16) -> Option<&PortUsage> {
    usages
        .iter()
        .find(|usage| usage.protocol == protocol && usage.port == port)
}

pub fn detect_conflict(claim: &PortClaim, usages: &[PortUsage]) -> Option<PortConflict> {
    find_usage(usages, claim.protocol.clone(), claim.port).map(|usage| PortConflict {
        requested: claim.clone(),
        usage: usage.clone(),
    })
}

pub fn next_available_port(
    preferred_port: u16,
    usages: &[PortUsage],
    protocol: PortProtocol,
) -> Option<u16> {
    (preferred_port..=u16::MAX).find(|port| find_usage(usages, protocol.clone(), *port).is_none())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tcp_usage(port: u16) -> PortUsage {
        PortUsage {
            port,
            protocol: PortProtocol::Tcp,
            pid: Some(1234),
            process_name: Some("node".to_string()),
            command: Some("npm run dev".to_string()),
            owner_type: PortOwnerType::LocalProcess,
            owner_ref: None,
            killable: true,
        }
    }

    #[test]
    fn detects_port_conflict_for_same_protocol_and_port() {
        let usage = tcp_usage(8088);
        let claim = PortClaim {
            port: 8088,
            protocol: PortProtocol::Tcp,
            owner_type: PortOwnerType::RelayDockRuntime,
            owner_ref: Some("runtime-1".to_string()),
        };

        let conflict = detect_conflict(&claim, &[usage]).expect("conflict exists");

        assert_eq!(conflict.requested.port, 8088);
        assert_eq!(conflict.usage.process_name.as_deref(), Some("node"));
    }

    #[test]
    fn suggests_next_available_port_by_incrementing() {
        let usages = [tcp_usage(8088), tcp_usage(8089)];

        let suggested = next_available_port(8088, &usages, PortProtocol::Tcp);

        assert_eq!(suggested, Some(8090));
    }

    #[test]
    fn udp_usage_does_not_conflict_with_tcp_claim() {
        let usage = PortUsage {
            protocol: PortProtocol::Udp,
            ..tcp_usage(8088)
        };
        let claim = PortClaim {
            port: 8088,
            protocol: PortProtocol::Tcp,
            owner_type: PortOwnerType::RelayDockRuntime,
            owner_ref: None,
        };

        assert!(detect_conflict(&claim, &[usage]).is_none());
    }
}
