use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParseSshCommandCommand {
    pub command_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParseSshCommandResult {
    pub destination_hint: Option<SshDestinationHint>,
    pub provider_target_hint: Option<SshProviderTargetHint>,
    #[serde(default)]
    pub rule_drafts: Vec<SshImportedRuleDraft>,
    #[serde(default)]
    pub diagnostics: Vec<SshCommandParseDiagnostic>,
}

impl ParseSshCommandResult {
    fn empty_with_diagnostics(diagnostics: Vec<SshCommandParseDiagnostic>) -> Self {
        Self {
            destination_hint: None,
            provider_target_hint: None,
            rule_drafts: Vec::new(),
            diagnostics,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SshDestinationHint {
    pub host: String,
    pub user: Option<String>,
    pub port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SshProviderTargetHint {
    pub target_address: String,
    pub target_port: Option<u16>,
    pub user: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SshImportedRuleDraft {
    pub forward_index: usize,
    pub service_name: String,
    pub alias: Option<String>,
    pub remote_host: String,
    pub local_port: u16,
    pub remote_port: u16,
    pub kind: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SshCommandParseDiagnostic {
    pub severity: SshCommandParseDiagnosticSeverity,
    pub summary: String,
    pub detail: Option<String>,
    pub forward_spec: Option<String>,
}

impl SshCommandParseDiagnostic {
    fn error(
        summary: impl Into<String>,
        detail: Option<String>,
        forward_spec: Option<&str>,
    ) -> Self {
        Self {
            severity: SshCommandParseDiagnosticSeverity::Error,
            summary: summary.into(),
            detail,
            forward_spec: forward_spec.map(str::to_string),
        }
    }

    fn warning(
        summary: impl Into<String>,
        detail: Option<String>,
        forward_spec: Option<&str>,
    ) -> Self {
        Self {
            severity: SshCommandParseDiagnosticSeverity::Warning,
            summary: summary.into(),
            detail,
            forward_spec: forward_spec.map(str::to_string),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SshCommandParseDiagnosticSeverity {
    Warning,
    Error,
}

pub fn parse_ssh_command(command_text: &str) -> ParseSshCommandResult {
    let trimmed = command_text.trim();
    if trimmed.is_empty() {
        return ParseSshCommandResult::empty_with_diagnostics(vec![
            SshCommandParseDiagnostic::error(
                "SSH 命令为空",
                Some("请粘贴一整行 ssh -L ... 命令后再解析。".to_string()),
                None,
            ),
        ]);
    }

    let tokens = match tokenize_shell_words(trimmed) {
        Ok(tokens) => tokens,
        Err(detail) => {
            return ParseSshCommandResult::empty_with_diagnostics(vec![
                SshCommandParseDiagnostic::error("SSH 命令无法解析", Some(detail), None),
            ]);
        }
    };

    let parsed = parse_command_tokens(&tokens);
    let destination_hint = build_destination_hint(
        parsed.destination_token.as_deref(),
        parsed.user,
        parsed.port,
    );
    let provider_target_hint = destination_hint.as_ref().map(|hint| SshProviderTargetHint {
        target_address: hint.host.clone(),
        target_port: hint.port,
        user: hint.user.clone(),
    });

    let mut rule_drafts = Vec::new();
    let mut diagnostics = parsed.diagnostics;

    for (index, forward_spec) in parsed.local_forward_specs.iter().enumerate() {
        match parse_local_forward(forward_spec) {
            Ok(forward) => {
                if let Some(bind_address) = forward.bind_address.as_deref() {
                    if !is_loopback_bind_address(bind_address) {
                        diagnostics.push(SshCommandParseDiagnostic::warning(
                            "本地绑定地址不会写入规则",
                            Some(format!(
                                "当前版本会导入端口映射，但不会保存 bind_address=`{bind_address}`。"
                            )),
                            Some(forward_spec),
                        ));
                    }
                }

                rule_drafts.push(import_rule_draft_from_forward(index + 1, &forward));
            }
            Err(diagnostic) => diagnostics.push(diagnostic),
        }
    }

    if parsed.local_forward_specs.is_empty() {
        diagnostics.push(SshCommandParseDiagnostic::error(
            "未找到可导入的 -L 本地转发",
            Some("当前版本只支持从 ssh 命令里导入 -L 本地转发参数。".to_string()),
            None,
        ));
    }

    ParseSshCommandResult {
        destination_hint,
        provider_target_hint,
        rule_drafts,
        diagnostics,
    }
}

#[derive(Default)]
struct ParsedCommandTokens {
    destination_token: Option<String>,
    user: Option<String>,
    port: Option<u16>,
    local_forward_specs: Vec<String>,
    diagnostics: Vec<SshCommandParseDiagnostic>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ParsedLocalForward {
    bind_address: Option<String>,
    local_port: u16,
    remote_host: String,
    remote_port: u16,
}

fn parse_command_tokens(tokens: &[String]) -> ParsedCommandTokens {
    let mut parsed = ParsedCommandTokens::default();
    let mut index = if tokens
        .first()
        .is_some_and(|token| matches!(token.as_str(), "ssh" | "autossh"))
    {
        1
    } else {
        0
    };

    while index < tokens.len() {
        let token = &tokens[index];

        if token == "--" {
            if parsed.destination_token.is_none() && index + 1 < tokens.len() {
                parsed.destination_token = Some(tokens[index + 1].clone());
            }
            break;
        }

        if let Some(spec) = attached_value(token, "-L") {
            parsed.local_forward_specs.push(spec.to_string());
            index += 1;
            continue;
        }

        if token == "-L" {
            if let Some(spec) = tokens.get(index + 1) {
                parsed.local_forward_specs.push(spec.clone());
                index += 2;
            } else {
                parsed.diagnostics.push(SshCommandParseDiagnostic::error(
                    "SSH 命令缺少 -L 转发参数",
                    Some(
                        "`-L` 后面需要跟一个 `local_port:remote_host:remote_port` 形式的转发定义。"
                            .to_string(),
                    ),
                    None,
                ));
                index += 1;
            }
            continue;
        }

        if let Some(spec) = attached_value(token, "-R") {
            parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                "暂不支持导入 -R 远端转发",
                Some("本次导入只会处理 -L 本地转发；请手动补充对应规则。".to_string()),
                Some(spec),
            ));
            index += 1;
            continue;
        }

        if token == "-R" {
            parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                "暂不支持导入 -R 远端转发",
                Some("本次导入只会处理 -L 本地转发；请手动补充对应规则。".to_string()),
                tokens.get(index + 1).map(String::as_str),
            ));
            index += usize::from(index + 1 < tokens.len()) + 1;
            continue;
        }

        if let Some(spec) = attached_value(token, "-D") {
            parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                "暂不支持导入 -D 动态转发",
                Some("本次导入只会处理 -L 本地转发；请手动补充对应规则。".to_string()),
                Some(spec),
            ));
            index += 1;
            continue;
        }

        if token == "-D" {
            parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                "暂不支持导入 -D 动态转发",
                Some("本次导入只会处理 -L 本地转发；请手动补充对应规则。".to_string()),
                tokens.get(index + 1).map(String::as_str),
            ));
            index += usize::from(index + 1 < tokens.len()) + 1;
            continue;
        }

        if let Some(port_text) = attached_value(token, "-p") {
            parsed.port = parse_optional_port_hint(port_text, &mut parsed.diagnostics, "-p");
            index += 1;
            continue;
        }

        if token == "-p" {
            if let Some(port_text) = tokens.get(index + 1) {
                parsed.port = parse_optional_port_hint(port_text, &mut parsed.diagnostics, "-p");
                index += 2;
            } else {
                parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                    "SSH 命令缺少目标端口",
                    Some("`-p` 后面需要跟远端 SSH 端口号。".to_string()),
                    None,
                ));
                index += 1;
            }
            continue;
        }

        if let Some(user_text) = attached_value(token, "-l") {
            if !user_text.trim().is_empty() {
                parsed.user = Some(user_text.trim().to_string());
            }
            index += 1;
            continue;
        }

        if token == "-l" {
            if let Some(user_text) = tokens.get(index + 1) {
                if !user_text.trim().is_empty() {
                    parsed.user = Some(user_text.trim().to_string());
                }
                index += 2;
            } else {
                parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                    "SSH 命令缺少登录用户",
                    Some("`-l` 后面需要跟登录用户名。".to_string()),
                    None,
                ));
                index += 1;
            }
            continue;
        }

        if let Some(option_text) = attached_value(token, "-o") {
            apply_config_option(option_text, &mut parsed);
            index += 1;
            continue;
        }

        if token == "-o" {
            if let Some(option_text) = tokens.get(index + 1) {
                apply_config_option(option_text, &mut parsed);
                index += 2;
            } else {
                parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
                    "SSH 命令缺少 -o 配置项",
                    Some("`-o` 后面需要跟一个 OpenSSH 配置项。".to_string()),
                    None,
                ));
                index += 1;
            }
            continue;
        }

        if option_consumes_next(token) {
            index += usize::from(index + 1 < tokens.len()) + 1;
            continue;
        }

        if token.starts_with('-') {
            index += 1;
            continue;
        }

        if parsed.destination_token.is_none() {
            parsed.destination_token = Some(token.clone());
            index += 1;
            continue;
        }

        break;
    }

    parsed
}

fn apply_config_option(option_text: &str, parsed: &mut ParsedCommandTokens) {
    let Some((keyword, value)) = split_config_option(option_text) else {
        return;
    };

    match keyword.to_ascii_lowercase().as_str() {
        "localforward" => {
            if value.is_empty() {
                parsed.diagnostics.push(SshCommandParseDiagnostic::error(
                    "SSH LocalForward 缺少转发参数",
                    Some(
                        "`LocalForward` 后面需要跟一个 `local_port:remote_host:remote_port` 形式的转发定义。"
                            .to_string(),
                    ),
                    Some(option_text),
                ));
            } else {
                parsed.local_forward_specs.push(value.to_string());
            }
        }
        "remoteforward" => parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
            "暂不支持导入 RemoteForward 远端转发",
            Some("本次导入只会处理 -L / LocalForward 本地转发；请手动补充对应规则。".to_string()),
            Some(value),
        )),
        "dynamicforward" => parsed.diagnostics.push(SshCommandParseDiagnostic::warning(
            "暂不支持导入 DynamicForward 动态转发",
            Some("本次导入只会处理 -L / LocalForward 本地转发；请手动补充对应规则。".to_string()),
            Some(value),
        )),
        _ => {}
    }
}

fn split_config_option(option_text: &str) -> Option<(&str, &str)> {
    let trimmed = option_text.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Some((keyword, value)) = trimmed.split_once('=') {
        return Some((keyword.trim(), value.trim()));
    }

    trimmed
        .split_once(char::is_whitespace)
        .map(|(keyword, value)| (keyword.trim(), value.trim()))
}

fn parse_local_forward(
    forward_spec: &str,
) -> Result<ParsedLocalForward, SshCommandParseDiagnostic> {
    if let Some(forward) = parse_spaced_local_forward(forward_spec)? {
        return Ok(forward);
    }

    let parts = forward_spec.split(':').collect::<Vec<_>>();
    let (bind_address, local_port_text, remote_host_text, remote_port_text) = match parts.as_slice()
    {
        [local_port, remote_host, remote_port] => (None, *local_port, *remote_host, *remote_port),
        [bind_address, local_port, remote_host, remote_port] => (
            Some(bind_address.trim().to_string()),
            *local_port,
            *remote_host,
            *remote_port,
        ),
        _ => {
            return Err(SshCommandParseDiagnostic::error(
                "SSH 本地转发格式不受支持",
                Some(
                    "请使用 `local_port:remote_host:remote_port` 或 `bind_address:local_port:remote_host:remote_port`。"
                        .to_string(),
                ),
                Some(forward_spec),
            ));
        }
    };

    let local_port = parse_forward_port(local_port_text, "本地端口", forward_spec)?;
    let remote_port = parse_forward_port(remote_port_text, "远端端口", forward_spec)?;
    let remote_host = remote_host_text.trim();
    if remote_host.is_empty() {
        return Err(SshCommandParseDiagnostic::error(
            "SSH 本地转发缺少远端主机",
            Some("remote_host 不能为空。".to_string()),
            Some(forward_spec),
        ));
    }

    Ok(ParsedLocalForward {
        bind_address,
        local_port,
        remote_host: remote_host.to_string(),
        remote_port,
    })
}

fn parse_spaced_local_forward(
    forward_spec: &str,
) -> Result<Option<ParsedLocalForward>, SshCommandParseDiagnostic> {
    let Some((local_text, remote_text)) = forward_spec.trim().split_once(char::is_whitespace)
    else {
        return Ok(None);
    };
    let remote_text = remote_text.trim();
    if remote_text.contains(char::is_whitespace) {
        return Ok(None);
    }

    let (bind_address, local_port_text) = split_local_forward_endpoint(local_text)?;
    let Some((remote_host_text, remote_port_text)) = remote_text.rsplit_once(':') else {
        return Err(SshCommandParseDiagnostic::error(
            "SSH LocalForward 远端格式不受支持",
            Some("请使用 `local_port remote_host:remote_port`。".to_string()),
            Some(forward_spec),
        ));
    };

    let local_port = parse_forward_port(local_port_text, "本地端口", forward_spec)?;
    let remote_port = parse_forward_port(remote_port_text, "远端端口", forward_spec)?;
    let remote_host = normalized_forward_host(remote_host_text);
    if remote_host.is_empty() {
        return Err(SshCommandParseDiagnostic::error(
            "SSH 本地转发缺少远端主机",
            Some("remote_host 不能为空。".to_string()),
            Some(forward_spec),
        ));
    }

    Ok(Some(ParsedLocalForward {
        bind_address,
        local_port,
        remote_host,
        remote_port,
    }))
}

fn split_local_forward_endpoint(
    local_text: &str,
) -> Result<(Option<String>, &str), SshCommandParseDiagnostic> {
    match local_text.split(':').collect::<Vec<_>>().as_slice() {
        [local_port] => Ok((None, *local_port)),
        [bind_address, local_port] => Ok((Some(bind_address.trim().to_string()), *local_port)),
        _ => Err(SshCommandParseDiagnostic::error(
            "SSH LocalForward 本地格式不受支持",
            Some("请使用 `local_port remote_host:remote_port` 或 `bind_address:local_port remote_host:remote_port`。".to_string()),
            Some(local_text),
        )),
    }
}

fn normalized_forward_host(host_text: &str) -> String {
    host_text.trim().trim_matches(&['[', ']'][..]).to_string()
}

fn import_rule_draft_from_forward(
    index: usize,
    forward: &ParsedLocalForward,
) -> SshImportedRuleDraft {
    let blueprint = infer_service_blueprint(forward.local_port, forward.remote_port);

    SshImportedRuleDraft {
        forward_index: index,
        service_name: blueprint.service_name,
        alias: Some(format!("{}.localhost", blueprint.alias_stem)),
        remote_host: forward.remote_host.clone(),
        local_port: forward.local_port,
        remote_port: forward.remote_port,
        kind: blueprint.kind.map(str::to_string),
        tags: Vec::new(),
    }
}

struct ServiceBlueprint {
    service_name: String,
    alias_stem: String,
    kind: Option<&'static str>,
}

fn infer_service_blueprint(local_port: u16, remote_port: u16) -> ServiceBlueprint {
    match remote_port {
        80 | 443 | 3000 | 3001 | 4173 | 4200 | 5000 | 5173 | 8000 | 8080 | 8081 | 8088 | 9000
        | 9090 => ServiceBlueprint {
            service_name: format!("Web {local_port}"),
            alias_stem: format!("web-{local_port}"),
            kind: Some("web"),
        },
        5432 => ServiceBlueprint {
            service_name: format!("Postgres {local_port}"),
            alias_stem: format!("postgres-{local_port}"),
            kind: Some("database"),
        },
        3306 => ServiceBlueprint {
            service_name: format!("MySQL {local_port}"),
            alias_stem: format!("mysql-{local_port}"),
            kind: Some("database"),
        },
        6379 => ServiceBlueprint {
            service_name: format!("Redis {local_port}"),
            alias_stem: format!("redis-{local_port}"),
            kind: Some("cache"),
        },
        27017 => ServiceBlueprint {
            service_name: format!("MongoDB {local_port}"),
            alias_stem: format!("mongodb-{local_port}"),
            kind: Some("database"),
        },
        5672 => ServiceBlueprint {
            service_name: format!("RabbitMQ {local_port}"),
            alias_stem: format!("rabbitmq-{local_port}"),
            kind: Some("queue"),
        },
        15672 => ServiceBlueprint {
            service_name: format!("RabbitMQ 管理台 {local_port}"),
            alias_stem: format!("rabbitmq-admin-{local_port}"),
            kind: Some("web"),
        },
        9200 => ServiceBlueprint {
            service_name: format!("Elasticsearch {local_port}"),
            alias_stem: format!("elasticsearch-{local_port}"),
            kind: Some("search"),
        },
        5601 => ServiceBlueprint {
            service_name: format!("Kibana {local_port}"),
            alias_stem: format!("kibana-{local_port}"),
            kind: Some("web"),
        },
        _ => ServiceBlueprint {
            service_name: format!("转发 {local_port}"),
            alias_stem: format!("ssh-{local_port}"),
            kind: None,
        },
    }
}

fn parse_forward_port(
    value: &str,
    label: &str,
    forward_spec: &str,
) -> Result<u16, SshCommandParseDiagnostic> {
    let trimmed = value.trim();
    match trimmed.parse::<u16>() {
        Ok(port) if port > 0 => Ok(port),
        _ => Err(SshCommandParseDiagnostic::error(
            format!("{label}无效"),
            Some(format!("`{trimmed}` 不是 1-65535 之间的端口。")),
            Some(forward_spec),
        )),
    }
}

fn build_destination_hint(
    destination_token: Option<&str>,
    explicit_user: Option<String>,
    explicit_port: Option<u16>,
) -> Option<SshDestinationHint> {
    let token = destination_token?.trim();
    if token.is_empty() {
        return None;
    }

    let scheme_trimmed = token.strip_prefix("ssh://").unwrap_or(token);
    let (token_user, host_port_text) = match scheme_trimmed.rsplit_once('@') {
        Some((user, host_port)) if !user.trim().is_empty() && !host_port.trim().is_empty() => {
            (Some(user.trim().to_string()), host_port.trim())
        }
        _ => (None, scheme_trimmed),
    };
    let (host, token_port) = split_host_and_port(token, host_port_text);
    if host.is_empty() {
        return None;
    }

    Some(SshDestinationHint {
        host,
        user: explicit_user.or(token_user),
        port: explicit_port.or(token_port),
    })
}

fn split_host_and_port(original_token: &str, host_port_text: &str) -> (String, Option<u16>) {
    if !original_token.starts_with("ssh://") {
        return (
            host_port_text.trim_matches(&['[', ']'][..]).to_string(),
            None,
        );
    }

    if let Some(stripped) = host_port_text.strip_prefix('[') {
        if let Some((host, rest)) = stripped.split_once(']') {
            let port = rest
                .strip_prefix(':')
                .and_then(|value| value.parse::<u16>().ok())
                .filter(|port| *port > 0);
            return (host.to_string(), port);
        }
    }

    if let Some((host, port_text)) = host_port_text.rsplit_once(':') {
        if let Ok(port) = port_text.parse::<u16>() {
            if port > 0 {
                return (host.to_string(), Some(port));
            }
        }
    }

    (host_port_text.to_string(), None)
}

fn parse_optional_port_hint(
    value: &str,
    diagnostics: &mut Vec<SshCommandParseDiagnostic>,
    flag: &str,
) -> Option<u16> {
    let trimmed = value.trim();
    match trimmed.parse::<u16>() {
        Ok(port) if port > 0 => Some(port),
        _ => {
            diagnostics.push(SshCommandParseDiagnostic::warning(
                "SSH 目标端口无效",
                Some(format!(
                    "`{flag}` 后面的 `{trimmed}` 不是 1-65535 之间的端口。"
                )),
                None,
            ));
            None
        }
    }
}

fn tokenize_shell_words(input: &str) -> Result<Vec<String>, String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_single_quote = false;
    let mut in_double_quote = false;
    let mut escape_next = false;

    for character in input.chars() {
        if escape_next {
            current.push(character);
            escape_next = false;
            continue;
        }

        if in_single_quote {
            if character == '\'' {
                in_single_quote = false;
            } else {
                current.push(character);
            }
            continue;
        }

        if in_double_quote {
            match character {
                '"' => in_double_quote = false,
                '\\' => escape_next = true,
                _ => current.push(character),
            }
            continue;
        }

        match character {
            '\'' => in_single_quote = true,
            '"' => in_double_quote = true,
            '\\' => escape_next = true,
            character if character.is_whitespace() => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            _ => current.push(character),
        }
    }

    if escape_next {
        return Err("命令末尾存在未完成的转义字符。".to_string());
    }

    if in_single_quote || in_double_quote {
        return Err("命令中存在未闭合的引号。".to_string());
    }

    if !current.is_empty() {
        tokens.push(current);
    }

    Ok(tokens)
}

fn attached_value<'a>(token: &'a str, prefix: &str) -> Option<&'a str> {
    token.strip_prefix(prefix).filter(|value| !value.is_empty())
}

fn option_consumes_next(token: &str) -> bool {
    matches!(
        token,
        "-b" | "-c"
            | "-E"
            | "-e"
            | "-F"
            | "-I"
            | "-i"
            | "-J"
            | "-m"
            | "-O"
            | "-o"
            | "-Q"
            | "-S"
            | "-W"
            | "-w"
    )
}

fn is_loopback_bind_address(bind_address: &str) -> bool {
    matches!(bind_address.trim(), "127.0.0.1" | "localhost" | "::1")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_split_l_flag_with_destination_hint() {
        let result = parse_ssh_command("ssh -L 3000:127.0.0.1:3000 admin@sanjose");

        assert_eq!(
            result.destination_hint,
            Some(SshDestinationHint {
                host: "sanjose".to_string(),
                user: Some("admin".to_string()),
                port: None,
            })
        );
        assert_eq!(
            result.provider_target_hint,
            Some(SshProviderTargetHint {
                target_address: "sanjose".to_string(),
                target_port: None,
                user: Some("admin".to_string()),
            })
        );
        assert_eq!(result.rule_drafts.len(), 1);
        assert_eq!(result.rule_drafts[0].local_port, 3000);
        assert_eq!(result.rule_drafts[0].remote_host, "127.0.0.1");
        assert_eq!(result.rule_drafts[0].remote_port, 3000);
        assert_eq!(result.diagnostics, Vec::<SshCommandParseDiagnostic>::new());
    }

    #[test]
    fn parses_compact_l_flag() {
        let result = parse_ssh_command("ssh -L3000:localhost:3000 -N root@devbox");

        assert_eq!(result.rule_drafts.len(), 1);
        assert_eq!(result.rule_drafts[0].local_port, 3000);
        assert_eq!(result.rule_drafts[0].remote_host, "localhost");
        assert_eq!(result.rule_drafts[0].remote_port, 3000);
        assert_eq!(
            result.destination_hint,
            Some(SshDestinationHint {
                host: "devbox".to_string(),
                user: Some("root".to_string()),
                port: None,
            })
        );
    }

    #[test]
    fn parses_bind_address_form() {
        let result = parse_ssh_command("ssh -L 127.0.0.1:3000:127.0.0.1:3000 admin@sanjose");

        assert_eq!(result.rule_drafts.len(), 1);
        assert_eq!(result.rule_drafts[0].local_port, 3000);
        assert_eq!(result.rule_drafts[0].remote_host, "127.0.0.1");
        assert_eq!(result.rule_drafts[0].remote_port, 3000);
        assert!(result.diagnostics.is_empty());
    }

    #[test]
    fn parses_multiple_local_forwards() {
        let result = parse_ssh_command(
            "ssh -L 3000:127.0.0.1:3000 -L5432:127.0.0.1:5432 -p 2222 root@devbox",
        );

        assert_eq!(result.rule_drafts.len(), 2);
        assert_eq!(result.rule_drafts[0].forward_index, 1);
        assert_eq!(result.rule_drafts[1].forward_index, 2);
        assert_eq!(result.rule_drafts[1].service_name, "Postgres 5432");
        assert_eq!(
            result.destination_hint,
            Some(SshDestinationHint {
                host: "devbox".to_string(),
                user: Some("root".to_string()),
                port: Some(2222),
            })
        );
    }

    #[test]
    fn parses_local_forward_from_o_config_option() {
        let result = parse_ssh_command(
            "ssh -o LocalForward=3000:127.0.0.1:3000 -o 'LocalForward 5432 localhost:5432' admin@sanjose",
        );

        assert_eq!(result.rule_drafts.len(), 2);
        assert_eq!(result.rule_drafts[0].local_port, 3000);
        assert_eq!(result.rule_drafts[0].remote_host, "127.0.0.1");
        assert_eq!(result.rule_drafts[1].local_port, 5432);
        assert_eq!(result.rule_drafts[1].remote_host, "localhost");
        assert!(result.diagnostics.is_empty());
    }

    #[test]
    fn parses_spaced_local_forward_with_bind_address() {
        let result = parse_ssh_command(
            "ssh -o 'LocalForward 127.0.0.1:3000 [127.0.0.1]:3000' admin@sanjose",
        );

        assert_eq!(result.rule_drafts.len(), 1);
        assert_eq!(result.rule_drafts[0].local_port, 3000);
        assert_eq!(result.rule_drafts[0].remote_host, "127.0.0.1");
        assert_eq!(result.rule_drafts[0].remote_port, 3000);
        assert!(result.diagnostics.is_empty());
    }

    #[test]
    fn reports_malformed_forward_without_panicking() {
        let result = parse_ssh_command("ssh -L 3000:127.0.0.1 admin@sanjose");

        assert!(result.rule_drafts.is_empty());
        assert_eq!(result.diagnostics.len(), 1);
        assert_eq!(
            result.diagnostics[0].severity,
            SshCommandParseDiagnosticSeverity::Error
        );
        assert_eq!(
            result.diagnostics[0].forward_spec.as_deref(),
            Some("3000:127.0.0.1")
        );
    }

    #[test]
    fn keeps_supported_local_forwards_when_unsupported_flags_exist() {
        let result =
            parse_ssh_command("ssh -R 9000:127.0.0.1:9000 -L 3000:127.0.0.1:3000 admin@sanjose");

        assert_eq!(result.rule_drafts.len(), 1);
        assert_eq!(result.diagnostics.len(), 1);
        assert_eq!(
            result.diagnostics[0].severity,
            SshCommandParseDiagnosticSeverity::Warning
        );
    }
}
