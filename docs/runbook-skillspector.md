# Runbook — SkillSpector (agent skill scanning)

Operational guide for the SkillSpector security scan of agent skills. Covers
what runs in CI, how to scan manually, how to read a verdict, and how to react
when the gate fails.

**Audience:** anyone adding or reviewing a `SKILL.md` in this repo.

---

## 1. What this does

[SkillSpector](https://github.com/NVIDIA/SkillSpector) is NVIDIA's static
security scanner for agent skills. It reads a skill (a `SKILL.md` plus any
bundled scripts) and returns a `risk_score` (0–100) with a severity band:

| Range  | Severity  |
|--------|-----------|
| 0–20   | LOW       |
| 21–50  | MEDIUM    |
| 51–80  | HIGH      |
| 81–100 | CRITICAL  |

Two entry points are installed:

- **CI** — `.github/workflows/scan-skills.yml`. Runs a **static** scan
  (`--no-llm`, deterministic) of each changed `SKILL.md` on push / PR, and on
  manual `workflow_dispatch`. **Fails the job at `risk_score >= 51`** (HIGH or
  CRITICAL). A SARIF report per skill is uploaded as the `skillspector-sarif`
  artifact.
- **Local** — `scripts/scan-skill.sh`. Scan one skill or batch-scan every
  `SKILL.md`, with a colour-coded verdict and Markdown + JSON reports.

This repo does not currently ship any `SKILL.md`. The scan is a guardrail for
when one is added (e.g. a Claude/agent skill committed under `**/skills/**`).

---

## 2. Requirements

SkillSpector requires **Python `>=3.12,<3.14`**. This is the scanner's runtime
only — it is independent of the application target (static HTML). CI provisions
3.12 for the scan job; locally, install SkillSpector in a 3.12/3.13 environment:

```bash
python3.12 -m venv .venv-skillspector
source .venv-skillspector/bin/activate
pip install "skillspector @ git+https://github.com/NVIDIA/SkillSpector.git"
```

To pin a specific release for reproducibility, append a ref (e.g.
`...SkillSpector.git@v2.1.3`) in both the install command and the CI workflow's
*Install SkillSpector* step.

---

## 3. Scanning manually

```bash
# Single skill (directory, SKILL.md path, git URL or zip):
scripts/scan-skill.sh path/to/skill/
scripts/scan-skill.sh path/to/skill/SKILL.md
scripts/scan-skill.sh https://github.com/user/some-skill

# Batch — every **/SKILL.md in the repo:
scripts/scan-skill.sh --batch

# Help:
scripts/scan-skill.sh --help
```

The script writes a `<slug>.md` and `<slug>.json` report per skill to
`./skillspector-reports/` and prints `risk_score`, severity and a `PASS`/`FAIL`
verdict. Exit code is `0` if every skill is below the threshold, `1` otherwise.

Configurable via environment variables:

| Variable           | Default                       | Purpose                                  |
|--------------------|-------------------------------|------------------------------------------|
| `SKILLS_ROOT`      | git repo root                 | Root searched in `--batch` mode.         |
| `REPORT_DIR`       | `./skillspector-reports`      | Where reports are written.               |
| `RISK_THRESHOLD`   | `51`                          | Score at/above which a skill is flagged. |
| `SKILLSPECTOR_BIN` | `skillspector`                | Scanner executable / path.               |
| `SCAN_EXTRA_ARGS`  | `--no-llm`                    | Extra args appended to every scan.       |

> Reports land in `./skillspector-reports/` — keep them out of commits
> (add to `.gitignore` if you run scans frequently).

---

## 4. When CI fails the gate

1. Open the failed **Scan Skills (SkillSpector)** run. The job log lists each
   skill with its `risk_score` and severity, and an `::error::` annotation on
   the offending `SKILL.md`.
2. Download the `skillspector-sarif` artifact for the per-issue detail, or
   reproduce locally: `scripts/scan-skill.sh path/to/skill/` and read the
   generated Markdown report.
3. Triage the findings:
   - **True positive** — fix the skill (remove the dangerous pattern: shell
     exec, network exfiltration, prompt-injection trigger, over-broad tool
     permissions, etc.), then re-run.
   - **False positive** — confirm with a second reviewer. SkillSpector findings
     are categorised (prompt injection, data exfiltration, dangerous code,
     etc.); document the justification in the PR before any override.
4. Do **not** lower `RISK_THRESHOLD` to get a skill through. The threshold is a
   security gate; changing it is a `SECURITY` decision that must be recorded in
   the PR and approved.

---

## 5. Maintenance

- **Action pins:** the workflow pins `actions/checkout@v6`,
  `actions/setup-python@v6`, `actions/cache@v4` and `actions/upload-artifact@v4`
  (tag pins, the org default — this is the repo's first workflow). Keep future
  workflows consistent with this convention.
- **SkillSpector version:** upgrades come from the upstream repo. Re-pin the
  install ref deliberately and note it in the PR.
- **Triggers:** the scan runs on changes to `**/SKILL.md` and `**/skills/**`.
  Extend these globs if skills land elsewhere.
