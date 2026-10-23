# Domain Docs

This repo uses a single-context layout:
root `GLOSSARY.md` and `docs/adr/`.

## Before exploring, read these

- `GLOSSARY.md`: the repo's domain vocabulary.
- Relevant ADRs in `docs/adr/`: decisions affecting the area of work.

If these files do not exist, proceed silently. Do not flag their
absence or suggest creating them upfront. The `/domain-modeling`
skill creates them lazily when terms or decisions are resolved.

## File structure

    /
    ├── GLOSSARY.md
    └── docs/adr/
        └── NNNN-decision-title.md

## Use the glossary's vocabulary

Use glossary terms when naming domain concepts in issue titles,
refactor proposals, hypotheses, tests, and other output.
Avoid synonyms the glossary explicitly rejects.

If a concept is missing, reconsider whether it belongs to the
project's vocabulary. If it is a real gap, note it for
`/domain-modeling`.

## Flag ADR conflicts

Explicitly surface proposals that contradict an existing ADR
rather than silently overriding it. Identify the ADR and explain
why the decision may be worth reopening.
