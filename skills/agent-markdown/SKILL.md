---
name: agent-markdown
description: Writes and edits the instruction files agents read, skills, rules, CLAUDE.md, agents and commands, and is the baseline for how a skill is built. Use whenever anything inside a .claude folder or a CLAUDE.md is created, changed, moved or reworded, when a skill is created or improved, when the user gives a ruling or correction that must hold in later sessions, and when a skill or rule needs its scope stated.
argument-hint: "[create|improve|rule|scope|align] <file or skill>"
allowed-tools: Read, Grep, Glob, Edit, Write
---

# agent-markdown

## Overview

An instruction file is loaded into context every time it applies and steers every session that reads it. Each line competes for tokens with the work itself, and a line written for one occasion misleads every later one. Instruction files are written as reusable rules and procedures: general, lean, in one voice per file, each concern in exactly one place.

## Layout

1. Reach decides the layer: `~/.claude/` for what holds in every repo, `<workspace>/.claude/` for one workspace, `<repo>/.claude/` for one repo. A lower layer points to the higher one and never restates it.
2. A skill is a folder named for it holding `SKILL.md`. Deterministic work is a bash script in its own `scripts/` folder, run as `bash <skill path>/scripts/<name>.sh`; detail that would push `SKILL.md` past a few hundred lines goes in `references/`. Neither folder exists until the skill needs it.
3. A rule file holds one concern, named for it, with a `paths:` scope unless every session needs it, and is indexed in its repo's `CLAUDE.md`.
4. A `CLAUDE.md` stays under 200 lines: what the repo is, its commands, its own conventions, then the index of its rules and skills.
5. A new file takes the frontmatter, headers and numbering of its nearest sibling in the same layer.

## Writing a skill

1. `name` equals the folder name, lowercase with hyphens, at most 64 characters.
2. `description` is the only part loaded before the skill is chosen, so it decides whether the skill is used at all. In the third person it says what the skill does, then `Use when` with the concrete situations, file types and words a user would type. It holds no process steps: a session that reads a summary of the steps follows the summary and skips the body. Under 1024 characters, ideally under 500.
3. `allowed-tools` lists what the skill runs; `argument-hint` names its arguments when it takes any.
4. The body is an overview of what the skill is for and why, when to use it and when not, the process as numbered steps, and how to verify the result. Under 500 lines, aiming far lower. A reference file is linked from `SKILL.md` directly, never through another reference, with a line on when to read it.
5. Match freedom to fragility. A step that must run exactly is a script with fixed flags. A judgment is a principle with its reason, trusting the reader to apply it.
6. One term per concept throughout, no time-sensitive content, no explanation of what a capable model already knows.

## Writing a rule

1. Generalize. A correction arrives as one incident. State the principle it is an instance of, wide enough to cover the family of cases the user means and no wider. The rule carries no quote, date, session, ticket or single instance, and reads correctly to someone who never saw the incident.
2. Match the form to the failure:
   1. The session knows the rule and breaks it under pressure: a prohibition with its reason.
   2. The output has the wrong shape: a positive recipe that states what the output is, its parts in order. A list of things not to do invites negotiation.
   3. A required element goes missing: a slot in the template the session fills in.
   4. The behaviour depends on a condition: a conditional keyed to something observable.
3. Explain why. A rule with its reason generalizes to cases nobody listed; a bare MUST does not. Capitals are for the few lines where a mistake is costly.
4. No nuance clauses and no exemption clauses. "Unless it matters" reopens the rule. An exception is its own conditional, or the structure is changed so the rule cannot reach it.
5. One home. The rule lives in the file and section that own the concern, as one numbered point worded like its neighbours. A point that already touches the case is rewritten in place, and two points that disagree never stand side by side. Everything else points to it.
6. A rule a script can enforce is a script, and the prose keeps only the judgment.

## Modes

1. **create**: a new skill. Settle what it enables, when it triggers and what it returns, place it in its layer, then write it as Writing a skill says.
2. **improve**: an existing skill changed in place, never a second one beside it. Remove what does not change behaviour, sharpen the steps, and tune the description so the skill triggers when it should and stays quiet when it should not.
3. **rule**: a ruling or correction written into the rule or skill that owns the concern, as Writing a rule says.
4. **scope**: a skill or rule that was applied where it should not be. Its trigger and its limit are stated as conditions on what is observable.
5. **align**: a file brought to the shape and voice of its layer, restated rules turned into pointers, contradictions resolved in favour of the owning file.

## Verification

1. Read every changed section again as a session that never saw why it changed. It reads as if it had always been there, in the same voice as the lines around it.
2. No line names one incident, quotes the user, or carries a date or version.
3. The concern lives in one place, and no two points disagree.
4. A skill's description says what and when with no steps, the body is under 500 lines, and every file it references exists and is linked from `SKILL.md`.
