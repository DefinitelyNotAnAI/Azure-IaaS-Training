# Security

This repository is community sample content provided "as is" with no warranty or
official support (see the [LICENSE](LICENSE)).

## Reporting a vulnerability

If you find a security issue in this sample, please open a GitHub issue with
enough detail to reproduce it — **but do not include any secrets, credentials, or
customer-identifying information** in the report.

If the issue involves a leaked secret or credential, do not post it. Instead,
note that a secret was exposed and where, and rotate/revoke the affected
credential immediately in your own environment.

## Hardening guidance for operators

If you deploy this workshop:

- Keep `api/local.settings.json`, `.env`, and the `.azure/` folder out of source
  control (they are gitignored by default).
- Store `ADMIN_ACCESS_CODE` and `SESSION_CODE` as Function App settings, not in
  committed files. Rotate `SESSION_CODE` per delivery.
- Use the included least-privilege RBAC model (per-participant Contributor on
  their own resource group; Reader on the hub; a narrow custom role for peering).
- Temporary Access Passes are short-lived and rotatable — rotate them close to
  workshop start and revoke participant accounts during teardown.
- Enable **GitHub secret scanning** and **push protection** on your fork.
