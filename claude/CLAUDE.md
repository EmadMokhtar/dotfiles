# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

# Conventional Commits
ALWAYS use [Conventional Commits](https://www.conventionalcommits.org/) — for every commit message **and** every pull request title. This is not optional and applies to all projects.

Format: `<type>[optional scope][!]: <description>`

- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `chore`, `style`, `revert`.
- Description: imperative mood, lowercase, no trailing period (`add X`, not `Added X.`).
- Breaking changes: append `!` after the type/scope (`feat!:`) and/or add a `BREAKING CHANGE:` footer.
- Body (optional): explain *why*, not what — the diff already shows what.

**PR titles matter as much as commits:** when a PR is squash-merged, its title becomes the commit message on the main branch, so a non-conventional PR title silently breaks the convention and any release automation that derives versions from commit history.

Never write a commit or PR title as a bare summary (`Update auth`, `Fix bug`, `M0+M1 engine`). Use `fix: reject expired tokens on refresh` instead.

# Language and clarity

English is not my first language. Apply these rules in every response:

1. **Expand every acronym the first time you use it in a conversation**, then use
   the short form afterwards.
   Example: "TTL (time to live — how long a cached value stays valid before it is
   discarded)".

2. **Define technical terms in place.** Put a short plain-English definition in
   parentheses right after the term. Do this even for terms that are common in the
   industry.

3. **Explain metaphors, idioms, and slang.** If a metaphor is the clearest way to
   say something, use it and then state the literal meaning.
   Example: "This is a footgun (a feature that is easy to use in a way that hurts
   you by accident)."
   Do not use sports, military, or US-culture references at all — I will not
   recognise them.

4. **Prefer plain verbs over industry slang**: "use" not "leverage", "start" not
   "spin up", "check" not "sanity-check", "reduce" not "trim the fat". If the slang
   term is worth knowing, use it and define it once.

5. **Short sentences.** One idea per sentence. Break long sentences into two.

6. **Do not simplify the engineering content.** I am an experienced backend
   engineer. I want the same technical depth and precision — only the *language*
   should be simpler, not the substance. Never omit a detail to keep things easy.

7. **Explain by default. Do not wait for me to ask.** My silence does not mean I
   understood the term.

8. For long or terminology-heavy answers, end with a short **Glossary** section
   listing the new terms with a one-line meaning each.

9. Before running a shell command, add one line saying what it does in plain English,
  including what each flag means.
  Example: `rsync -avz src/ dst/` — copies files, keeping permissions (-a), printing
  progress (-v), compressing during transfer (-z).

10. When an error message or stack trace appears, translate it into plain English
  before proposing a fix. Explain what the error *actually means*, not only how to
  make it go away.

11. Write code comments and commit messages in simple, direct English. No idioms.

12. When you introduce a library, tool, or pattern I have not used in this repository,
  give a one-sentence description of what it is and why it fits here.

13. Names of things (design patterns, algorithms, protocols) get a one-line
  explanation on first mention.

## Pull requests

Always assign me to any pull request you create or open.
- When creating a new PR: `gh pr create --assignee @EmadMokhtar ...`
- When opening or editing an existing PR that has no assignee yet: `gh pr edit <PR-number> --add-assignee @EmadMokhtar`
