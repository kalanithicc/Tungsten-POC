# Metadata Inventory — GPTfy Case Resolution Solution

Complete list of metadata **used by this solution**, with purpose. Items marked **Removed** were deleted in the June 2026 cleanup.

---

## Apex Classes

| Metadata | Package path | Need in solution |
|----------|--------------|------------------|
| `CaseResolutionController` | `force-app/main/default/classes/` | Guest LWC controller: `submitForClarification`, `getClarification`, `confirmQuestion`, `getRecommendation`, `resolveCase`, `sanitizeRecommendation`, quality guards |
| `CaseResolutionControllerTest` | same | Unit tests for controller |
| `CaseResolveActionController` | same | Agent Resolve quick action: save resolution, close case, enqueue KB match |
| `CaseResolveActionControllerTest` | same | Unit tests for agent controller |
| `CaseQuestionClarifierAgentService` | `force-app-agent-path/.../classes/` | Queueable: invokes `Question_Clarifier_Agent`, writes `Intent_Analysis__c` |
| `CaseAgentResolutionService` | `force-app-agent-path/.../classes/` | Queueable: invokes `Case_Resolve_Agent`, writes `Summary__c` + `Description` |
| `QuestionClarifierAction` | `force-app/main/default/classes/` | GPTfy Prompt Action + `buildJson()` parser for clarifier MCQ output |
| `KbMatchAgentService` | `force-app/main/default/classes/` | Queueable: `KB_Match_Agent` gate — skip (scope) or chain creation; HTML normalize + fuzzy title match |
| `KbCreationService` | `force-app/main/default/classes/` | Queueable: invokes KB Creation Prompt for Route 4 |
| `KbArticleBuilderAction` | `force-app/main/default/classes/` | GPTfy Prompt Action: parse prompt output, CREATE draft article, link Case, set `KB_Article_Link__c` |
| `KbArticleBuilderActionTest` | same | Unit tests for article builder |
| ~~`KbCandidateSearchService`~~ | — | **Removed** — legacy SOSL search |
| ~~`KbPromptContextService`~~ | — | **Removed** — legacy candidate staging |
| ~~`createSupportCase()` method~~ | on `CaseResolutionController` | **Legacy** — bypasses clarifier; kept for old scripts only |

---

## Apex Triggers

| Metadata | Object | Need in solution |
|----------|--------|------------------|
| `CaseAIAgentTrigger` | `Case` after insert | Legacy gate: enqueues resolution when `AI_Clarification_Pending__c != true` (non-clarifier inserts) |
| `CaseConfirmTrigger` | `Case_Clarification_Confirmed__e` after insert | Sets `Subject`, clears `AI_Clarification_Pending__c`, nulls `Intent_Analysis__c` |
| `CaseResolvedTrigger` | `Case_Resolved__e` after insert | Closes case; copies `Summary__c` → `Resolution__c` |
| ~~`CaseAIRequestTrigger`~~ | ~~`Case_AI_Requested__e`~~ | **Removed** — deprecated PE subscriber |

---

## Lightning Web Components

| Metadata | Need in solution |
|----------|------------------|
| `caseResolutionAssistant` | Portal UI: input, voice, clarification MCQs, resolution display, customer decision |
| `caseResolveAction` | Agent quick action modal: resolution text, Create KB checkbox, Save |

---

## Aura

| Metadata | Need in solution |
|----------|------------------|
| `caseResolveActionAura` | Quick action shell (`force:lightningQuickActionWithoutHeader`) hosting `caseResolveAction` |

---

## Flows

| Metadata | Status | Need in solution |
|----------|--------|------------------|
| `Case_Resolution_Email_RTF` | Active | On Case Closed + `SuppliedEmail` + `Resolution__c`: sends plain-text email using `Description` |
| `Case_Resolution_RTF` | Obsolete | **Deprecated** — legacy GPTfy prompt on Case create; replaced by agent Queueables |

---

## Platform Events

| Metadata | Fields | Need in solution |
|----------|--------|------------------|
| `Case_Clarification_Confirmed__e` | `CaseId__c`, `CleanedQuestion__c` | Guest confirms MCQs → system updates Case |
| `Case_Resolved__e` | `CaseId__c` | Guest marks resolved → system closes Case |
| ~~`Case_AI_Requested__e`~~ | ~~CaseId, Question, Product, RequestType~~ | **Removed** — failed Guest→Automated Process routing experiment |

---

## Case Custom Fields (solution-active)

| Field | Label / alias | Written by | Read by | Need |
|-------|---------------|------------|---------|------|
| `AI_Clarification_Pending__c` | AI Clarification Pending | `submitForClarification` | `CaseAIAgentTrigger`, `CaseConfirmTrigger` | Gates direct resolution on insert |
| `Intent_Analysis__c` | Intent Analysis | Clarifier service / `QuestionClarifierAction` | LWC `getClarification` | MCQ JSON for portal |
| `Summary__c` | Summary | `CaseAgentResolutionService` | LWC display, `CaseResolvedTrigger` | HTML AI answer |
| `Description` | Description (standard) | `CaseAgentResolutionService`, agent resolve path | Email flow formula, KB agents | Plain-text answer |
| `Resolution__c` | Resolution | Agent resolve, `CaseResolvedTrigger` | Email flow condition + legacy display | Final closed resolution |
| `Product__c` | Product | Portal form | Clarifier context (optional) | Product filter for guest |
| `KB_Candidates__c` | KB Update Scope | `KbMatchAgentService` (skip path) | Agent layout review | Why existing KB was missed + update scope |
| `KB_Article_Link__c` | KB Article Link | `KbArticleBuilderAction` | Agent layout | Clickable URL to created article |
| ~~`KB_Update_Status__c`~~ | — | — | — | **Removed** — never implemented |

---

## Case Custom Fields (org template — not used by this solution)

These exist in the repo/org from broader GPTfy demos or prior work. **Not read or written** by case resolution Apex/LWC/flows:

`AI_Email_Subject__c`, `AI_Resolution_Status__c`, `AI_Suggested_Articles__c`, `AI_Suggested_Product__c`, `Area__c`, `Case_Sentiment__c`, `Case_Summary__c`, `Client_Tier__c`, `Email_AI__c`, `Email_Body__c`, `Email_Subject__c`, `Ext_ID__c`, `Extracted_Product_Information__c`, `File_Summary__c`, `File_Summary_Done__c`, `GPTfy_Language__c`, `GPTfy_Product__c`, `GPTfy_Question__c`, `GPTfy_Root_Cause_Analysis__c`, `GPTfy_Root_Cause_Reason__c`, `GPTfy_Sentiment__c`, `GPTfy_Sentiment_Score__c`, `GPTfy_Status__c`, `GPTfy_Summary__c`, `Internal_Account__c`, `Intention__c`, `Issue__c`, `Issue_Triage_Score__c`, `issue_Triage_Routing__c`, `Open_Related_Tickets__c`, `Order_created__c`, `Prior_Escalation_Same_Issue__c`, `Prior_Ticket_Refs__c`, `Problem_statement__c`, `Products__c`, `Proposed_Resolution__c`, `Response_Description__c`, `Root_Cause__c`, `SLA_Class__c`, `SLA_Response_Hours__c`, `SLA_Status__c`, `Sub__c`, `Ticket_Age_Hours__c`, `Title__c`, `Topics__c`, `URL_Name__c`

---

## Knowledge Fields

| Object.Field | Need |
|--------------|------|
| `Knowledge__kav.Title` | Article title from customer question |
| `Knowledge__kav.UrlName` | Unique slug |
| `Knowledge__kav.Language` | `en_US` |
| `Knowledge__kav.Resolution__c` | Rich-text answer body |
| `Knowledge__kav.PublishStatus` | Draft/Online — used in KB match SOQL |

---

## Permission Sets

| Metadata | Need |
|----------|------|
| `gptfysupport_Guest_Access` | Guest: Case create/read, PE create, AI field read, `CaseResolutionController` |
| `GPTfy_Case_Fields_Access` | Internal agents: Case AI + KB fields, resolve action |

---

## Layouts

| Metadata | Need |
|----------|------|
| `Case-GPTfy Case Layout` | Agent console: resolution, AI analysis, `KB_Article_Link__c`, `KB_Candidates__c` |

---

## Experience Cloud

| Metadata | Need |
|----------|------|
| `digitalExperiences/site/gptfysupport1/` | LWR portal hosting `caseResolutionAssistant` on home page |

---

## GPTfy Configuration (org — not in repo)

| Asset | Need |
|-------|------|
| `Question_Clarifier_Agent` | MCQ generation from RAG |
| `Case_Resolve_Agent` | Customer-facing resolution |
| `KB_Match_Agent` | Semantic dedup gate for manual KB path |
| KB Creation Prompt | Generates structured CREATE Q&A |
| Vector store / FILE_SEARCH | All agents — articles must be indexed in GPTfy RAG |
| `ccai__AI_Response__c` | GPTfy audit / security log per invocation |

Prompt text: see `docs/` prompt files.

---

## Standard Objects Used

| Object | Need |
|--------|------|
| `Case` | Core ticket |
| `CaseArticle` | Junction linking created KB to Case |
| `Knowledge__kav` / `KnowledgeArticle` | Knowledge articles |

---

## Standard Case Fields Used

| Field | Need |
|-------|------|
| `Subject` | Question text |
| `Status` | New → Open → Closed |
| `Origin` | `Web` for portal cases |
| `SuppliedEmail`, `SuppliedName` | Guest contact |
| `Description` | Plain resolution |
| `Priority` | Set on create |

---

## Scripts (`scripts/apex/`)

Production verification scripts (cursor-tagged): `testQuestionClarification.apex`, `testE2E_Routes_*.apex`, `testKbCreateOnlyPolicy.apex`, `testKbUpdateScope.apex`, `verifyRoute3HtmlFix.apex`, etc.

**Deprecated scripts** (reference removed metadata): `testPortalPEFlow.apex`, `debugSoslCheck.apex`, `testKbCaseCandidates*.apex`, `testWeakTermFilter.apex`.

---

## Manifest

| File | Need |
|------|------|
| `manifest/destructiveChanges.xml` | Removes deprecated classes, PE, trigger, `KB_Update_Status__c` from org |
| `manifest/package-empty.xml` | Empty package paired with destructive deploy |
