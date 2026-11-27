# Releasing the IP (tapeout-readiness T7) — kit template

> Copy to `pkg/RELEASE.md` and adapt the bundle table to `pkg/release.json`.

How a versioned release of the AXI4 → 2× APB4 bridge is cut. This block is the program's
flow pathfinder, so this procedure and `scripts/make_release.py` are the template the
sibling IPs copy.

## Versioning

- **IP release:** semantic version `vMAJOR.MINOR.PATCH` (git tag `v1.0.0`, …).
  - MAJOR: an interface or behaviour change, which always comes with a new design-contract
    version and tag.
  - MINOR: compatible additions (new collateral, new configurations).
  - PATCH: fixes that keep the contract.
- **Design contract:** its own tag (`contract-v1.0`). **No release before T0:** the tag-run
  pre-flight refuses to publish unless `contract_tag` exists and `contract_doc` is present and
  shipped. PR dry-runs (`make release-check`) still work before T0. Every IP release records the contract
  it implements in `MANIFEST.json`. `v1.0.0` implements contract `1.0`.

## What a release contains

`make release VERSION=x.y.z` builds `dist/<ip-name>-x.y.z.tar.gz` (plus a `.sha256`).
The bundle holds:

| Kind | Files |
|---|---|
| `rtl` | `src/<top>.v` (per `pkg/release.json`) |
| `rtl-example` | example/demo RTL outside sign-off, if any |
| `ip-xact` | `pkg/ip-xact/*.xml` (IEEE 1685-2014, XSD-validated) |
| `contract` | `doc/design_contract.md` |
| `signoff` | `syn/SIGNOFF.md` |
| `constraints`, `power-intent`, `plan` | SDC, OpenSTA script, UPF, LP/DFT/T6 plans |
| `doc`, `license` | integration guide, package README, this file, top-level README, LICENSE |
| `gate-report` | every `syn/**/reports/*` present at build time (synth, scan, GLS, PPA) |
| — | `MANIFEST.json` |

`MANIFEST.json` records:
- the SHA-256 and size of every file;
- the source commit, and whether the tree was dirty;
- the contract tag and version;
- the T0–T7 gate status, parsed from `syn/SIGNOFF.md`;
- the tool versions used.

The tarball is deterministic: sorted entries, and every timestamp set to the commit time.
Rebuilding the same commit with the same reports gives the same bytes.

## Procedure

Releases are built and published **by CI** (`.github/workflows/release.yml`), not on a
workstation:

1. `main` is green in CI (CI, UVM on Verilator, Docker plumbing), and
   `pkg/RELEASE_NOTES.md` starts with `# <ip-name> vX.Y.Z` for the version you are
   releasing.
2. Tag the main commit and push the tag (owner):
   ```
   git tag -a v1.0.0 -m "IP release 1.0.0 (contract 1.0)"
   git push https://github.com/markrthomas/<repo>.git v1.0.0
   ```
3. The **Release** workflow then runs on a runner:
   - **Pre-flight:** checks that the tag is on `main`, that every CI check on that commit
     succeeded, that the release notes heading matches, and that no release with that name
     exists yet.
   - **Tool check:** requires every gate tool. A missing tool is an error, never a skip.
   - **Gates:** re-runs `make test-all formal syn dft lp gls ppa pkg pkg-xsd`.
   - **Build and verify:** `make release VERSION=X.Y.Z`, then `make release-verify` and
     `sha256sum -c`.
   - **Publish:** the GitHub release `vX.Y.Z`, with the bundle and its `.sha256` attached
     and `pkg/RELEASE_NOTES.md` as the notes.

   If any step fails, nothing is published. Fix the problem, delete the tag
   (`git push --delete origin v1.0.0`), and tag again.
4. Sign the gates in `syn/SIGNOFF.md` (artifact path, pass date, reviewer), citing the
   published release bundle as the archived artifact.

A pull request that changes the release flow runs the same workflow as a **dry run**
(version `0.0.0-dryrun`: every gate, build and verify, nothing published). To try a build
locally: `make release VERSION=x.y.z` and `make release-verify VERSION=x.y.z`. CI also runs
`make release-check` (two byte-identical builds plus verify) on every push.

## Scope

This is the OSS, no-PDK release. A bundle contains the generated gate reports so that each
sign-off row has an archived artifact. Items that need a PDK or a licensed tool are tagged
in `syn/SIGNOFF.md`; they are not part of this release.
