# 0010. Git LFS for `.miz` fixtures and audio

Status: Accepted · 2026-10-27

## Context

The `.miz` test fixtures, `.ogg`/`.wav`/`.mp3` audio and images are binary and sometimes large.
Keeping them in plain git bloats every clone.

## Decision

- `.gitattributes` routes `*.miz`, `*.wav`, `*.ogg`, `*.mp3` and `*.png` through Git LFS.
- CI checks out with `lfs: true`.
- Generated outputs (`campaigns/**/out/`, `dist/`) are git-ignored rather than stored in LFS.

## Consequences

- Contributors need to run `git lfs install`.
- GitHub's LFS bandwidth and storage quotas apply.
- The pre-commit `check-added-large-files` hook catches binaries that bypass LFS.
