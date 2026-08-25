<!-- cdocs rules v0.1.0 hash=bc9d239ac160cd68be7b580434416cf51269095aebd6c4b893ad749628de4757 - regenerate with /cdocs:init (use version from plugin.json) -->
# CDocs Writing Conventions

All CDocs documents and communication should follow these conventions.

## BLUF (Bottom Line Up Front)

Lead documents and substantial communications with a BLUF summary.
A good BLUF results in no surprises when the full body of work is scrutinized.
It doesn't need every detail, just the essential takeaway.

Format: `> BLUF: ...` or `> BLUF(author/workstream): ...`

## Brevity and Communicative Efficiency

- Succinct, well-factored markdown docs are more effective than multi-section chat messages.
- Avoid repetition. Say it once, in the right place.
- Skip obvious explanations. Focus on decisions and their rationale.
- Explain WHY, not just WHAT.

## Sentence-per-Line Formatting

Use one sentence or thought per line in markdown source.
This makes diffs cleaner and editing easier.

## Callout Syntax

Use these callouts to leave context for future readers.
For example:
- `NOTE(opus/traige-subagent):` Context, caveats, or design commentary that doesn't belong in the main flow.
- `TODO(sonnet/big-refactor):` Known work remaining.
- `WARN(codex/cdocs/architecture-review):` Risks, gotchas, or things that could break.

The parenthetical is an attribution in the format `author/workstream`, which often maps to a feature branch name.
Add slashes for subprojects: `NOTE(mjr/cdocs/hooks)`.

## History-Agnostic Framing

- Frame documents in present tense as if the current state has always been the state.
- Don't reference "previously", "now updated", "added in this version", "old approach" in the test of the document.
- If a change is very very imporant, the _previous_ approach can be put in a qualifying `> NOTE` callout.
- Exception: Devlogs document chronological work. Proposals may reference prior approaches in NOTE() callouts.

## Commentary Decoupling

Separate commentary from technical content.
When implementation diverges from design, add a NOTE callout rather than rewriting the design doc:

```md
### Some Component
> NOTE(opus/my-feat): Implementation has special cases not in the original design.
> See `myEdgecaseReconciler` for details.

... Original clean design documentation ...
```

## Critical and Detached Analysis

Approach and reflect on work with a realist mindset.
- Be critical and detached in analysis.
- Surface deviations and complications as high-importance.
- Track both improvements AND what was not done or could be improved.
- Never gloss over a problem or present it as a success.

## Devlog Convention

Always create a devlog when starting substantive work.
The devlog is the single source of truth for a work session.
Update it as you go, not at the end.

## Punctuation: Prefer Colons Over Em-Dashes

Use colons, commas, or periods instead of em-dashes (` -- ` or `—`).
For brief qualifying statements, use ` - ` (spaced hyphen).
Em-dashes and semicolons should be used sparingly.

## Prefer Mermaid Over ASCII for Diagrams

Use Mermaid diagram syntax (` ```mermaid `) instead of ASCII art for flowcharts, sequence diagrams, state machines, and other visual representations.
Mermaid renders natively in GitHub and most markdown viewers, is easier to maintain, and diffs cleanly.

## Direct Links for External References

Use direct HTTP links for external references (GitHub issues, pull requests, commits, docs pages, npm packages, etc.).
Bare references like `CC #14200` or `issue 16538` are less useful than a navigable URL.

Format: `[#14200](https://github.com/anthropics/claude-code/issues/14200)` on first mention.
Subsequent shortform references in the same document are acceptable if the linked URL is unambiguous from nearby context.

This applies to all cdocs documents and to commit messages where practical.

## Avoid Emojis

Avoid excessive use of emojis and overly-effusive language in all documentation.
