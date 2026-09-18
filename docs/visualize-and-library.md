# Seeing the plan, sharpening the prompt, and the Library

Asked for on 2026-09-18: *"think visualization app structure before built, road maps and more,
how can we visualize plans further and add more ways to improve my prompts. Maybe even a
library that saves useful assets so we have ideas the AI can draw on from tags and keywords we
can run past clients linked briefs."*

How the pieces connect, because each one feeds the next:

```
Library ──references──▶ Brief ──▶ Prompt (effective view, lint) ──▶ Run ──▶ Report
   ▲                      ▲                                            │  (per-item answers,
   │                      │                                            │   screenshots, cost)
   └── client shortlist   └── Map / Roadmap node the brief belongs to  ▼
                                                              Ledger (outcome, rating)
                                                                      │
                                                    correction → Playbook rule → next Brief
```

## 1. Seeing a plan before anything is built
- **The Map** — AppPro's map, generalised to every project: nodes are screens, pages,
  services, data shapes and APIs; edges are navigation, data flow and dependency; a node is a
  phase. The AI drafts it from the brief; you edit by dragging. **The map is the plan** — the
  plan text is generated from it, never the reverse, so they cannot drift.
- **Roadmap** — phases as swimlanes on a timeline. Each shows its AI-executable steps, its
  human to-dos (owner, blocked-on), estimated credits, and risk flags. Drag a phase earlier and
  the dependencies it breaks light up.
- **Storyboard** — for every screen node, a cheap AI-generated low-fi wireframe; a filmstrip of
  the whole app before code. Tap through as a clickable prototype — the mockup-before-build
  pattern, automated.
- **Flows** — user journeys drawn as paths across the map ("book a showing"); a gap in the path
  is a missing screen, visible before it is missing in code.
- **Plan diff** — plans get revised in conversation; show two versions of the map with nodes
  added, removed and changed, and the text diff beside it.
- **Progress lens** — the same map coloured by status once building starts; a node opens its
  runs, commits and screenshots.
- **Cost lens** — estimated versus actual credits per node and phase, and which model did the
  work. "What did this feature cost" answered by pointing at it.
- **Critical path & blockers** — human to-dos that sit on the critical path (an Apple Developer
  account, a client's login) flagged at planning time, not discovered at build time.
- **Export** — any lens to a co-branded PDF or PNG for a client, or straight into a Brief.

## 2. More ways to improve prompts
- **Prompt Ledger** — every prompt sent, with its run, outcome, cost, screenshots and your rating
  or correction. Search "hero section" and see what worked last time and what it cost.
- **Effective-prompt view** — exactly what reaches Claude: your words, the Playbook rules that
  apply, glossary entries, references and Marks, in order. Toggle pieces before sending.
- **Prompt Lint** — the Assistant reads a prompt before it goes: ambiguous references ("that
  section" — which?), missing constraints (device, tone, don't-touch list), no verification
  step, no success criterion. It proposes a tightened draft; one tap accepts.
- **Reference-first** — attach Library items with their "what I like about it" notes; the
  prompt cites them by name. The reference is the spec, not inspiration.
- **Correction → rule** — when you edit or reject a result, the gap between what it did and
  what you wanted is offered as a Playbook rule with a *why*. One tap. Rules compound.
- **Glossary** — your named concepts (swatters, love letters, marks, arcade / kinesthetic) with
  definitions, injected automatically when the word appears in a prompt.
- **A/B runs** — one brief, two prompts or two models, previews side by side; pick; the
  winner's prompt is saved as the pattern.
- **Outcome-linked history** — prompts tagged with what they produced; "prompts that produced
  testimonials sections I rated good".
- **Brief templates with slots** — site brief, feature brief, fix brief, client-notes brief
  (numbered items, per-item answers — the JBN notes pattern).
- **Voice → structured brief** on the phone; the Assistant asks for what is missing.

## 3. The Library
- **Items** — images, sites and URLs, components extracted from shipped builds (with their
  code), palettes, fonts, copy snippets, motion effects, PDFs, client documents, screenshots and
  Marks, whole past briefs.
- **On every item** — tags, keywords, a "what I like about it" note, source and **licence**
  (stock photo terms tracked, so a client site never ships an unlicensed image), links to
  clients and sites, usage history (which briefs and runs used it), rating.
- **Import** — drop anything in; the AI auto-tags it (vision for images), suggests keywords,
  and flags duplicates. Semantic search over the lot.
- **Retrieval into prompts** — "draw on: arcade, kinesthetic" hands the run those items and
  their notes as references; while you write a brief the Assistant suggests items that match.
- **Client shortlist** — pick items, share a link, the client thumbs and comments without a
  login; their choices attach to the linked Brief. "Run past clients", built in.
- **Pattern library** — settled patterns from shipped work (a hero layout, a listing card, a
  love-letters carousel) kept as reusable units with the rules that govern them, so a build
  reuses what is settled instead of re-deriving it.
- **Scope** — a global library plus per-client sub-libraries; provenance on everything. In
  LodiStudios it lives in CloudKit (personal); the licensed studio keeps its own in its database.

### Auto-library: things are catalogued as they are made
Asked for on 2026-09-18: *"auto sort organize tag and library them as they're created
automatically on your end say the drones from DGM and roamers from JBN."*

The intake is the run itself, not a form:
- **Every run ends with a catalog step.** From the run's diff and report, the AI lists each
  reusable thing it created or materially changed — an effect, a component, an asset, a copy
  block, a palette — and files it: name, site, client, file paths, a screenshot or short clip
  captured from the preview, the concept it implements, and the Playbook rules that govern it.
- **The owner's names win.** If he has named a thing — DGM's drones are "swatters", JBN's
  "roamers" — the glossary supplies the name and the AI never invents another. A thing he has
  not named gets a plain descriptive name and a *needs a name* flag he can answer in one tap.
- **Sorted automatically** into Effects / Components / Assets / Copy / Palettes, under the
  client's sub-library and the global one; tags and keywords derived from the code, the brief
  that asked for it, and what it looks like (vision on the screenshot). Duplicates across sites
  are linked as variants of one pattern, not filed twice.
- **Retroactive harvest.** A one-time sweep of the sites that already exist (Drone God Max,
  JBN, greenflashusa.com) seeds the Library with the settled patterns — swatters, roamers, the
  love-letters carousel, the open-house scenes, the SSG motion effects — so the first brief can
  already draw on them.
- **Nothing is catalogued silently.** The run report shows "added to the Library: 3 items";
  the Board shows new items until seen. Hidden automation is how a library fills with junk.


## Order
1. Prompt Ledger, effective-prompt view and Prompt Lint — cheapest, and they cut credits
   immediately.
2. Library v1 — items, tags, notes, licence, retrieval into prompts, and the auto-catalog
   step at the end of every run; retroactive harvest of the existing sites.
3. Map and Roadmap, with storyboards and the cost lens — arrives with AppPro.
4. Client shortlists, alongside client marks (`docs/webpro-markup.md`).
