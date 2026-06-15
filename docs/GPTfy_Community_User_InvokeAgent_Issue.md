# GPTfy Community User — `invokeAgent()` Empty Body Issue

> **Org:** `gptfy-poc1`  
> **Site:** Experience Cloud LWR — `gptfysupport1`  
> **Affected agent:** `Question_Clarifier_Agent` (Security Audit label: **Question Clarifier Agent**)  
> **Salesforce workaround deployed:** June 2026 — read Security Audit **PII Added** when `invokeAgent()` body is empty  
> **Audience:** GPTfy vendor/developer, Salesforce admins, portal developers

---

## 1. Problem summary (one paragraph)

When a **Customer Community** user submits a question through the portal, GPTfy often **completes the agent successfully** and stores the full clarifier response in **Security Audit → AI Processed Data (PII Added)** — the same field the GPTfy UI renders in chat. However, `ccai.AIAgenticUtility.invokeAgent()` returns **`status = Error`** with an **empty `responseBody`** to Apex. Our integration treated that as failure even though the audit record (e.g. **A-00656**, **A-00661**) contains valid MCQs. Some community users (e.g. Andy Young) receive a non-empty synchronous `responseBody`; others (e.g. K7 Portal user) hit the empty-body path more often. **Permissions are not the differentiator** — both users had `SGPT_User`, `SGPT_Portal_User`, and `Gptfy_AI_models`.

---

## 2. Symptoms

| What you see | Meaning |
|--------------|---------|
| Portal orange banner / “AI temporarily unavailable” | Apex got empty `invokeAgent()` body; fallback JSON written with `_error` |
| GPTfy Security Audit chat shows cleaned question + MCQs | Agent **did** run; answer is in the audit |
| **AI Processed Data (PII Added)** populated | Canonical GPTfy output — **this is the field GPTfy UI uses** |
| **AI Processed Data (No PII)** shows `"status":"completed"` | Backend call may have succeeded while Apex wrapper still returned `Error` |
| Case `Intent_Analysis__c` has `_error` and empty `clarifications` | Old integration path failed before PII Added fallback (fixed in repo June 2026) |
| Andy Young works, K7 user fails (same site) | Same perm sets; difference is **sync `responseBody` vs audit-only** path |

---

## 3. Evidence from `gptfy-poc1` (June 2026)

### Failed portal run (K7 community user)

| Item | Value |
|------|--------|
| Case | `00001628` |
| Created by | Kesavamoorthy GPTfy (`kesavcbe23@gmail.com`) |
| Product | `PowerPDF` |
| Async job | `CaseQuestionClarifierAgentService` — Completed ~3s |
| Security Audit | **A-00656** — Created by **K7 Portal** |
| PII Added | **Full MCQs present** (Cleaned Question + Clarification 1 & 2) |
| Apex `invokeAgent()` | `status=Error`, **empty body** → `_error` on Case |

### Successful runs (comparison)

| Audit | Created by | PII Added | Portal result |
|-------|------------|-----------|---------------|
| A-00659 | Kesavamoorthy Kannan (admin script) | Full MCQs | GPTfy UI renders; admin `invokeAgent` repro works |
| A-00661 | K7 Portal | Full MCQs | Same message as failed run — data exists in audit |
| A-00638 | Andy Young | Present | Case `00001612` — MCQs in `Intent_Analysis__c` |

### Permission sets (Andy vs K7 — **identical**)

- `SGPT_User`
- `SGPT_Portal_User`
- `Gptfy_AI_models`
- `gptfysupport_Guest_Access`
- `GPTfy_Case_Fields_Access`

### Agent audit metadata (important for integrators)

On **agent** invocations (not prompt-only):

| Field | Typical value |
|-------|----------------|
| `ccai__Record_Id__c` | **null** |
| `ccai__AI_Prompt__c` | **null** |
| `ccai__Agent_Name__c` | `Question Clarifier Agent` |

Do **not** rely on Record Id or Prompt Id to find agent audit rows.

### PII Added JSON shape

GPTfy stores agent text inside a wrapper:

```json
{
  "messages": [
    "{\"message\": \"<p><strong>Cleaned Question:</strong> ...</p>...\", \"intents\": [], \"language\": \"en\", \"additionalParameters\": {}}"
  ],
  "fncDetails": []
}
```

Integrators must unwrap `messages[0].message` (itself a JSON string) before parsing clarifier sections.

---

## 4. What we fixed in Salesforce (workaround)

**Files changed:**

- `QuestionClarifierAction.cls` — `extractMessageFromPiiAdded()`, `loadClarifierAuditText()`, `parseClarifierResponse()`
- `CaseQuestionClarifierAgentService.cls` — if `invokeAgent()` body empty, load latest clarifier Security Audit for same user + case window
- `CaseResolutionController.getClarification()` — if cached JSON has `_error` or no MCQs, retry from Security Audit

**Verification script:** `scripts/apex/testPiiAddedClarifierRecovery.apex` (parses audit **A-00661** — PASS in org)

This is a **defensive integration pattern**. The underlying GPTfy behaviour should still be reviewed with the vendor.

---

## 5. What to ask GPTfy to fix (vendor ticket)

Copy or adapt the following for your GPTfy developer / support case.

### Subject

`invokeAgent()` returns empty `responseBody` / `status=Error` for Experience Cloud community users while Security Audit PII Added is populated

### Description

We invoke **`Question_Clarifier_Agent`** from Apex using:

```apex
ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName   = 'Question_Clarifier_Agent';
req.userMessage = 'Product: PowerPDF\nQuestion: How do I configure...';

ccai.AIAgenticWebService.ResponseWrapper resp =
    ccai.AIAgenticUtility.invokeAgent(req);
```

**Expected:** `response.responseBody` contains the same clarifier HTML/text shown in Security Audit chat and in `ccai__AI_Processed_Data_PII_Added__c`.

**Actual (community user, UserType = CspLitePortal):**

- `response.status` = `Error`
- `response.responseBody` = empty/null
- Security Audit **is created** (e.g. A-00656)
- `ccai__AI_Processed_Data_PII_Added__c` **is populated** with valid MCQs
- GPTfy UI on the audit record **renders the response correctly**

**Actual (some other users / admin):** synchronous `responseBody` is populated — integration works without reading the audit.

**Questions for GPTfy:**

1. Why does `AIAgenticUtility.invokeAgent()` return `Error` + empty body when the audit PII Added field is populated for the same transaction?
2. Is community / **CspLitePortal** user context treated as async-only (audit write) vs synchronous wrapper return?
3. Should integrators **always** poll `ccai__AI_Response__c` instead of trusting `responseBody` for agent calls?
4. Is there a GPT Config, agent profile, or package setting required so **`responseBody` is populated for Customer Community Login User** the same as for Standard User?
5. Can `ccai__Record_Id__c` be set on agent audits when invoked from a known Case Id (for easier correlation)?

### Attachments to provide GPTfy

- Security Audit **A-00656** (failed sync, PII Added OK)
- Security Audit **A-00659** or **A-00661** (comparison)
- Case `00001628` Intent_Analysis `_error` JSON
- AsyncApexJob id for the clarifier Queueable (~3s runtime)

---

## 6. GPTfy configuration checklist (admin)

Verify in Setup before blaming Apex:

| Check | Where | Notes |
|-------|--------|------|
| Agent active | GPTfy → Agents → **Question Clarifier Agent** | Developer name `Question_Clarifier_Agent` |
| Vector store assigned | Same agent | Same KB as Case Resolve Agent |
| GPT Config / model access | GPTfy Setup | Must include **Customer Community Login User** profile if GPTfy uses profile-scoped configs |
| Permission sets on community user | User → Permission Set Assignments | `SGPT_User`, `SGPT_Portal_User`, `Gptfy_AI_models` minimum |
| `ccai.AIAgenticUtility` class access | Permission set **SGPT_User** | Required for any user who enqueues the Queueable |
| Site Guest User (if public portal) | Separate from this issue | Guest needs same GPTfy sets if agents run as guest |

---

## 7. How to reproduce in a dev org

### Prerequisites

1. Deploy this project’s portal + agent-path classes to the dev org.
2. Experience Cloud site with `caseResolutionAssistant` LWC on the home page.
3. GPTfy agents: `Question_Clarifier_Agent`, `Case_Resolve_Agent`.
4. Two **logged-in** community users (or one community + one admin):
   - User A — e.g. Andy-style test member
   - User B — e.g. K7-style test member  
   Both need identical GPTfy permission sets.

### Reproduction steps (portal)

1. Log in to the Experience site as **User B** (community).
2. Submit a question (≥10 words), **Product required** — e.g. PowerPDF + retention policy question.
3. Wait on “Understanding your question…” (clarifier poll).
4. **If bug present:** Confirm screen shows friendly error; Case `Intent_Analysis__c` contains `"_error":"invokeAgent returned empty body | status=Error..."`.
5. Open **Setup → GPTfy → Security Audits** — latest row for **Question Clarifier Agent**, Created By = User B.
6. Open **Response** tab → confirm **AI Processed Data (PII Added)** has MCQs even though portal errored (pre-fix) or portal succeeds (post-fix).

### Reproduction steps (Apex — isolates GPTfy wrapper)

Run as **admin** (works):

```bash
sf apex run --file scripts/apex/reproCase00001628Clarifier.apex --target-org YOUR_ORG
```

Expect: non-empty `responseBody`, MCQs in debug log.

Compare Security Audit Created By for:

- Portal submit as community user
- Anonymous admin script

Query audits:

```sql
SELECT Name, CreatedBy.Name, ccai__Agent_Name__c, ccai__Status__c,
       ccai__AI_Processed_Data_PII_Added__c
FROM ccai__AI_Response__c
WHERE ccai__Agent_Name__c = 'Question Clarifier Agent'
ORDER BY CreatedDate DESC
LIMIT 10
```

Query failed Case:

```sql
SELECT CaseNumber, Intent_Analysis__c, Product__c, CreatedBy.Name
FROM Case
WHERE CreatedDate = TODAY
ORDER BY CreatedDate DESC
LIMIT 5
```

### Reproduction steps (verify Salesforce fix)

```bash
sf apex run --file scripts/apex/testPiiAddedClarifierRecovery.apex --target-org YOUR_ORG
```

Expect: `[ASSERT] K7 audit A-00661 parses to MCQs: PASS`

Then portal test as User B after hard refresh — expect MCQs on Confirm screen.

### Optional: compare two community users

| Step | User A (works) | User B (fails sync) |
|------|----------------|---------------------|
| Same question + product | ✓ | ✓ |
| Compare `responseBody` in Queueable debug | Non-empty | Empty + Error |
| Compare PII Added on audit | Populated | Populated |
| Compare perm sets | Must be identical | Must be identical |

If perm sets match and only sync return differs → **GPTfy platform issue**, not Salesforce permissions.

---

## 8. Apply the same pattern to other agents

The same empty-body / PII Added populated pattern may affect:

| Agent | Apex service |
|-------|----------------|
| `Question_Clarifier_Agent` | `CaseQuestionClarifierAgentService` — **fixed** |
| `Case_Resolve_Agent` | `CaseAgentResolutionService` — **candidate** for same audit fallback |
| `KB_Match_Agent` | `KbMatchAgentService` — **candidate** if community agents run from portal |

If resolution fails for community users with empty `Description` but Security Audit shows an answer, apply the same **PII Added recovery** pattern.

---

## 9. Related docs & scripts

| Resource | Purpose |
|----------|---------|
| `docs/SOLUTION_ARCHITECTURE.md` | End-to-end portal flow |
| `docs/Question_Clarifier_Agent_Prompt.md` | Agent prompt setup |
| `scripts/apex/reproCase00001628Clarifier.apex` | Admin repro of clarifier message |
| `scripts/apex/testPiiAddedClarifierRecovery.apex` | Parse PII Added from audit A-00661 |
| `scripts/apex/diagnoseClarifierAgentResponse.apex` | Raw `invokeAgent()` dump |

---

## 10. TL;DR for your developer

**Tell them:** “GPTfy completes the agent and writes the answer to Security Audit **PII Added**, but `AIAgenticUtility.invokeAgent()` returns **Error + empty body** for our Experience Cloud community user. Andy Young sometimes gets a synchronous body; K7 user doesn’t — same permission sets. We worked around it in Apex by reading PII Added when the wrapper is empty. Please fix GPTfy so **`invokeAgent().responseBody` matches PII Added** for **CspLitePortal** users, or document that integrators must poll Security Audit instead of using the synchronous return.”
