# CDocs Writing Conventions

When authoring or editing documents in the `cdocs/` directory, follow these conventions:

- **Frontmatter is mandatory.** Every document must begin with YAML frontmatter (`---` delimiters) containing at minimum: `title`, `date`, `status`.
- **Use active voice and imperative mood** in headings and action items.
- **BLUF (Bottom Line Up Front)** — lead with the conclusion or recommendation, then provide supporting detail.
- **Keep paragraphs short** — 3-5 sentences max. Use bullet lists for enumerations.
- **Code blocks must specify a language** for syntax highlighting.
- **Status values:** `draft`, `in_review`, `accepted`, `rejected`, `implemented`, `archived`, `request_for_proposal`.
- **Date format:** ISO 8601 (`YYYY-MM-DD`) in frontmatter and filenames.
- **Filenames:** lowercase, hyphen-separated, prefixed with date: `YYYY-MM-DD-topic.md`.
