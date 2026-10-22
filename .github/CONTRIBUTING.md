# Contributing to Save My Disk (save-my-disk)

Thank you for your interest in contributing to `save-my-disk`! This project provides universal, non-invasive storage audit and safe cleanup runbooks for AI Coding Agents and developers.

## Core Contributing Principles

1. **Zero-Invasive Guarantee**: Scan and audit operations MUST remain strictly read-only and never delete or lock user files during discovery.
2. **Targeted Confirmation (SSOT)**: All deletions must be explicitly gated through the structured manifest file (`.save-my-disk/cleanup_manifest.md`) or explicit candidate IDs (`SYS-xxx`, `RES-xxx`, `DEV-xxx`).
3. **Protected Red Line (Tier 4)**: Scripts must strictly refuse to delete operating system core files (`System32`, `WinSxS`), active user project source code, and personal chat history databases.
4. **Mock Sandbox Testing**: Any new scanner or cleaner script must be paired with automated unit tests in `tests/test_mock_sandbox.ps1` running against an isolated temporary directory in `$env:TEMP`.
5. **Character Encoding**: PowerShell `.ps1` files must be saved with UTF-8 with BOM (`\xef\xbb\xbf`) to ensure compatibility with Windows PowerShell 5.1 and PowerShell 7+.

## How to Submit Changes

1. Fork the repository and create your feature branch from `main`.
2. Implement your changes following the 4-Tier safety framework.
3. Run the automated test suite locally:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tests\test_mock_sandbox.ps1
   ```
4. Commit your changes following Conventional Commits format (`feat: ...`, `fix: ...`, `docs: ...`).
5. Open a Pull Request against `main`. All CI checks must pass before merging.
