---
name: slyed-identify
description: Reads a project's Claude session logs for work that was repeated by hand and could have been code, then writes the scripts, skills and agent changes that remove it, aiming at the fewest tokens per task. Use when the user asks what keeps being repeated, to optimise a project's agents, skills or token use, to turn recurring commands into scripts, or to fold the questions the user has answered and the corrections they gave into the project's instructions.
argument-hint: "[days]"
allowed-tools: Bash(bash */skills/slyed-identify/scripts/*), Bash(git *), Read, Grep, Glob, Edit, Write, Skill
---

# slyed-identify

Every session pays in tokens for what it works out again. The logs show what was worked out more than once: the same command shape, the same file read in full, the same search, the same question. Each of those is a script, a pointer or a rule that the next session reads in one line. This skill writes inside the project's `.claude` folder on its own standing permission, and nothing outside it.

## Process

1. `bash <this skill's base directory>/scripts/repeats.sh [days]` prints, for this repo's logs of the last 14 days or the days given: calls per tool, shell command shapes run three times or more, files read or edited four times or more, searches repeated, skills invoked, what the user said as a correction, and what the user answered to a numbered question.
2. A command shape that recurs is a script under the `scripts/` of the skill that owns the concern, with fixed flags and one line of output per step. A chain of several commands always run together is one script.
3. A file read in full again and again is too large or too central to be read that way: the skill that owns it gets a script that prints the part asked for, or a reference page with the map of the file.
4. A search that recurs is a line in the owning skill saying where the thing lives.
5. An answered question is a ruling. It is written into the task it belongs to with the `tasks` skill's `answer.sh`, and into the rule or skill that owns the concern when it holds beyond that task.
6. A correction is written as the `agent-markdown` skill's rule mode says: generalised, in the file that owns the concern, never as the incident.
7. An agent that reads what it does not use, or runs on a larger model or effort than its work needs, is trimmed: fewer tools, the least model that does the job, a brief that names files and lines.
8. Nothing is written for a shape seen once, and nothing that restates a rule a higher layer already holds.

## Verification

Each new script runs clean on the repo, each changed instruction file passes the `agent-markdown` verification, and a second run of `repeats.sh` after the next sessions shows the shape gone.
