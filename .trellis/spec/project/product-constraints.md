# Product Constraints

## Product Identity

RelayDock is a local-first desktop tunnel and port-forwarding workbench.

It is not:

- a browser
- an SSH terminal
- a session manager
- an operations backend
- a local project lifecycle manager
- a cloud account or sync product

## Current Pages

The first product structure is:

- `运行与恢复`
- `资源登记`
- `日志`
- `诊断`
- `偏好设置`

## Domain Model

Use the domain documents as source of truth before inventing new entities:

- `Host`
- `ProviderTarget`
- `Rule / Service`
- `Preset`
- `RuntimeInstance`
- `RecoveryItem`
- `LocalPortBinding`
- `LocalPortOverride`
- `PortUsage / PortClaim`
- `LocalAlias`

## Provider Scope

First provider scope:

- SSH through system OpenSSH
- Tailscale through local CLI/status integration when available

Do not implement an SSH terminal or remote shell UI as part of RelayDock.
