/**
 * Apex controller for the Case Resolution Assistant LWC.
 *
 * Runs WITHOUT SHARING because the LWC is invoked by the unauthenticated
 * Guest User on a public Experience Cloud (LWR) site. The Guest User
 * profile typically cannot insert/read/update Case records under default
 * sharing rules, so we explicitly elevate privileges for these three
 * narrow, well-defined operations.
 *
 * Methods exposed to the LWC:
 *   1. createSupportCase  - inserts a new Case from the form fields
 *   2. getRecommendation  - polled while waiting for the GPTfy AI answer
 *   3. resolveCase        - publishes a Case_Resolved__e Platform Event so that
 *                           CaseResolvedTrigger can close the Case in system
 *                           context (the Guest User License forbids guests from
 *                           updating Cases directly)
 */
public without sharing class CaseResolutionController {

    private static final Integer SUBJECT_MAX_LENGTH = 255;

    /**
     * Shown when GPTfy returns a junk/no-match style answer. Keep in sync with
     * caseResolutionAssistant.js NO_ANSWER_MESSAGE.
     */
    public static final String NO_ANSWER_MESSAGE =
        'Thank you for your question. We could not find a specific answer in our knowledge base at this time. ' +
        'Our support team will review your case and follow up with you shortly.';

    /**
     * Shown when Description is still empty after the LWC poll window (GPTfy still
     * processing or failed). Keep in sync with caseResolutionAssistant.js
     * TIMEOUT_MESSAGE.
     */
    public static final String TIMEOUT_MESSAGE =
        'Thank you for your patience. We are still processing your question. ' +
        'Our support team has your case and will follow up with you shortly.';

    private static final List<String> LOW_QUALITY_CONTAINS = new List<String>{
        'didn\'t get that',
        'did not get that',
        'what was that',
        'can you repeat',
        'can you rephrase',
        'can you say it again',
        'can you say that again',
        'say that again',
        'say it again',
        'say that one more time',
        'one more time?',
        'one more time',
        'missed what you said',
        'sorry, what was',
        'sorry, can you',
        'sorry, i didn\'t',
        'sorry, i did not',
        'no answer found in the knowledge base',
        'no relevant information was found in the knowledge base',
        'not available in the current knowledge base',
        'does not contain sufficient information',
        'knowledge base does not contain',
        'not contain information to answer',
        'outside the scope of available knowledge'
    };

    private static final Set<String> LOW_QUALITY_RESPONSES = new Set<String>{
        'what was that?',
        'what was that',
        'huh?',
        'sorry, i don\'t know',
        'sorry, i do not know',
        'i don\'t know',
        'i do not know',
        'no answer found',
        'no answer available',
        'unable to answer',
        'unable to find an answer',
        'could not find an answer',
        'couldn\'t find an answer',
        'could not find a match',
        'couldn\'t find a match',
        'no relevant information found',
        'no relevant results found',
        'i\'m not sure',
        'i am not sure',
        'i cannot answer',
        'i can\'t answer',
        'i didn\'t get that. can you repeat?',
        'i didn\'t get that. can you say it again?',
        'sorry, i didn\'t get that. can you rephrase?',
        'sorry, what was that?',
        'sorry, can you say that again?',
        'sorry, can you say that again',
        'can you say that again?',
        'can you say that again',
        'say that one more time?',
        'say that one more time',
        'i missed what you said. what was that?'
    };

    /**
     * Inserts a new Case from the guest's form submission.
     * Origin = 'Web' is critical: the record-triggered Flow filters on it.
     *
     * @param firstName  Guest's first name (becomes part of SuppliedName)
     * @param lastName   Guest's last name  (becomes part of SuppliedName)
     * @param email      Guest's email      (stored on SuppliedEmail)
     * @param subject    The user's question (stored on Subject; truncated to 255 chars)
     * @param product    Required product picklist value (stored on Product__c).
     * @return Map with keys 'caseId' (the new record's Id) and
     *         'caseNumber' (the auto-generated human-readable number).
     */
    @AuraEnabled
    public static Map<String, String> createSupportCase(
        String firstName,
        String lastName,
        String email,
        String subject,
        String product
    ) {
        try {
            String safeSubject = subject == null ? '' : subject;
            if (safeSubject.length() > SUBJECT_MAX_LENGTH) {
                safeSubject = safeSubject.substring(0, SUBJECT_MAX_LENGTH);
            }

            String suppliedName = String.join(
                new List<String>{
                    firstName == null ? '' : firstName,
                    lastName == null ? '' : lastName
                },
                ' '
            ).trim();

            Case c = new Case(
                Origin       = 'Web',
                Status       = 'New',
                Priority     = 'Medium',
                Subject      = safeSubject,
                SuppliedName = suppliedName,
                SuppliedEmail = email,
                Product__c   = String.isBlank(product) ? null : product
            );
            insert c;

            // CaseNumber is auto-generated on insert; we must re-query to read it.
            Case requeried = [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Id = :c.Id
                LIMIT 1
            ];

            return new Map<String, String>{
                'caseId'     => requeried.Id,
                'caseNumber' => requeried.CaseNumber
            };
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create Case: ' + e.getMessage());
        }
    }

    /**
     * Returns the Case.Description if populated by GPTfy, or null while empty.
     * Polled by the LWC every 2.5 seconds for up to 90 seconds.
     *
     * Returns null on any error so that the LWC's polling loop continues
     * cleanly instead of surfacing a transient query failure to the user.
     */
    @AuraEnabled
    public static String getRecommendation(Id caseId) {
        try {
            if (caseId == null) {
                return null;
            }
            Case c = [
                SELECT Description, Summary__c, GPTfy_Question__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            // Summary__c holds the full HTML response for rich rendering in the LWC.
            // Fall back to Description (plain text) if Summary__c has not been written yet
            // (e.g. very old cases or error paths that only write Description).
            String content = String.isNotBlank(c.Summary__c) ? c.Summary__c : c.Description;
            if (String.isBlank(content) && String.isNotBlank(c.GPTfy_Question__c)
                && (c.GPTfy_Question__c.startsWith('[AGENT ERROR]')
                    || c.GPTfy_Question__c.startsWith('[EXCEPTION]'))) {
                content = c.GPTfy_Question__c;
            }
            if (String.isBlank(content)) {
                return null;
            }
            return sanitizeRecommendation(content);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Maps low-quality GPTfy/RAG outputs to a polite guest-facing message.
     * Returns null when the raw text is blank so polling can continue.
     */
    public static String sanitizeRecommendation(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        if (isLowQualityResponse(raw)) {
            return NO_ANSWER_MESSAGE;
        }
        return plainTextToHtml(raw);
    }

    /**
     * Converts plain-text line breaks to HTML so that
     * lightning-formatted-rich-text renders paragraphs and line breaks
     * instead of collapsing everything into a single wall of text.
     *
     * Already-HTML input (starts with '<') is returned unchanged so that
     * future agent prompts that emit HTML directly continue to work.
     *
     * When the agent returns everything as one long paragraph with no newlines,
     * a heuristic splits on inline section headers of the form
     * ". Title Case Words:" so each section still gets its own paragraph.
     */
    @TestVisible
    private static String plainTextToHtml(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        // If the agent already returned HTML, clean up redundant blank lines between
        // block elements. white-space is an inherited CSS property; blank lines
        // between tags render as extra empty rows in lightning-formatted-rich-text
        // unless collapsed here.
        if (text.trim().startsWith('<')) {
            return text.replaceAll('>[ \\t]*\\n{2,}[ \\t]*<', '>\n<');
        }
        // Normalise Windows-style line endings.
        String normalised = text.replace('\r\n', '\n').replace('\r', '\n');
        // When the agent emits no newlines at all, apply a heuristic to split
        // on inline section headers: a sentence boundary (". ") followed by
        // one or more title-cased words then a colon (e.g. ". Token Generation:").
        // We insert a double newline before each such header so the paragraph
        // splitter below turns them into separate <p> blocks.
        if (!normalised.contains('\n')) {
            normalised = normalised.replaceAll(
                '\\.\\s+(?=[A-Z][a-zA-Z]+(\\s+[A-Z][a-zA-Z]+){0,4}:)',
                '.\n\n'
            );
        }
        // Split on blank lines (two or more consecutive newlines) into paragraphs.
        List<String> paragraphs = normalised.split('\\n{2,}');
        List<String> htmlParagraphs = new List<String>();
        for (String para : paragraphs) {
            String trimmed = para.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            // Convert **bold** markdown to <strong> so lightning-formatted-rich-text renders it.
            String converted = trimmed.replaceAll('\\*\\*(.+?)\\*\\*', '<strong>$1</strong>');
            // Within a paragraph, single newlines become <br/> so list items and steps
            // each appear on their own line instead of collapsing into a wall of text.
            String withBreaks = converted.replace('\n', '<br/>');
            htmlParagraphs.add('<p>' + withBreaks + '</p>');
        }
        return String.join(htmlParagraphs, '');
    }

    private static Boolean isLowQualityResponse(String text) {
        String normalized = text.toLowerCase().replaceAll('\\s+', ' ').trim();
        if (LOW_QUALITY_RESPONSES.contains(normalized)) {
            return true;
        }
        // Always check LOW_QUALITY_CONTAINS regardless of length —
        // fallback messages from the agent system prompt can be long sentences.
        for (String fragment : LOW_QUALITY_CONTAINS) {
            if (normalized.contains(fragment)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Called when the guest clicks "Yes, resolved".
     *
     * The Salesforce Guest User License does NOT permit "Edit Cases", so we
     * cannot `update` the Case directly from this transaction (the restriction
     * is enforced below the sharing layer and `without sharing` does not bypass
     * it). Instead, we publish a Case_Resolved__e Platform Event; the
     * subscriber (CaseResolvedTrigger) runs as the Automated Process user and
     * is permitted to flip Status='Closed' and copy the AI answer into
     * Case.Resolution__c.
     *
     * Delivery is fire-and-forget from the guest's perspective: the event is
     * persisted to the bus after this transaction commits, and the trigger
     * fires within a second or two. The LWC's "Closing your case..." spinner
     * covers that window.
     */
    @AuraEnabled
    public static void resolveCase(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
        try {
            Case_Resolved__e evt = new Case_Resolved__e(
                CaseId__c = String.valueOf(caseId)
            );
            Database.SaveResult sr = EventBus.publish(evt);
            if (!sr.isSuccess()) {
                String firstError = sr.getErrors().isEmpty()
                    ? 'Unknown error publishing Case_Resolved__e'
                    : sr.getErrors()[0].getMessage();
                throw new AuraHandledException(
                    'Unable to close case: ' + firstError
                );
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to close case: ' + e.getMessage()
            );
        }
    }

    // ─── Question Clarification flow ─────────────────────────────────────────

    /**
     * Creates a Case in "clarification pending" mode and enqueues the
     * Question Clarifier prompt. The LWC then polls getClarification() until
     * Case.Clarification_Response__c is populated.
     *
     * Clarification_Pending__c = true prevents CaseAIAgentTrigger from firing
     * the AI resolution on insert — the AI fires only after the guest confirms.
     */
    @AuraEnabled
    public static Map<String, String> submitForClarification(
        String firstName,
        String lastName,
        String email,
        String subject,
        String product
    ) {
        try {
            if (String.isBlank(product)) {
                throw new AuraHandledException('Please select a product.');
            }

            String safeSubject = subject == null ? '' : subject;
            if (safeSubject.length() > SUBJECT_MAX_LENGTH) {
                safeSubject = safeSubject.substring(0, SUBJECT_MAX_LENGTH);
            }

            String suppliedName = String.join(
                new List<String>{
                    firstName == null ? '' : firstName,
                    lastName  == null ? '' : lastName
                },
                ' '
            ).trim();

            Case c = new Case(
                Origin                      = 'Web',
                Status                      = 'New',
                Priority                    = 'Medium',
                Subject                     = safeSubject,
                SuppliedName                = suppliedName,
                SuppliedEmail               = email,
                Product__c                  = product.trim(),
                AI_Clarification_Pending__c = true
            );
            insert c;

            Case requeried = [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Id = :c.Id
                LIMIT 1
            ];

            // Enqueue directly — Guest User has sufficient GPTfy package permissions
            // to invoke agents. Running as Automated Process (via Platform Event)
            // does NOT have the correct GPTfy agent context.
            System.enqueueJob(new CaseQuestionClarifierAgentService(
                requeried.Id,
                safeSubject,
                product.trim()
            ));

            return new Map<String, String>{
                'caseId'     => requeried.Id,
                'caseNumber' => requeried.CaseNumber
            };
        } catch (Exception e) {
            throw new AuraHandledException('Unable to submit question: ' + e.getMessage());
        }
    }

    /**
     * Polled by the LWC every 2.5 s during the CLARIFYING state.
     *
     * Strategy:
     *   1. Check Case.Intent_Analysis__c (written by QuestionClarifierAction).
     *      If it contains a non-empty cleanedQuestion, return it immediately.
     *   2. If Intent_Analysis__c is blank OR cleanedQuestion is empty, query
     *      ccai__AI_Response__c directly for the latest Question Clarifier
     *      response tied to this Case — this is the approach the user suggested
     *      to guarantee we get the actual prompt output regardless of the
     *      Prompt Action timing.
     *   3. Parse and cache the result in Intent_Analysis__c, then return it.
     *   4. Return null if no response has arrived yet (caller will keep polling).
     */
    @AuraEnabled
    public static String getClarification(Id caseId) {
        try {
            if (caseId == null) {
                return null;
            }

            // ── Step 1: return cached JSON only when MCQs are present ──
            Case c = [
                SELECT Intent_Analysis__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            if (QuestionClarifierAction.isSuccessfulClarificationJson(c.Intent_Analysis__c)) {
                return c.Intent_Analysis__c;
            }

            // ── Step 2: recover from GPTfy Security Audit (PII Added field) ──
            String auditText = QuestionClarifierAction.loadClarifierAuditText(caseId);
            String jsonResult = QuestionClarifierAction.parseClarifierResponse(auditText);
            if (String.isNotBlank(jsonResult)) {
                try {
                    update new Case(Id = caseId, Intent_Analysis__c = jsonResult);
                } catch (Exception dmlEx) {
                    System.debug(LoggingLevel.WARN,
                        'getClarification: could not cache JSON on Case ' + caseId +
                        ' — ' + dmlEx.getMessage());
                }
                return jsonResult;
            }

            // ── Step 3: return fallback JSON so LWC can show friendly warning ──
            if (String.isNotBlank(c.Intent_Analysis__c)) {
                try {
                    Map<String, Object> parsed =
                        (Map<String, Object>) JSON.deserializeUntyped(c.Intent_Analysis__c);
                    if (String.isNotBlank((String) parsed.get('cleanedQuestion'))) {
                        return c.Intent_Analysis__c;
                    }
                } catch (Exception parseEx) {
                    // ignore
                }
            }

            return null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'getClarification: exception for Case ' + caseId +
                ' — ' + e.getMessage());
            return null;
        }
    }

    /**
     * Called when the guest clicks "Confirm & Find Solution".
     * Publishes Case_Clarification_Confirmed__e; CaseConfirmTrigger then
     * updates Case.Subject and clears Clarification_Pending__c, which
     * causes CaseAIAgentTrigger (after update) to fire the AI resolution.
     *
     * @param caseId          The Case to update.
     * @param cleanedQuestion The confirmed question (may include appended MCQ context).
     */
    @AuraEnabled
    public static void confirmQuestion(Id caseId, String cleanedQuestion, String agentMessage) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
        try {
            // subjectQ — goes into Case.Subject (max 255 chars, Salesforce field limit)
            String subjectQ = String.isBlank(cleanedQuestion) ? '' : cleanedQuestion.trim();
            if (subjectQ.length() > SUBJECT_MAX_LENGTH) {
                subjectQ = subjectQ.substring(0, SUBJECT_MAX_LENGTH);
            }

            // agentQ — sent to the Case Resolve Agent. This is the FULL cleaned question
            // PLUS any MCQ context the user selected. No 255-char truncation here — the
            // agent benefits from every detail. Fall back to subjectQ if blank.
            String agentQ = String.isBlank(agentMessage) ? subjectQ : agentMessage.trim();

            // Enqueue directly — Guest User has sufficient GPTfy package permissions.
            System.enqueueJob(new CaseAgentResolutionService(caseId, agentQ));

            // Publish the event so CaseConfirmTrigger can update Case.Subject and clear
            // AI_Clarification_Pending__c in system context (Guest User cannot edit Cases).
            Case_Clarification_Confirmed__e evt = new Case_Clarification_Confirmed__e(
                CaseId__c          = String.valueOf(caseId),
                CleanedQuestion__c = subjectQ
            );
            Database.SaveResult sr = EventBus.publish(evt);
            if (!sr.isSuccess()) {
                String firstError = sr.getErrors().isEmpty()
                    ? 'Unknown error publishing Case_Clarification_Confirmed__e'
                    : sr.getErrors()[0].getMessage();
                throw new AuraHandledException('Unable to confirm question: ' + firstError);
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to confirm question: ' + e.getMessage());
        }
    }

    // ─── Portal session / profile prefill ─────────────────────────────────────

    /**
     * Returns the current Experience Cloud session context for the LWC.
     * Logged-in community members get profile name + contact fields for prefill.
     * Guest/public sessions return isGuest=true with no profile fields.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPortalUserContext() {
        String userType = UserInfo.getUserType();
        Boolean isGuest = userType == 'Guest';

        Map<String, String> result = new Map<String, String>{
            'userType'    => userType,
            'isGuest'     => String.valueOf(isGuest),
            'displayName' => isGuest ? '' : UserInfo.getName()
        };

        if (!isGuest) {
            User u = [
                SELECT FirstName, LastName, Email
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            result.put('firstName', u.FirstName == null ? '' : u.FirstName);
            result.put('lastName',  u.LastName  == null ? '' : u.LastName);
            result.put('email',     u.Email     == null ? '' : u.Email);
        }

        return result;
    }

    // ─── Product picklist ─────────────────────────────────────────────────────

    /**
     * Returns the active picklist values for Case.Product__c so the LWC can
     * render an up-to-date <select> without hard-coding values. Cacheable so
     * the wire adapter only hits the server once per session.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProductOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.DescribeFieldResult f = Case.Product__c.getDescribe();
        for (Schema.PicklistEntry e : f.getPicklistValues()) {
            if (e.isActive()) {
                options.add(new Map<String, String>{
                    'label' => e.getLabel(),
                    'value' => e.getValue()
                });
            }
        }
        return options;
    }
}
