# KB Article Version-Based Update — Future Design

**Status:** Not implemented. This doc captures the design for when the team
decides to move from "flag for human update" to "auto-draft the update".

---

## Current Behaviour (Phase 1)

When `KB_Match_Agent` finds an existing article and the scope analysis says
`UPDATE_NEEDED: YES`, the solution today:

1. Writes the scope analysis to `Case.KB_Candidates__c` ("KB Update Scope" label).
2. Stops. The human support agent reads the field and manually decides whether to
   update the article.

The article is never touched programmatically.

---

## Proposed Behaviour (Phase 2)

Automatically create a **new Draft version** of the matched article with the
improved content pre-populated, ready for a knowledge manager to review and
publish.

```
KB_Match_Agent returns MATCH + KB_UPDATE_SCOPE_START … KB_UPDATE_SCOPE_END
       │
       ├─ UPDATE_NEEDED: NO  →  Write scope to Case field only (current behaviour)
       │
       └─ UPDATE_NEEDED: YES
                 │
                 ├─ Query KnowledgeArticle master record
                 │    (Title lookup → Knowledge__kav.KnowledgeArticleId)
                 │
                 ├─ Check: does a Draft version already exist?
                 │         Knowledge__kav WHERE KnowledgeArticleId = :id
                 │                           AND PublishStatus = 'Draft'
                 │
                 ├─ Draft EXISTS → log "Draft pending review" on Case, stop.
                 │                 (Do not overwrite a draft in flight.)
                 │
                 └─ No Draft → Phase 2 pipeline:
                       1. editOnlineArticle(masterArticleId)  ← creates new Draft
                       2. Invoke "KB Merge Agent" (GPTfy)
                              Input:  existing article body (Answer__c)
                                    + Case.Description (agent resolution)
                                    + SCOPE field from KB_UPDATE_SCOPE block
                              Output: merged article body (no duplication)
                       3. Update Draft Knowledge__kav.Answer__c
                       4. Write Draft article URL to Case.KB_Article_Link__c
                       5. (Optional) Trigger Salesforce Knowledge Approval Process
```

---

## Salesforce Knowledge Versioning — Key Technical Facts

### How versions work

| Concept | Detail |
|---|---|
| Parent record | `KnowledgeArticle` — one per article topic, stable `ArticleNumber`, never changes |
| Version record | `Knowledge__kav` — one row per version, `VersionNumber` auto-increments |
| Allowed co-existing states | ONE `Online` (Published) + ONE `Draft` at the same time |
| Archived | All older Published versions become `Archived` after each new publish |

### Critical constraint

> Only **one Draft version** can exist per article at any time.
> If `editOnlineArticle` is called when a Draft already exists, it throws
> `DUPLICATE_DEVELOPER_NAME`. The guard check above is mandatory.

### Programmatic API

```apex
// Step 1: get the master KnowledgeArticle Id from the __kav record
Knowledge__kav matched = [
    SELECT KnowledgeArticleId, VersionNumber
    FROM Knowledge__kav
    WHERE Title = :title
      AND PublishStatus = 'Online'
    LIMIT 1
];

// Step 2: check for an existing draft
List<Knowledge__kav> draftCheck = [
    SELECT Id
    FROM Knowledge__kav
    WHERE KnowledgeArticleId = :matched.KnowledgeArticleId
      AND PublishStatus = 'Draft'
];
if (!draftCheck.isEmpty()) {
    // A draft is already in review — bail out.
    return;
}

// Step 3: create a new draft version from the live Published article.
// unpublish = false → Published version stays Online; new Draft is created in parallel.
// unpublish = true  → Takes the article Offline; creates Draft. Avoid for live KBs.
KbManagement.PublishingService.editOnlineArticle(
    matched.KnowledgeArticleId,
    false   // keep published version live
);

// Step 4: fetch the newly created Draft version to update its body
Knowledge__kav draft = [
    SELECT Id, Title, Answer__c
    FROM Knowledge__kav
    WHERE KnowledgeArticleId = :matched.KnowledgeArticleId
      AND PublishStatus = 'Draft'
    LIMIT 1
];
draft.Answer__c = mergedBodyFromGPTfy;
update draft;

// Step 5: (optional) publish immediately — OR leave for human review
// KbManagement.PublishingService.publishArticle(matched.KnowledgeArticleId, true);
```

### Draft visibility

| Where | Visible? |
|---|---|
| Customer-facing portal | No — Draft is never shown to end users |
| Support agent in Salesforce | Yes — Draft appears in Knowledge search with a "Draft" badge |
| GPTfy RAG (FILE_SEARCH) | No — GPTfy only indexes `Online` (Published) articles |

The last point is important: even after creating a Draft update, future
`KB_Match_Agent` calls will still find the **Published** version (the body that
existed before the update). The improved body only becomes searchable after a
knowledge manager publishes it.

---

## New GPTfy Agent Required: KB Merge Agent

A separate agent is needed — the current KB Creation Prompt generates articles
from scratch. Merging requires understanding what already exists.

**Prompt design sketch:**

```
You are a technical knowledge base editor.

You are given:
1. EXISTING ARTICLE BODY: the current content of the article.
2. NEW RESOLUTION: a support agent's resolution for a recent case.
3. UPDATE SCOPE: what specific information should be added.

Your task:
- Read the existing article carefully.
- Integrate the new information from the resolution and scope into the article.
- Do NOT duplicate information that already exists.
- Preserve the article's structure and tone.
- Return ONLY the updated full article body. No commentary.
```

**Input merge field wiring:**
- `{!Knowledge__kav.Answer__c}` — existing article body (pass via merge field)
- `{!Case.Description}` — the agent's resolution text
- `{!Case.KB_Candidates__c}` — the SCOPE line from KB_UPDATE_SCOPE block

---

## For Draft-Only Articles (never published)

If the matched article has `PublishStatus = 'Draft'` (it was created but never
published), it will NOT appear in GPTfy's RAG — so `KB_Match_Agent` cannot find
it via FILE_SEARCH. The SOQL guard in `KbMatchAgentService` currently includes
`PublishStatus IN ('Draft', 'Online')`, which means a Draft title match would
still skip creation. In this case:

- Skip creation (already happening)
- If `UPDATE_NEEDED: YES`, update the Draft directly via DML — no
  `editOnlineArticle` call needed since the article is already a Draft.

---

## Why This Was Not Implemented in Phase 1

| Concern | Detail |
|---|---|
| New GPTfy prompt required | "KB Merge Agent" needs to be designed and tuned separately |
| Content merge risk | Badly merged articles are worse than the original; needs human QA before going live |
| Draft collision | Guard logic adds meaningful complexity |
| Human review still preferred | Publishing a Draft to production without review is too risky for this use-case |
| Developer Edition limits | Article + version count limits would be hit quickly during testing |

**Phase 1 tradeoff:** Give the human agent all the information they need
(`KB Update Scope` field on the Case) and let them decide. This is safe,
auditable, and already useful.

Phase 2 can be tackled once:
1. The team has validated the quality of `KB_Match_Agent`'s scope reasoning.
2. A "KB Merge Agent" prompt has been designed and tested.
3. A Knowledge Approval workflow is in place to gate Draft → Publish.
