# Contributing

Thanks for your interest in improving the Azure IaaS Training Workshop. This is
community sample content — contributions are welcome, but it is provided without
any guarantee of support or maintenance.

## Ground rules

- **Never commit secrets or environment-specific values.** Real subscription IDs,
  tenant IDs, tenant domains, access codes, resource names, and customer names do
  not belong in the repo. Use the placeholder tokens documented in the
  [README](README.md) (e.g. `<SUBSCRIPTION_ID>`, `<TENANT_DOMAIN>`,
  `<SWA_HOSTNAME>`).
- Keep the app **generic and reusable**. Customer-specific details belong only in
  a local, untracked `src/config.js` edit and in your own Function App settings.
- `api/local.settings.json`, `.env`, and the `.azure/` folder are gitignored —
  keep it that way.

## Making changes

1. Fork and create a feature branch.
2. Make your change. For frontend or API edits, test locally
   (`func start` in `api/`, and serve `src/` with the SWA CLI or any static
   server).
3. Run a quick self-check before committing — confirm no secrets or
   environment-specific identifiers were introduced:

   ```powershell
   git grep -nEi "onmicrosoft\.com|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}" -- ':!*.md'
   ```

4. Open a pull request with a clear description of the change.

## Reporting issues

Use GitHub issues for bugs and suggestions. For anything security-sensitive, see
[SECURITY.md](SECURITY.md).
