# The Three-Role Pattern: Building Software with Claude Code Under Conversational Direction

## What this document is

A description of the working pattern that emerged across building a multi-tenant SaaS food traceability system (Tracelot) over ~19 goals of work. The pattern involves three distinct roles working together: a human developer providing direction and judgment, a conversational Claude instance providing thinking partnership and review, and Claude Code (the agentic coding tool) doing the implementation.

This isn't a methodology invented from first principles. It emerged from working through real problems and noticing what consistently produced good outcomes versus what consistently produced regret. The intent of writing it down is so other projects can consider whether the pattern fits, adapt it, or push back on where it falls short.

## The three roles

### Role 1: The developer (you)

The developer is the project owner. They hold:

- **Domain knowledge** that neither AI has — what tenants actually need, what regulations actually require, what the product should feel like to use
- **Architectural authority** — the final word on technical decisions
- **Quality bar** — the willingness to stop and investigate rather than ship on faith
- **Resource budget** — time, energy, attention; the willingness to spend it on discipline rather than speed

The developer doesn't write production code in this pattern. They write specs (often with help), they review what gets implemented, they make architectural decisions, they catch issues, and they push back when something looks off.

What the developer is doing isn't passive review. It's active direction — choosing which goals to tackle, deciding when to fix versus defer, holding the line on quality when shortcuts beckon, and providing the judgment that neither AI can supply.

### Role 2: Conversational Claude (the thinking partner)

A Claude instance accessed through a conversation interface (claude.ai or similar). Not connected to the codebase; works from descriptions, summaries, and reasoning.

Conversational Claude's job:

- **Drafting specs** before implementation begins (goal specifications, architectural decisions, scope boundaries)
- **Reviewing completion summaries** from Claude Code with skepticism
- **Surfacing concerns** about what could go wrong
- **Asking clarifying questions** about decisions before they're locked in
- **Holding methodology** — remembering the patterns that worked and the patterns that didn't
- **Pushing back** when the developer or Claude Code suggests shortcuts that aren't worth the risk

Conversational Claude is not a rubber stamp. The pattern only works if conversational Claude is willing to disagree with the developer, push back on Claude Code's claims, and surface concerns that might be unwelcome.

The key property: conversational Claude isn't doing the work. This separation means conversational Claude has the cognitive bandwidth for review, critique, and methodological consistency. An AI doing implementation work has its attention on the implementation; an AI reviewing implementation work has its attention on the review.

### Role 3: Claude Code (the implementer)

Claude Code is Anthropic's agentic coding tool. It has direct access to the codebase, can run tests, execute commands, edit files, make commits.

Claude Code's job:

- **Implementing** what specifications describe
- **Asking clarifying questions** when specs are ambiguous
- **Running tests** to verify the work
- **Reporting honestly** about what it built, what it found, what it deferred
- **Investigating** when something looks wrong

Claude Code is doing the actual engineering work. It's the one that knows what the codebase actually contains, what the tests actually verify, what the database actually has in it. Its honesty about state is what makes the pattern function.

## How the three roles interact

The basic loop for any meaningful unit of work (a "goal" in our terminology):

```
1. Developer + conversational Claude draft a specification
   - Discuss the architectural decisions
   - Settle the scope and deferrals
   - Identify expected ADR candidates
   - Write the specification document
   - Draft a compressed kickoff prompt for Claude Code

2. Developer hands the kickoff prompt to Claude Code
   - Claude Code reads the full spec
   - Claude Code asks clarifying questions about ambiguities
   - Developer answers (sometimes consulting conversational Claude)
   - Claude Code implements

3. Claude Code reports completion to the developer
   - What was built
   - Test counts and results
   - ADRs proposed
   - Issues found during implementation
   - Items deferred

4. Developer shares the completion summary with conversational Claude
   - Conversational Claude reviews skeptically
   - Surfaces concerns about what's claimed versus verified
   - Identifies items requiring more investigation
   - Proposes follow-up actions or accepts the work

5. Developer directs Claude Code on next steps
   - Address surfaced concerns
   - Land the commits in the agreed structure
   - Push to origin when verified clean

6. Walkthrough verification
   - Claude Code runs Playwright-driven walkthrough
   - Reports findings categorized by severity
   - Developer triages with conversational Claude

7. Address findings, commit, push
   - Small housekeeping commits if needed
   - Always under explicit developer approval

8. Stop at clean state before next goal
```

The roles never collapse. Conversational Claude never directly drives Claude Code; the developer is always in the middle. This sounds inefficient but turns out to be load-bearing — the developer's judgment is what catches drift between what conversational Claude expects and what Claude Code actually does.

## What makes this pattern actually work

The mechanical structure above is most of what people would write down. But the structure alone doesn't produce good outcomes. Several non-obvious properties do the real work.

### 1. Specifications are written before implementation

Each goal gets a detailed specification document — typically 200-500 lines covering architecture, scope, out-of-scope items, ADR candidates, commit strategy, testing strategy, completion criteria. These documents take real effort to write (conversational Claude drafts them; developer reviews and refines).

Why this matters: specifications surface architectural decisions before implementation hides them in code. Writing "should packaging materials be tracked as full lots or consumable counts?" before Claude Code starts implementing forces an explicit decision. Without the specification, that decision gets made implicitly during implementation, often suboptimally, often without anyone realizing a decision was made.

The cost: each spec is 30-60 minutes of focused thinking. For projects with simple, well-understood requirements, this overhead may not be worth it. For projects with architectural complexity (multi-tenant, regulatory, integration-heavy), it consistently pays off.

### 2. Claude Code asks clarifying questions before implementing

The kickoff prompts explicitly invite clarifying questions. Claude Code uses this invitation — typically 3-5 questions about ambiguities in the spec.

Why this matters: it surfaces the gaps in the specification before implementation locks them in. When Claude Code asks "should the Customer entity have full master data scope or lightweight free-text on shipments?", that's a real architectural decision being elevated to conscious consideration rather than buried in implementation choices.

The questions also reveal what Claude Code is thinking about — its mental model of the work. Misalignments between Claude Code's mental model and the developer's get caught here rather than after 4 hours of implementation.

### 3. Honest reporting from Claude Code, including failures

Claude Code reports what actually happened, including:

- Pre-existing failing tests it didn't introduce
- Decisions it made that diverged from the spec
- Items it deferred or skipped
- Things it couldn't verify

This honesty is non-trivial. There's an implicit pressure for any AI tool to make work look complete and clean. Claude Code in this pattern is configured (via CLAUDE.md and prompt structure) to surface gaps rather than paper over them.

Concrete example from the project: Claude Code reported "verified failing on clean main" for a test that was load-bearing for an architectural protection. That report led to forensic investigation, which found a real defect that had silently shipped weeks earlier. Without the honest reporting, the defect would have continued to ship.

### 4. Conversational Claude pushes back

This is the property that's hardest to describe and hardest to maintain. Conversational Claude must be willing to:

- Disagree with the developer's instinct
- Tell the developer to investigate rather than ship
- Question Claude Code's reported "PASS" status
- Point out when an "easy" path is the wrong path
- Surface concerns that may be unwelcome

The pattern fails if conversational Claude becomes agreeable. Most of the value-add of having a conversational thinking partner comes from disagreement and friction, not from confirmation.

Conversely, the pattern fails if conversational Claude becomes obstructive. The friction has to be in service of better outcomes, not in service of being seen as thorough. A reviewer who blocks on every minor concern is as broken as one who waves everything through.

The middle path: push back where the consequences matter, accept where they don't. This requires judgment that conversational Claude has to develop over time as it learns the project's actual risk profile.

### 5. Verification has teeth

Tests run. Test counts get reported with breakdown. Walkthroughs happen. Reviewer subagents execute (not just structurally verify). When something fails, it gets investigated, not waved past.

The pattern includes specific anti-patterns to catch:

- "Verified failing on clean main" → forensic investigation, not acceptance
- "Reviewer marked PASS" → check what the reviewer actually executed
- "Tests exist for this scenario" → did they actually run? Did they pass?
- "Pre-existing flake" → when did it start failing? Why?

These aren't paranoid checks. They emerged from cases where waving past these signals would have shipped real defects. Each one is empirically justified by an incident.

### 6. Methodology improves from incidents

When something goes wrong, the response isn't just "fix it." It's:

1. Fix the immediate issue
2. Understand why it happened
3. Update the methodology to prevent recurrence
4. Document the update with reference to the empirical case

This makes the pattern self-improving. Each goal teaches something. The CLAUDE.md document grows with hard-won wisdom. The reviewer prompts get more rigorous. The verification standards get sharper.

Concrete examples:

- A reviewer marked an architectural test as passing while it was actually failing. Result: CLAUDE.md §12 amendment requiring reviewers to execute load-bearing tests, not just verify structure.
- A theme-capture mechanism kept getting refined while the underlying bug (a missing component mount) went undiagnosed. Result: CLAUDE.md §13 refinement with SHA-divergence as the cleaner binary signal.
- Pre-existing failing tests were initially accepted as "not regressions." Result: practice changed to forensic investigation; multiple defects found that would have shipped silently.

### 7. The pattern stops at clean states

Sessions don't end with work in flight. The pattern enforces:

- Commits land before pushing
- Push happens before stopping
- Next session anchors on the previous session's clean state

This means anyone (including the developer's future self) can pick up the project at any time without untangling half-done work. Mental load between sessions stays bounded.

The cost: sometimes a session has to extend by 30 minutes to reach a clean stopping point. The benefit: no session opens with the question "where was I?"

## The cultural properties that enable the structural ones

The structural pieces above are necessary but not sufficient. Several cultural properties have to be present:

### Discomfort with shortcuts that feel reasonable

Most defects in software get shipped because someone said "this is probably fine" about something that wasn't. The pattern requires resistance to "probably fine."

Specifically: the pattern requires the developer to accept that conversational Claude will sometimes push back on shortcuts the developer wants to take. And it requires conversational Claude to actually do that pushback, even when the developer signals they want to move fast.

Without this discomfort, the pattern degrades into a confirmation-bias generator with extra steps.

### Willingness to do forensic work

When something looks wrong, the response is investigation, not rationalization. This takes time — often 30-60 minutes per investigation. Across a project, this adds up.

The investigation pays off because what looks wrong is sometimes wrong. A test failing for "no obvious reason" sometimes reveals a real defect that's been silently shipping. A reviewer report showing "all PASS" sometimes reveals a methodology gap. A walkthrough finding something visual sometimes reveals an integration issue.

Without willingness to do this work, real defects accumulate as "known issues" that nobody quite understands.

### Honest tracking of deferred work

Things get deferred. That's fine. But the deferrals get tracked explicitly:

- Polish backlog entries with specific items
- Out-of-scope sections in specifications
- "Deferred to operator pilot" markers
- "Phase 2" mentions with reasoning

This means the project never accumulates implicit debt. If something was deferred, there's a record of what and why. Future-you (or future-team-members) can find the deferred items rather than rediscovering them as surprises during a pilot.

### Trust as the medium

The pattern only works if the three roles trust each other:

- Developer trusts conversational Claude to surface real concerns, not just procedural friction
- Developer trusts Claude Code to report honestly, including failures
- Conversational Claude trusts the developer's judgment on domain priorities
- Claude Code trusts the developer's direction on scope and approach

Trust gets built through repeated cycles where the trusted party demonstrates they're earning it. It gets damaged by:

- Conversational Claude waving things through to be agreeable
- Claude Code reporting "complete" when work is incomplete
- Developer overriding concerns without engaging with them
- Any party pretending to know things they don't

When trust gets damaged, the pattern's quality degrades. Repair requires explicit re-establishment.

## What this pattern is good at

Specific kinds of projects where this pattern has shown clear value:

### Architecturally complex projects

Multi-tenant systems, regulatory-bound systems, systems with significant cross-cutting concerns (audit, security, traceability). These benefit from the specification discipline because the architectural decisions matter and can't be deferred to implementation.

### Long-running projects with high quality requirements

Projects that will run for months or years, where defects shipped today become problems six months from now. The discipline overhead amortizes well over long timelines. The forensic investigation pays off when caught defects would have been expensive to find later.

### Single-developer projects that need architectural review

A solo developer doesn't have a senior engineer to push back on their decisions. Conversational Claude fills that gap — not perfectly, but meaningfully. The pattern provides the architectural friction that solo work usually lacks.

### Projects where the developer wants to stay in the architecture

If the developer wants to keep making architectural decisions and shaping the system, this pattern keeps them in that seat. Claude Code does implementation; the developer retains authority. For developers who enjoy architectural thinking but find pure implementation tedious, the division of labor is satisfying.

## What this pattern is bad at

Equally specific kinds of projects where this pattern is wrong:

### Prototypes and exploration

When the goal is "see if this idea works," the specification discipline is overhead. Throwaway code shouldn't have detailed specs. Use Claude Code directly without the surrounding pattern.

### Tight deadlines

The pattern is slower than just letting Claude Code build something. If you have a hard deadline tomorrow, you don't have time for forensic investigation of pre-existing flakes. Use a faster pattern that day; come back to discipline when you can afford it.

### Projects where the developer doesn't want architectural involvement

If the developer just wants something built and doesn't want to make decisions, the pattern wastes everyone's time. The pattern requires an engaged developer with architectural judgment. A disengaged developer using this pattern produces worse outcomes than just letting Claude Code work autonomously.

### Projects with frequent context switching

If the developer is juggling multiple unrelated projects with rapid context switches, the pattern's "stop at clean state" discipline becomes burdensome. The pattern assumes sustained attention on one project over weeks or months.

### Highly experimental architecture

If the architecture is genuinely uncertain and being discovered through implementation, the spec-first discipline can prematurely lock in decisions. Use a more exploratory pattern; come back to spec discipline once architecture stabilizes.

## What this pattern costs

Honest accounting of the overhead:

### Time

Per goal of work, the pattern adds:

- Spec drafting: 30-60 minutes of conversational Claude time, 15-30 minutes of developer review
- Clarifying question exchange: 10-20 minutes
- Reviewer subagent execution: 5-15 minutes
- Completion summary review with conversational Claude: 15-30 minutes
- Walkthrough verification: 30-90 minutes
- Forensic investigation when things look off: 30-90 minutes per incident
- Methodology updates: 15-30 minutes per incident

Across a goal: 2-4 hours of overhead beyond the implementation time itself.

For a project running through 20+ goals, that's 40-80 hours of overhead. Real time.

### Cognitive load

The pattern requires sustained attention from the developer. They can't context-switch in the middle of a goal without losing thread. Session boundaries matter.

Conversational Claude needs context — typically through long threads where it accumulates project understanding. Starting fresh sessions loses some of that, requiring re-establishment.

Claude Code needs the spec to be detailed enough to implement against. Vague specs produce vague implementations or many clarifying-question rounds.

### Money

For projects using paid Claude tiers (Claude Code subscriptions, conversational Claude usage), the pattern costs more than minimal usage. Long threads, multiple cycles per goal, forensic investigations all consume tokens.

The pattern is not free. For projects where money matters more than quality, find a cheaper approach.

## Common failure modes

Where the pattern goes wrong in practice:

### Conversational Claude becomes agreeable

If conversational Claude starts agreeing with whatever the developer or Claude Code says, the pattern's review function dies. Symptoms: lots of "approved" with little pushback; "looks good" without substance; concerns that are mentioned then immediately walked back.

Repair: the developer needs to actively invite pushback. "Push back if you think I'm wrong" doesn't work as well as "what would you change about this approach if you were free to disagree?"

### Claude Code reports success without verification

If Claude Code says "all tests pass" without having actually run them, the pattern's verification function dies. Symptoms: completion summaries with high-level claims and no observed counts; "test exists for this" without confirming it passes.

Repair: explicit requirements for observed counts in completion summaries. CLAUDE.md amendments requiring "run the test, report what happened" not "verify the test exists."

### Developer overrides without engaging

If the developer waves past concerns without genuinely considering them, the pattern's review function dies from the other end. Symptoms: "let's just ship it" responses to substantive concerns; "I know what I'm doing" framing that closes discussion.

Repair: when conversational Claude raises a concern, the response should be either "here's why that doesn't apply" or "you're right, let me investigate." Not just "noted, proceeding."

### Forensic investigation gets skipped

When something looks off and there's deadline pressure, the temptation is to defer investigation. "We'll look into this after the deadline." Usually "after the deadline" never comes.

Repair: budget forensic time into the schedule. Treat investigation as core work, not optional. If you genuinely don't have time for investigation today, document the deferred issue explicitly so it doesn't get lost.

### Specifications become bureaucratic

If specifications start mattering more than the work they describe, the pattern has inverted itself. Symptoms: long debates over spec formatting; checklist completeness becoming the goal; specs that nobody actually reads.

Repair: remember why the spec exists (surfacing architectural decisions before they're hidden in code). If a spec section isn't serving that purpose, cut it.

### Methodology updates accumulate without integration

If every incident produces a new CLAUDE.md amendment, eventually CLAUDE.md becomes unreadable. Symptoms: 50-section CLAUDE.md that nobody can navigate; rules that contradict each other; lessons that nobody references.

Repair: periodic cleanup of CLAUDE.md. Consolidate related sections. Remove rules that have been superseded. Cross-reference instead of duplicating.

## How to start using this pattern

If a project might benefit from this approach, the rough sequence:

### Step 1: Establish the three roles clearly

Decide who's doing what. Specifically:

- Are you the developer? Are you willing to stay engaged with architectural decisions over the project's duration?
- Do you have access to a conversational Claude that can hold context across long threads? (claude.ai or similar)
- Do you have access to Claude Code or a similar agentic coding tool?

If any of these is missing or uncertain, this isn't the right pattern.

### Step 2: Write a baseline CLAUDE.md (or equivalent)

Project-specific document that captures:

- What the project is, who it's for
- Architectural principles
- Conventions (code style, commit format, test patterns)
- Anti-patterns to avoid
- The pattern itself (so future sessions have context)

This grows over time. Start with what you know; let it accumulate as you learn.

### Step 3: Try one goal end-to-end

Pick a meaningful unit of work — not too big, not too trivial. Draft a spec with conversational Claude. Hand the kickoff prompt to Claude Code. Get the completion summary. Review it. Walk through. Push when clean.

Notice what worked and what didn't. The first goal will be rough. The second will be better. By the fifth, the pattern will feel natural.

### Step 4: Establish the cultural properties

After a few goals, deliberately practice:

- Forensic investigation when something looks off (don't skip even if it feels like overkill)
- Pushback from conversational Claude (model it explicitly if it's not happening naturally)
- Honest reporting from Claude Code (notice when claims aren't substantiated)
- Documenting deferrals (track polish backlog explicitly)

The cultural properties are harder than the structural ones. They take longer to develop.

### Step 5: Let the methodology improve from incidents

When something goes wrong, run the response cycle: fix → understand → update methodology → document with reference. Don't skip the update step.

Over time, the project's CLAUDE.md becomes the accumulated wisdom of what's been learned. New sessions start with that wisdom available.

## Where this pattern might evolve

Things that aren't fully settled in the pattern as it currently exists:

### When to push to origin

The pattern accumulated commits locally between pushes. This works for solo development but doesn't scale to team work where origin needs to be a shared baseline.

### How to handle multi-developer collaboration

The pattern assumes a single developer in the middle. Multiple developers with conversational Claudes and Claude Code instances introduce coordination challenges that aren't solved here.

### When walkthroughs require human iPad time vs. Playwright

The pattern eventually settled on Playwright-driven walkthroughs for most verification with explicit deferrals for hardware ergonomics. Whether this is the right boundary varies by project — projects with significant device-specific UX may need more human walkthrough time than this pattern allocates.

### How much methodology amendment is too much

The pattern grew CLAUDE.md amendments organically. At some point, the methodology document needs structural editing or it becomes unreadable. When that point arrives and what to do about it isn't yet established.

### How to onboard new participants

Adding a new conversational Claude (different model, different session) or new developer to an established project requires re-establishing context. The patterns for doing this efficiently aren't yet refined.

## A final honest note

This pattern emerged from one project, with one developer, building one kind of software (multi-tenant SaaS for regulatory compliance). The properties that made it work include things specific to that context: the developer had strong architectural judgment, the project had real quality requirements (regulatory), the timeline was measured in months not days, and the developer enjoyed architectural thinking enough to stay engaged.

For projects matching that profile, the pattern produces clean, well-tested, architecturally coherent code with a defensible audit trail. For projects with different profiles, the pattern may need significant adaptation or may be wrong entirely.

The biggest risk in writing this document is that someone reads it, tries to apply it mechanically to a different context, and concludes either "this doesn't work" (because the cultural properties weren't there) or "this works great" (because they confirmation-biased themselves into thinking it did when it didn't).

The pattern's structural pieces are easy to copy. The cultural pieces are what make it actually work. If you find yourself adopting the structure without the culture, you're probably better off with a simpler approach.

The pattern's core insight, if it has one: software quality emerges from sustained discipline applied across many small decisions, not from any single brilliant insight or any single review pass. The three roles working together provide more sustained discipline than any one role alone could maintain. That's what produces the results, not the specific mechanics.

If a different set of mechanics would produce the same sustained discipline in a different context, that different set of mechanics would work too. The mechanics described here are one instance of the underlying principle, not the only valid expression of it.
