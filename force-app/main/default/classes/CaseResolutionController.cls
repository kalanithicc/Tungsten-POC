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
     * @param product    Optional product picklist value (stored on Product__c).
     *                   Pass null/blank if the guest did not pick one; the GPTfy
     *                   prompt will then search KB across all products.
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
                SELECT Description
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            if (String.isBlank(c.Description)) {
                return null;
            }
            return sanitizeRecommendation(c.Description);
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
        String trimmed = raw.trim();
        if (isLowQualityResponse(trimmed)) {
            return NO_ANSWER_MESSAGE;
        }
        return trimmed;
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
