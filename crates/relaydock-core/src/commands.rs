use crate::ports::{detect_conflict, next_available_port, PortClaim, PortConflict, PortUsage};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum BridgeCommand {
    CheckPortClaim(CheckPortClaimCommand),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CheckPortClaimCommand {
    pub claim: PortClaim,
    #[serde(default)]
    pub known_usages: Vec<PortUsage>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BridgeCommandResult {
    PortClaimCheck(PortClaimCheckResult),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortClaimCheckResult {
    pub claim: PortClaim,
    pub available: bool,
    pub conflict: Option<PortConflict>,
    pub suggested_port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BridgeResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<BridgeCommandResult>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<BridgeError>,
}

impl BridgeResponse {
    pub fn success(result: BridgeCommandResult) -> Self {
        Self {
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn failure(error: BridgeError) -> Self {
        Self {
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BridgeError {
    pub code: BridgeErrorCode,
    pub summary: String,
    pub detail: Option<String>,
    pub affected_port: Option<u16>,
    pub suggested_recovery: Option<String>,
}

impl BridgeError {
    pub fn invalid_command(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::InvalidCommand,
            summary: summary.into(),
            detail,
            affected_port: None,
            suggested_recovery: Some("Send one supported RelayDock bridge command as JSON.".into()),
        }
    }

    pub fn internal(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::InternalError,
            summary: summary.into(),
            detail,
            affected_port: None,
            suggested_recovery: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BridgeErrorCode {
    InvalidCommand,
    InternalError,
}

pub fn execute_bridge_command(command: BridgeCommand) -> Result<BridgeCommandResult, BridgeError> {
    match command {
        BridgeCommand::CheckPortClaim(command) => Ok(BridgeCommandResult::PortClaimCheck(
            check_port_claim(command.claim, command.known_usages),
        )),
    }
}

pub fn check_port_claim(claim: PortClaim, known_usages: Vec<PortUsage>) -> PortClaimCheckResult {
    let conflict = detect_conflict(&claim, &known_usages);
    let available = conflict.is_none();
    let suggested_port = conflict
        .as_ref()
        .and_then(|_| next_available_port(claim.port, &known_usages, claim.protocol.clone()));

    PortClaimCheckResult {
        claim,
        available,
        conflict,
        suggested_port,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{PortOwnerType, PortProtocol};
    use serde_json::json;

    fn tcp_claim(port: u16) -> PortClaim {
        PortClaim {
            port,
            protocol: PortProtocol::Tcp,
            owner_type: PortOwnerType::RelayDockRuntime,
            owner_ref: Some("runtime-1".to_string()),
        }
    }

    fn tcp_usage(port: u16) -> PortUsage {
        PortUsage {
            port,
            protocol: PortProtocol::Tcp,
            pid: Some(2233),
            process_name: Some("node".to_string()),
            command: Some("npm run dev".to_string()),
            owner_type: PortOwnerType::LocalProcess,
            owner_ref: None,
            killable: true,
        }
    }

    #[test]
    fn check_port_claim_returns_structured_conflict_and_suggestion() {
        let result = check_port_claim(tcp_claim(8088), vec![tcp_usage(8088), tcp_usage(8089)]);

        assert!(!result.available);
        assert_eq!(
            result.conflict.as_ref().map(|conflict| conflict.usage.port),
            Some(8088)
        );
        assert_eq!(result.suggested_port, Some(8090));
    }

    #[test]
    fn check_port_claim_omits_suggestion_when_requested_port_is_available() {
        let result = check_port_claim(tcp_claim(8088), vec![tcp_usage(8089)]);

        assert!(result.available);
        assert!(result.conflict.is_none());
        assert_eq!(result.suggested_port, None);
    }

    #[test]
    fn bridge_command_json_round_trips_to_structured_success_response() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "check_port_claim",
            "claim": {
                "port": 8088,
                "protocol": "Tcp",
                "owner_type": "RelayDockRuntime",
                "owner_ref": "runtime-1"
            },
            "known_usages": [
                {
                    "port": 8088,
                    "protocol": "Tcp",
                    "pid": 2233,
                    "process_name": "node",
                    "command": "npm run dev",
                    "owner_type": "LocalProcess",
                    "owner_ref": null,
                    "killable": true
                }
            ]
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "port_claim_check");
        assert_eq!(json["result"]["available"], false);
        assert_eq!(json["result"]["suggested_port"], 8089);
    }

    #[test]
    fn bridge_error_response_preserves_code_and_diagnostic_detail() {
        let response = BridgeResponse::failure(BridgeError::invalid_command(
            "Command JSON could not be parsed",
            Some("missing field `command`".to_string()),
        ));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], false);
        assert_eq!(json["error"]["code"], "invalid_command");
        assert_eq!(json["error"]["detail"], "missing field `command`");
        assert_eq!(
            json["error"]["suggested_recovery"],
            "Send one supported RelayDock bridge command as JSON."
        );
    }
}
