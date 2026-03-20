# Contributing

## Development Environment

- Windows PowerShell 5.1 or PowerShell 7 on Windows
- A locally installed `openclaw` CLI for runtime validation
- Git

## Recommended Setup

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -RequiredVersion 5.5.0
```

## Local Checks

```powershell
Invoke-Pester -Path .\tests
powershell -ExecutionPolicy Bypass -File .\build-release.ps1 -Version dev
```

## Contribution Guidelines

- Keep the repository focused on the Windows service wrapper layer.
- Do not vendor upstream OpenClaw source code into this repository.
- Do not commit generated WinSW binaries, logs, or local machine secrets.
- Keep public documentation in English and Chinese in sync.
- Prefer targeted process or service control over broad machine-wide cleanup logic.

## Pull Requests

- Explain user-visible behavior changes.
- Call out config or compatibility changes explicitly.
- Include or update tests for configuration, template, or lifecycle behavior.
