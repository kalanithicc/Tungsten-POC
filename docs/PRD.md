# GPTfy POC1 – Product Requirements Document (PRD)

| Field | Value |
|-------|-------|
| **Project** | GPTfy POC1 (Tungsten Automation – Use Case 2) |
| **Status** | In Progress – Parts 1, 2 & 3 complete, Part 4 (Speech-to-Text) complete |
| **Last updated** | 2026-06-12 |
| **GitHub repo** | https://github.com/K7-CC/GPTFY-POC1 |
| **Salesforce org** | `gptfy-poc1` (`kesavpoc@gptfy.com`) |
| **Latest checkpoint** | `Part-1` (tag) · latest commit `4a5a27a` |

---

## How to use this document

This PRD is a **living document**. It grows as the project grows.

| When | What to do |
|------|------------|
| After each commit / push | Run `.\scripts\update-prd-changelog.ps1` from the project root |
| After a major milestone | Add a new **Part** section and create a git tag (e.g. `Part-2`) |
| When the project is complete | Export to PDF – see [Export to PDF](#export-to-pdf) at the bottom |

---

## 1. What this project does (simple summary)

GPTfy POC1 helps customers get answers without waiting for an agent, and helps agents close cases faster.

**Three main paths:**

1. **Guest portal** – A customer fills a form, AI writes an answer, customer clicks "Yes, resolved", case closes, email sent.
2. **Agent Resolve button** – An agent types a resolution, case closes, draft Knowledge article created.
3. **Resolution email** – When any case with a guest email closes, the customer receives the answer by email.

**Two AI resolution modes (switchable):**

- **PATH 1 (Flow/GCP)** – `Case_Resolution_RTF` record-triggered flow calls GPTfy prompt flow to fill `Case.Description`.
- **PATH 2 (Agent/RAG)** – `CaseAIAgentTrigger` enqueues `CaseAgentResolutionService`, which calls the GPTfy "Case Resolve Agent" (`ccai.AIAgenticUtility`) to query the vector store and fill `Case.Description`.

Both paths write the answer to the same field; the LWC polling loop and downstream close/email flows are shared and path-agnostic.

---

## 2. Goals

| Goal | Why it matters |
|------|----------------|
| Deflect simple support questions via AI | Reduce agent workload |
| Close cases automatically when guest confirms | Faster resolution, no manual step |
| Let agents resolve cases in one click | Less clicking, consistent data |
| Draft Knowledge articles from resolutions | Build a reusable KB over time |
| Email the answer to the guest | Customer gets proof of resolution |
| Support multiple Tungsten products | E-Invoicing, TotalAgility, PowerPDF in one POC |

---

## 3. Users

| User | What they do |
|------|--------------|
| **Guest (portal visitor)** | Submits question, reads AI answer, confirms resolution |
| **Support agent** | Uses Resolve button, reviews draft KB articles |
| **Admin / developer** | Deploys metadata, configures flows/triggers, monitors email |

---

## 4. Features built (Part 1 + Part 2 in progress)

### 4.1 Guest portal – Case Resolution Assistant

**What the user sees:** A form on the Experience Cloud site (`gptfysupport1`).

**Steps (guest journey):**

1. Guest enters first name, last name, email, product (dynamic picklist from org), and question.
   - Guest can also **speak** their question using the mic icon inside the question textarea (see 4.10).
2. Guest clicks submit → a Case is created with `Origin = Web`.
3. Screen shows "loading" while AI works (polls up to 36 times, every 2.5 s → 90 s total).
4. AI answer appears in `Case.Description` (via PATH 1 or PATH 2, both write the same field).
5. Low-quality / no-match AI responses are automatically replaced with a polite `NO_ANSWER_MESSAGE`.
6. Guest reads the answer and can:
   - Click **"Yes, resolved"** → case closes, resolution saved, email sent.
   - Click **"No, create a case"** → case stays open for an agent.

**Technical pieces:**

| Piece | Location |
|-------|----------|
| LWC (UI) | `force-app/main/default/lwc/caseResolutionAssistant/` |
| Apex controller | `force-app/main/default/classes/CaseResolutionController.cls` |
| Apex tests | `force-app/main/default/classes/CaseResolutionControllerTest.cls` |
| Guest permission set | `force-app/main/default/permissionsets/gptfysupport_Guest_Access.permissionset-meta.xml` |
| AI prompt flow (PATH 1) | `force-app/main/default/flows/Case_Resolution_RTF.flow-meta.xml` |
| Experience Cloud site | `force-app/main/default/digitalExperiences/site/gptfysupport1/` |

---

### 4.2 Guest "Yes, resolved" – Case close path

**What happens behind the scenes:**

1. LWC calls `CaseResolutionController.resolveCase(caseId)`.
2. Apex publishes platform event `Case_Resolved__e` with the Case Id.
   - Guest users cannot update Cases directly – platform event runs in system context.
3. Trigger `CaseResolvedTrigger` fires:
   - Sets `Status = Closed`
   - Copies `Description` → `Resolution__c`
4. Record-triggered flow `Case_Resolution_Email_RTF` sends email (see 4.4).

**Technical pieces:**

| Piece | Location |
|-------|----------|
| Platform event | `force-app/main/default/objects/Case_Resolved__e/` |
| Trigger | `force-app/main/default/triggers/CaseResolvedTrigger.trigger` |

---

### 4.3 Agent Resolve button

**What the agent sees:** A **Resolve** button on open Cases (highlights panel).

**Steps (agent journey):**

1. Agent opens a Case where `Status ≠ Closed`.
2. Agent clicks **Resolve** → modal opens with rich-text editor.
3. Agent types the resolution text and optionally checks **"Update Knowledge Base"**.
4. Agent clicks **Save**. System:
   - Saves text to `Case.Resolution__c`
   - Sets `Status = Closed`
   - If "Update Knowledge Base" is checked → enqueues `KbCreationService` (async)
5. Toast confirms success (`caseClosed = true`, `articleQueued = true/false`); page refreshes.

**One-time org setup (not in source):** Wire the Resolve action on the Case Lightning Record Page. See `docs/resolve_button_setup.md`.

**Technical pieces:**

| Piece | Location |
|-------|----------|
| LWC (modal) | `force-app/main/default/lwc/caseResolveAction/` |
| Aura wrapper | `force-app/main/default/aura/caseResolveActionAura/` |
| Apex controller | `force-app/main/default/classes/CaseResolveActionController.cls` |
| Apex tests | `force-app/main/default/classes/CaseResolveActionControllerTest.cls` |
| Quick Action | `force-app/main/default/quickActions/Case.Resolve.quickAction-meta.xml` |

---

### 4.4 Resolution email on case close

**When it runs:** Case is updated to `Status = Closed`, `SuppliedEmail` is filled, and `Resolution__c` is not blank.

**What the guest receives:**

| Field | Source |
|-------|--------|
| **To** | `Case.SuppliedEmail` |
| **Subject** | `Case.Subject` (their original question) |
| **Body** | Intro line + decoded resolution text |

**Email body fix (Part 1):** Plain text format + HTML entity decoding (`&quot;` → `"`) so quotes display correctly.

**Org settings:**

| Setting | Value |
|---------|-------|
| Org-wide email | `kesavamoorthy@cloudcompliance.app` |
| Substitute sender workaround | `EmailAuthorization.enableSubstituteFromAddress = true` |
| Actual send domain | `...@sfcustomeremail.com` (until DKIM verified) |

**Technical pieces:**

| Piece | Location |
|-------|----------|
| Email flow | `force-app/main/default/flows/Case_Resolution_Email_RTF.flow-meta.xml` |
| Email auth setting | `force-app/main/default/settings/EmailAuthorization.settings-meta.xml` |

---

### 4.5 PATH 2 – GPTfy Agent / Vector Store resolution (NEW)

**What it does:** An alternative AI resolution path that calls the GPTfy "Case Resolve Agent" directly via the `ccai.AIAgenticUtility` managed-package API instead of the record-triggered flow. Queries the vector store with the case subject and writes the plain-text answer to `Case.Description`.

**Switch mechanism:**

| To use | Activate | Deactivate |
|--------|----------|------------|
| PATH 1 (Flow/GCP) | `Case_Resolution_RTF` flow | `CaseAIAgentTrigger` trigger |
| PATH 2 (Agent/RAG) | `CaseAIAgentTrigger` trigger | `Case_Resolution_RTF` flow |

> Never run both active at the same time – two AI calls would race to write `Case.Description`.

**How it works:**

1. New `Origin='Web'` Case inserted → `CaseAIAgentTrigger` fires (after insert).
2. Trigger enqueues `CaseAgentResolutionService` (Queueable + Database.AllowsCallouts).
3. Service calls `ccai.AIAgenticUtility.invokeAgent()` with the case subject (cleaned: surrounding quotes stripped for better RAG similarity scoring).
4. Response HTML is stripped to plain text and written to `Case.Description`.
5. Errors are written to `Case.Description` with `[AGENT ERROR]` / `[EXCEPTION]` prefix so the LWC polling loop can surface them.

**Technical pieces:**

| Piece | Location |
|-------|----------|
| Trigger | `force-app-agent-path/main/default/triggers/CaseAIAgentTrigger.trigger` |
| Queueable service | `force-app-agent-path/main/default/classes/CaseAgentResolutionService.cls` |
| sfdx source directory | `force-app-agent-path` (registered in `sfdx-project.json`) |
| Test script | `scripts/apex/agent-path/testAgentPath.apex` |

---

### 4.6 Low-quality response filtering (NEW)

**What it does:** `CaseResolutionController.sanitizeRecommendation()` intercepts AI answers before they are shown to the guest. Junk responses (agent confusion messages, "I didn't get that", "no answer found in the knowledge base", etc.) are silently replaced with a polite fallback message instead of exposing raw AI errors.

**Two detection strategies:**

| Strategy | How it works |
|----------|-------------|
| Exact match | `LOW_QUALITY_RESPONSES` set – normalised lowercase comparison |
| Contains match | `LOW_QUALITY_CONTAINS` list – substring scan; catches long fallback sentences from agent system prompts |

**Constants (kept in sync with LWC JS):**

| Constant | Used when |
|----------|-----------|
| `NO_ANSWER_MESSAGE` | AI returned a recognisable junk/no-match response |
| `TIMEOUT_MESSAGE` | LWC poll window expired and `Description` is still blank |

**Technical pieces:**

| Piece | Location |
|-------|----------|
| Apex method | `CaseResolutionController.sanitizeRecommendation()` |
| Test script | `scripts/apex/testRecommendationSanitize.apex` |

---

### 4.7 Dynamic product picklist (NEW)

`CaseResolutionController.getProductOptions()` returns active `Case.Product__c` picklist values at runtime. The LWC `<select>` renders these dynamically instead of hard-coded values.

**Current POC product values:**

| Label | Notes |
|-------|-------|
| E-Invoicing | Tungsten product |
| TotalAgility | Tungsten product |
| PowerPDF | Tungsten product |

**Technical piece:** `@AuraEnabled(cacheable=true)` method in `CaseResolutionController`; picklist values managed via `force-app/main/default/objects/Case/fields/Product__c.field-meta.xml`.

---

### 4.8 Knowledge Base data pipeline (NEW)

Tungsten product FAQ content scraped, cleaned, and loaded into Salesforce Knowledge.

**Data files:**

| File | Product | Approximate rows |
|------|---------|-----------------|
| `data/einvoicing-faq-kb.csv` | E-Invoicing | ~2 600 |
| `data/powerpdf-faq-kb.csv` | PowerPDF | ~5 100 |
| `data/totalagility-faq-kb.csv` | TotalAgility | ~78 000 |

**Pipeline scripts:**

| Script | Purpose |
|--------|---------|
| `scripts/scrape_tungsten_kb.py` | Scrapes Tungsten support site, outputs CSV |
| `scripts/batch_import_kb.py` | Batch-imports CSV rows into Salesforce Knowledge via REST API |
| `scripts/generate_kb_apex.py` | Generates Apex batch scripts from CSV |
| `scripts/generate_kb_update_apex.py` | Generates Apex update scripts |
| `scripts/apex/importPowerPDFKB.apex` | Imports PowerPDF KB articles |
| `scripts/apex/updatePowerPDFKB.apex` | Updates existing PowerPDF articles |
| `scripts/apex/deleteOldPowerPDFKB.apex` | Cleanup script for stale articles |
| `scripts/apex/batches/batch_001.apex` | Auto-generated batch insert (358 articles) |

---

### 4.9 AI-powered KB article generation (NEW – Part 3)

**What it does:** When the agent checks **"Update Knowledge Base"** and clicks Save, the system asynchronously invokes the GPTfy **KB Creation Prompt** via `ccai__AIPromptProcessingInvokable`. The LLM receives the portal question (`Case.Subject`) and agent resolution (`Case.Resolution__c`), then generates **6 Q&A pairs** (1 original enhanced + 5 phrasing variations). A configured Prompt Action (`KbArticleBuilderAction`) then bulk-inserts 6 draft `Knowledge__kav` articles and links them all to the Case via `CaseArticle`.

**How it works (full pipeline):**

1. Agent saves resolution with `createKb = true`
2. `CaseResolveActionController.saveResolution()` enqueues `KbCreationService`
3. `KbCreationService.execute()` calls `ccai__AIPromptProcessingInvokable` with `promptRequestId`, `recordId` (Case Id), and a random `eventUUID`
4. GPTfy invokes the KB Creation Prompt (LLM sees `Case.Subject` + `Case.Resolution__c`)
5. LLM returns structured text: `Portal Question` + `OG Answer` + `Question 1–5` + `Answer 1–5`
6. GPTfy fires the configured Prompt Action → `KbArticleBuilderAction.invokeApex()` is called with the `ccai__AI_Response__c` record
7. `KbArticleBuilderAction` parses the 6 Q&A pairs, inserts 6 draft `Knowledge__kav` articles, and links each via `CaseArticle`

**KB Creation Prompt (KCS-compliant):**

- Reads `Case.Subject` (original portal question) and `Case.Resolution__c` (agent text)
- Rewrites the agent resolution into a professional KB answer
- Generates 5 additional unique question phrasings (direct, how-to, troubleshooting, conceptual, scenario-based)
- **Source fidelity constraint:** LLM must not add information not present in the agent's resolution — no hallucination, no external knowledge
- Prompt file: `docs/KB Creation Prompt`

**Article deduplication and URL uniqueness:**

- `UrlName` is built from the question text (lowercased, non-alphanumeric chars replaced with `-`) plus a random 8-char hex suffix — guarantees uniqueness within a batch and against existing articles
- Title is capped at 255 chars

**Error handling:**

- Blank or JSON-error GPTfy responses are logged and skipped (no articles created)
- Article `insert` failures are caught and logged; do not surface to the agent (case is already closed)
- `CaseArticle` link failures are caught separately and logged
- `KbCreationService` failure does not affect case close or resolution save (best-effort)

**Technical pieces:**

| Piece | Location |
|-------|----------|
| Queueable service | `force-app/main/default/classes/KbCreationService.cls` |
| Prompt action | `force-app/main/default/classes/KbArticleBuilderAction.cls` |
| Prompt action tests | `force-app/main/default/classes/KbArticleBuilderActionTest.cls` |
| GPTfy prompt template | `docs/KB Creation Prompt` |
| E2E verification | `scripts/apex/testKbCreation.apex` |
| Save button E2E | `scripts/apex/testSaveButtonE2E.apex` |
| Prompt diagnostics | `scripts/apex/diagKbPromptInvocation.apex` |
| Trace enabler | `scripts/apex/enableTraceAndTest.apex` |

---

## 5. End-to-end flow diagrams

### Guest portal → close → email

```
Guest form (LWC)
    → createSupportCase (Apex)
    → Case created (Origin=Web)

PATH 1:  Case_Resolution_RTF flow → GPTfy AI → Description filled
PATH 2:  CaseAIAgentTrigger → CaseAgentResolutionService (Queueable)
                             → ccai.AIAgenticUtility.invokeAgent()
                             → Description filled (HTML stripped)

    → sanitizeRecommendation() filters junk responses
    → Guest sees answer
    → "Yes, resolved" → resolveCase (Apex)
    → Case_Resolved__e published
    → CaseResolvedTrigger → Status=Closed, Resolution__c=Description
    → Case_Resolution_Email_RTF → email to SuppliedEmail
```

### Agent resolve → AI KB generation

```
Agent clicks Resolve (Quick Action)
    → caseResolveAction LWC modal (resolution text + "Update Knowledge Base" checkbox)
    → saveResolution(caseId, text, createKb) (Apex)
    → Resolution__c saved, Status=Closed
    → [if createKb=true] KbCreationService enqueued (Queueable)
        → ccai__AIPromptProcessingInvokable (KB Creation Prompt)
        → LLM generates 6 Q&A pairs (1 original + 5 variations)
        → KbArticleBuilderAction.invokeApex() (Prompt Action)
        → 6 draft Knowledge__kav articles inserted
        → 6 CaseArticle links created
    → Case_Resolution_Email_RTF (if SuppliedEmail present)
```

---

## 6. Key Salesforce fields (Case)

| Field | Purpose |
|-------|---------|
| `Subject` | Guest question / email subject |
| `Description` | AI-generated answer (written by PATH 1 or PATH 2) |
| `Resolution__c` | Final resolution text (Html field; copied from Description on close) |
| `SuppliedEmail` | Guest email for notifications |
| `SuppliedName` | Guest name from form |
| `Origin` | `Web` for portal cases (gates both AI paths) |
| `Product__c` | Product picklist – E-Invoicing / TotalAgility / PowerPDF |
| `Status` | `Closed` triggers email flow |

---

## 7. Verification scripts

All test scripts live in `scripts/apex/`. Run with:

```powershell
sf apex run --file scripts/apex/<script-name>.apex --target-org gptfy-poc1
```

| Script | What it tests |
|--------|---------------|
| `testCaseResolutionEmail.apex` | Guest close, agent close, no-email guard, re-save guard |
| `testCaseResolutionEmailBody.apex` | Email body formatting with quotes |
| `testCaseResolveActionUI.apex` | Agent resolve path |
| `testCaseResolveKbDraft.apex` | Knowledge article draft on resolve |
| `testRecommendationSanitize.apex` | Low-quality response filtering |
| `testIrrelevantQuestionCreate.apex` | Creates irrelevant-question test case |
| `testIrrelevantQuestionRag.apex` | RAG answer quality for irrelevant questions |
| `testIrrelevantQuestionResult.apex` | Reads result of irrelevant-question test |
| `testEssentialEightRag.apex` | RAG answer quality for standard product questions |
| `testProductPicklist.apex` | Verifies Product__c picklist values in org |
| `testConfigUnblockers.apex` | Validates org config (sharing, permissions, email) |
| `agent-path/testAgentPath.apex` | End-to-end PATH 2 (Agent/RAG) smoke test |
| `testKbCreation.apex` | End-to-end KB AI generation pipeline (prompt → 6 articles) |
| `testSaveButtonE2E.apex` | Agent Save button with `createKb=true` E2E flow |
| `diagKbPromptInvocation.apex` | Diagnoses GPTfy KB prompt invocation and response |
| `enableTraceAndTest.apex` | Enables Apex trace flags for KB pipeline debugging |

**Agent/prompt utility scripts** (for GPTfy agent inspection):

| Script | Purpose |
|--------|---------|
| `describeAgent.apex` | Lists agent configuration details |
| `describePrompt.apex` | Reads prompt template metadata |
| `readAgentPrompt.apex` | Reads current agent system prompt |
| `readPrompt.apex` | Reads a named prompt |
| `updateAgentPrompt.apex` | Updates agent system prompt text |
| `verifyAgentPrompt.apex` | Verifies prompt content matches expected |

Test records use marker `cursor-test-{timestamp}` in Subject for easy cleanup.

---

## 8. Known limitations

| Limitation | Notes |
|------------|-------|
| `Resolution__c` is Html field | Quotes may store as `&quot;` – email flow decodes them |
| Email sender uses substitute address | Until DKIM verified for `cloudcompliance.app` |
| PATH 1 `Case_Resolution_RTF` may be Draft in org | Needs activation + prompt verification |
| Resolve button page wiring | Manual one-time Setup step |
| PATH 1 and PATH 2 are mutually exclusive | Only one AI path active at a time; never activate both |
| KB data import is one-directional | No automatic sync when Tungsten updates their docs |
| Agent callout runs in Queueable | Cannot be tested in synchronous Apex test context (mock required) |

---

### 4.10 Speech-to-text input on guest portal (NEW – Part 4)

**What it does:** A microphone icon sits inside the bottom-right corner of the "Your Question" textarea. Guests can tap it to speak their issue instead of typing, allowing them to describe problems more elaborately and naturally. Voice input produces richer, more detailed questions, which leads to better AI matching against the knowledge base.

**How it works:**

1. Guest clicks the mic icon → browser requests microphone permission (one-time).
2. Icon turns into a pulsing red dot; a `● Listening — speak now` bar appears below the textarea.
3. Words appear **live in the textarea** as the guest speaks — interim phrases show in real-time and are committed when a phrase is finalised.
4. Click the icon again (or pause speaking) to stop recording.
5. Transcript is **appended** to any text already typed — never replaces existing content.
6. Guest can then click **Find a Solution** as normal with the spoken text as the question.

**Browser support:**

| Browser | Behaviour |
|---------|-----------|
| Chrome / Edge | Full speech-to-text (Web Speech API) |
| Firefox / Safari | Mic icon still appears; clicking shows "not supported" error inline |

**Error handling:**

| Scenario | Response |
|----------|----------|
| Microphone permission denied | Inline red error below the textarea |
| Browser does not support Web Speech API | Inline error message on click |
| Component destroyed while recording | Recognition stopped in `disconnectedCallback` |

**Technical implementation notes:**

- Uses `window.SpeechRecognition || window.webkitSpeechRecognition` (Chrome built-in, no external API calls)
- `continuous: true` — keeps recording across natural pauses; user speaks in chunks
- `interimResults: true` — interim words pushed to textarea DOM directly (bypasses LWC reactivity lag via `this.template.querySelector('textarea')`)
- LWC scopes element IDs in shadow DOM — selector uses tag name (`'textarea'`), not ID
- Capability check deferred to click time (not `connectedCallback`) for Lightning Web Security (LWS) compatibility on Experience Cloud LWR

**Technical pieces:**

| Piece | Location |
|-------|----------|
| LWC HTML (mic icon, listening bar) | `force-app/main/default/lwc/caseResolutionAssistant/caseResolutionAssistant.html` |
| LWC JS (SpeechRecognition logic) | `force-app/main/default/lwc/caseResolutionAssistant/caseResolutionAssistant.js` |
| LWC CSS (icon, pulse animation) | `force-app/main/default/lwc/caseResolutionAssistant/caseResolutionAssistant.css` |

---

## 9. Pending work

See `POC_CHECKLIST.md` for full checklist. High-priority items:

- [ ] Activate either `Case_Resolution_RTF` (PATH 1) or `CaseAIAgentTrigger` (PATH 2) – confirm which path for demo
- [ ] Complete TotalAgility KB import (large dataset – batch jobs)
- [ ] DKIM verification for `cloudcompliance.app` email domain
- [ ] Deflection metrics and reports
- [ ] UAT and demo recording
- [ ] Finalize Experience Cloud site branding (`gptfysupport1`)

**Completed (removed from pending):**
- ~~GPTfy KB drafting prompt~~ — Done: KB Creation Prompt (`docs/KB Creation Prompt`) with KCS-compliant 6-article generation pipeline (`KbCreationService` + `KbArticleBuilderAction`)
- ~~Speech-to-text input~~ — Done: mic icon in question textarea using Web Speech API (see 4.10)

---

## 10. Repository and checkpoints

| Item | Value |
|------|-------|
| Remote | `origin` → https://github.com/K7-CC/GPTFY-POC1.git |
| Default branch | `main` |
| Checkpoint **Part 1** | Tag `Part-1` on commit `15e9bcb` |
| Latest commit | `4a5a27a` (2026-06-05) |

**Restore to Part 1:**
```powershell
git fetch origin
git checkout Part-1
```

---

## 11. Change log (auto-updated from Git)

<!-- CHANGELOG_START -->
| Date | Commit | Tag | Summary |
|------|--------|-----|---------|
| 2026-06-12 | `8c099b9` | - | Store KB candidates on Case.KB_Candidates__c instead of KB_Prompt_Context__c |
| 2026-06-12 | `186d0dc` | checkpoint-4 | checkpoint 4: KB candidate search, CREATE/UPDATE upsert, and chained prompt fix |
| 2026-06-08 | `804ab11` | Part-3 | checkpoint: Part 3 - AI-powered KB generation pipeline |
| 2026-06-05 | `9c31a05` | - | docs: update PRD and project walkthrough to reflect Part 2 (Agent/RAG path) |
| 2026-06-05 | `4a5a27a` | - | checkpoint: agent resolution service updates and apex utility scripts |
| 2026-06-04 | `eeb14d3` | checkpoint-2 | checkpoint: agent-path trigger, KB data expansion, and case resolution improvements |
| 2026-06-04 | `67f4b0d` | - | checkpoint: case resolution assistant, KB pipeline, and support site |
| 2026-06-03 | `a419e45` | - | docs: fix PRD changelog script and refresh commit log |
| 2026-06-03 | `ae3cde5` | - | docs: add living PRD with auto-updated changelog |
| 2026-06-03 | `15e9bcb` | Part-1 | Initial commit: GPTfy POC1 Salesforce project |
<!-- CHANGELOG_END -->

---

## 12. Part history (milestones)

### Part 1 – Working baseline (2026-06-03)

**Tag:** `Part-1` · **Commit:** `15e9bcb`

**Delivered:**
- Guest portal LWC + Apex + platform event close path
- Agent Resolve quick action + KB draft
- Resolution email flow with plain-text body fix
- Org verification scripts
- GitHub repo + Part 1 checkpoint

**Status:** Verified working in `gptfy-poc1` org.

---

### Part 2 – Agent/RAG Path + KB Pipeline (2026-06-04 → 2026-06-05)

**Commits:** `67f4b0d`, `eeb14d3`, `4a5a27a`

**Delivered:**
- PATH 2: `CaseAIAgentTrigger` + `CaseAgentResolutionService` (Queueable, callout to `ccai.AIAgenticUtility`)
- Switch mechanism between PATH 1 (flow) and PATH 2 (agent) – never both active
- Low-quality AI response filtering (`sanitizeRecommendation`, `LOW_QUALITY_RESPONSES`, `LOW_QUALITY_CONTAINS`)
- Dynamic product picklist (`getProductOptions`) + POC products: E-Invoicing, TotalAgility, PowerPDF
- `NO_ANSWER_MESSAGE` and `TIMEOUT_MESSAGE` constants (kept in sync with LWC)
- `cleanSubject()` – strips surrounding quotes from subject before RAG query
- `stripHtml()` – strips HTML tags and collapses blank lines in agent response
- KB data files: `einvoicing-faq-kb.csv`, `powerpdf-faq-kb.csv`, `totalagility-faq-kb.csv`
- KB import/scrape pipeline: Python scripts + Apex batch scripts
- Experience Cloud site source: `gptfysupport1`
- Expanded verification scripts (RAG quality, sanitize, config, product picklist, agent path)
- Agent prompt utility scripts (describe, read, update, verify)
- Project Walkthrough doc (`docs/GPTfy-POC1-Project-Walkthrough.md`)

**Status:** Complete.

---

### Part 3 – AI-Powered KB Article Generation (2026-06-08)

**Delivered:**
- KCS-compliant KB Creation Prompt (`docs/KB Creation Prompt`) — takes `Case.Subject` + `Case.Resolution__c`, generates 1 original enhanced answer + 5 question-phrasing variations; strict source-fidelity constraint (no hallucination)
- `KbCreationService.cls` — Queueable + `Database.AllowsCallouts`; invokes `ccai__AIPromptProcessingInvokable` with the KB Creation Prompt `promptRequestId`, Case `recordId`, and a random `eventUUID`
- `KbArticleBuilderAction.cls` — implements `ccai.AIPromptActionInterface`; called by GPTfy after LLM responds; parses 6 Q&A pairs from structured response; bulk-inserts 6 draft `Knowledge__kav` articles; links all 6 to Case via `CaseArticle`; URL slug uniqueness via 8-char random hex suffix; graceful error handling at every DML boundary
- `KbArticleBuilderActionTest.cls` — unit tests covering parser, URL slug builder, article creation, and error paths
- `CaseResolveActionController.cls` updated — `saveResolution()` now accepts `createKb` boolean; enqueues `KbCreationService` when true; returns `SaveResult` (`caseClosed`, `articleQueued`, `articleWarning`)
- `caseResolveAction.js` (LWC) updated — "Update Knowledge Base" checkbox wired to `createKb` parameter
- New verification scripts: `testKbCreation.apex`, `testSaveButtonE2E.apex`, `diagKbPromptInvocation.apex`, `enableTraceAndTest.apex`

**Status:** Complete and verified working in `gptfy-poc1` org.

---

### Part 4 – Speech-to-Text Input (2026-06-12)

**Delivered:**
- Mic icon embedded inside the "Your Question" textarea (bottom-right, positioned with CSS `absolute`)
- Chrome Web Speech API integration: `continuous: true`, `interimResults: true`
- Live word-by-word transcript directly in the textarea DOM (bypasses LWC reactivity lag)
- Append-only behaviour — typed text is never replaced by speech
- Pulsing red dot icon + `● Listening — speak now` status bar when recording
- Graceful fallback: capability check at click time (not load time) for LWS compatibility; unsupported browsers get inline error
- `disconnectedCallback` cleanup — recognition stopped if component unmounts mid-recording

**Status:** Complete and verified in `gptfy-poc1` org.

---

<!-- Add Part 5, etc. below as milestones are reached -->

---

## Export to PDF

When the project is complete, use any of these options:

### Option A – VS Code / Cursor (easiest)

1. Open `docs/PRD.md` in the editor.
2. Install extension **Markdown PDF** (yzane.markdown-pdf) if not installed.
3. Right-click the file → **Markdown PDF: Export (pdf)**.
4. Save as `docs/PRD-GPTfy-POC1-Final.pdf`.

### Option B – GitHub (no install)

1. Push latest `docs/PRD.md` to GitHub.
2. Open the file on github.com → it renders as formatted HTML.
3. Browser **Print** → **Save as PDF**.

### Option C – Pandoc (command line)

```powershell
pandoc docs/PRD.md -o docs/PRD-GPTfy-POC1-Final.pdf --pdf-engine=wkhtmltopdf
```

### Before final export

1. Run `.\scripts\update-prd-changelog.ps1` so all commits are listed.
2. Update **Status** at the top to `Complete`.
3. Fill in any remaining **Part** sections.
4. Export using one of the options above.

---

*This document is maintained in source control at `docs/PRD.md`.*
