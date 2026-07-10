---
name: security-review
description: Guidance on performing security reviews for fsdk-containers. Use when reviewing pull requests, auditing workflows, or using the /security-review command.
metadata:
  type: runbook
---

# Security-Focused Code Review

Use this skill when auditing the codebase, workflows, or BuildStream elements for security vulnerabilities, or when instructed to perform a security-focused review via the /security-review command.

## When to Use

- When analyzing pull requests for high-confidence security vulnerabilities.
- When auditing GitHub Actions workflows for potential injection, unsafe token usages, or unpinned dependencies.
- When evaluating BuildStream 2 element configurations for build-time safety (e.g., untrusted script executions, permission issues, or leaked build secrets).

## When NOT to Use

- When performing standard linting or structural syntax checks (e.g., just validate).
- When doing basic codebase feature work without security-implications.

## Core Process

1. Check GitHub Workflows:
   - Scan all .github/workflows/*.yml for:
     - Hardcoded API tokens or secrets.
     - Usage of mutable git tags for Actions instead of 40-character commit SHAs.
     - Unsafe script executions using dynamic inputs (e.g., ${{ github.event.issue.title }}).
     - Elevated permissions (e.g., wildcard write scopes) where minimal permissions suffice.
2. Audit BuildStream Elements (elements/**/*.bst):
   - Verify that builds do not execute commands requiring host root privileges.
   - Check that no sensitive credentials, keys, or personal access tokens are included in the recipe sources.
   - Ensure that manual C/C++ elements (like qemu-img) inject OpenSSF-aligned compiler hardening flags with a fallback root-level default `hardening-flags: ""` definition.
   - Ensure that strip-binaries is correctly configured where necessary (e.g., manual Go/Rust/static binary elements) to prevent binary corruption or builder issues.
3. Execute Static Scans:
   - Run local security checks, container scans, or helper tools to verify the integrity of built OCI images.
4. Formulate and Present Findings:
   - Report findings clearly in a structured summary table categorised by severity (CRITICAL, HIGH, MEDIUM, LOW).
   - Use plain text or basic Markdown structure for all headings and lists, adhering to user formatting preferences.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The workspace is clean, so no security review is needed." | Even if working tree is clean, workflow configuration or BuildStream configuration changes should still be checked for existing posture and long-term risk. |
| "It's safe to use a mutable tag since it is an official action." | Compromised tag updates are a common entrypoint for supply-chain attacks. Pinning to a specific 40-character SHA is mandatory. |

## Red Flags

- Hardcoded secrets or tokens in scripts or workflows.
- Workflow actions using mutable tags (e.g., @v2 or @main) instead of full commit SHAs.
- Insecure dynamic workflow inputs used directly in shell commands.
- Elevating workflow permissions (like contents: write) globally instead of limiting them to specific jobs.

## Verification

- [ ] All workflows use strict 40-character commit SHAs for actions.
- [ ] No hardcoded secrets or API tokens exist in any file.
- [ ] Workflow steps with custom branch checkout specify canonical refs securely.
- [ ] Manual C/C++ elements (e.g. qemu-img.bst) inject OpenSSF-aligned compiler hardening flags with a fallback root-level default `hardening-flags: ""` definition.
- [ ] Findings summary table matches user constraints and is free of unwanted decorative elements.
