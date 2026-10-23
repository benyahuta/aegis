# ShieldCore test fixtures

Captured inputs for ShieldCoreTests (SPEC §3, §13.1). Copied into the test bundle as the
`Fixtures` folder; load with
`Bundle.module.url(forResource: "<name>", withExtension: "json", subdirectory: "Fixtures")`.

Expected files (added by the builders that own them): `sofa_ios_v2_2026-10-22.json`,
`sofa_macos_v2_2026-10-22.json`, `rollback_*.json`, `stale_*.json`, `scam_corpus.jsonl`,
`benign_corpus.jsonl`.

Version fixtures (VersionEvaluatorTests, FeedDecodeTests, FeedStoreTests):
- `sofa_ios_v2_2026-10-22.json`, `sofa_macos_v2_2026-10-22.json`: the live SOFA v2 feeds, captured once
  with curl on 2026-10-22 (served 2026-10-23 01:23 UTC, Last-Modified 2026-10-22 20:18 UTC). Unmodified.
- `rollback_ios_v2.json`, `rollback_macos_v2.json`: the captures with the newest release of every
  patched major removed (27.0.1, 26.7.1, 18.7.10 / 15.8.1). The raise-only rule must reject them.
- `stale_ios_v2_2026-09-21.json`, `stale_macos_v2_2026-09-21.json`: the captures with every release
  after 2026-09-21 removed (the feed as it looked a month earlier).
- `raise_ios_v2_2026-10-29.json`: the iOS capture plus hypothetical 27.0.2 / 26.7.2 releases that fix
  an exploited CVE (CVE-2026-99999, fictional). Must be accepted.

The derived files were made from the captures with jq (compact output).

`MacChecks/` (MacCheckParserTests): `tool_outputs.json` (captured + synthesized outputs of every
allowlisted tool), SoftwareUpdate preference plists, synthetic MobileMeAccounts plists (fake
values only), an XProtect Info.plist and a garbage file. Load with `subdirectory: "Fixtures/MacChecks"`.
