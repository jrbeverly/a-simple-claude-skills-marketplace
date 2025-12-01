# a-simple-claude-skills-marketplace

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

A standard for packaging, indexing, and installing Claude Code skills.

```bash
bash scripts/installer/install.sh \
  --from tests/installer/fixtures/marketplace \
  example/hello-world
```

## Notes

- test case; asked Factory to create a cloud marketplace
- surprisingly solid overall
- bunch of extra/redundant shell scripts
- recurring tendency toward large Bash scripts; paragraphs upon paragraphs of shell
- points to need for platform-engineering / DevOps-style agent in the Factory ecosystem
- agent should help frame implementation choices; steer away from shell-script sprawl
- does not need to produce the ideal implementation first try
- system should still have pressure toward better baseline tools/patterns
- “understanding” not necessarily required; ecosystem-level tendency is enough
- current behaviour looks like a silent maintenance leak
- repeated Bash generation likely compounds over time; increasingly difficult to maintain/administer
