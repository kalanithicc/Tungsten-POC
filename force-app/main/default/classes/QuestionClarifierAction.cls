/**
 * GPTfy Prompt Action — invoked automatically by GPTfy after the Question
 * Clarifier Prompt generates its response.
 *
 * Implements ccai.AIPromptActionInterface so GPTfy can call this class as
 * the configured Prompt Action on the Question Clarifier Prompt
 * (promptRequestId = c9705af0cf39def9e8f0cbb915cb525071754).
 *
 * GPTfy calls invokeApex() with the ccai__AI_Response__c record after the
 * LLM returns its output. This method:
 *   1. Parses the structured prompt response text
 *   2. Extracts the cleaned question and 0-3 MCQ clarification questions
 *   3. Serialises the result as JSON into Case.Clarification_Response__c
 *      so the LWC polling loop can display the clarification UI
 *
 * Expected prompt response format:
 *   Cleaned Question: [rewritten question here]
 *
 *   Clarification 1: [question text]
 *   Options: A) [opt] | B) [opt] | C) [opt] | D) [opt]
 *
 *   Clarification 2: [question text]
 *   Options: A) [opt] | B) [opt] | C) [opt]
 */
global without sharing class QuestionClarifierAction implements ccai.AIPromptActionInterface {

    @TestVisible
    private static final String CLARIFIER_AGENT_AUDIT_NAME = 'Question Clarifier Agent';

    // ─── Interface entry point ────────────────────────────────────────────────

    global void invokeApex(ccai__AI_Response__c response) {
        String responseText = resolveGptfyResponseText(
            response?.ccai__AI_Processed_Data_PII_Added__c,
            response?.ccai__Message__c,
            response?.ccai__Data_Original__c
        );

        if (String.isBlank(responseText)) {
            System.debug(LoggingLevel.WARN,
                'QuestionClarifierAction: blank/null AI response — skipping.');
            return;
        }

        if (responseText.startsWith('{') && responseText.contains('"error"')) {
            System.debug(LoggingLevel.WARN,
                'QuestionClarifierAction: GPTfy error response — skipping. Body: '
                + responseText.abbreviate(300));
            return;
        }

        Id caseId = null;
        if (String.isNotBlank(response.ccai__Record_Id__c)) {
            try {
                caseId = Id.valueOf(response.ccai__Record_Id__c);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'QuestionClarifierAction: invalid Record Id "' +
                    response.ccai__Record_Id__c + '"');
                return;
            }
        }

        if (caseId == null) {
            System.debug(LoggingLevel.WARN,
                'QuestionClarifierAction: no Case Id on response — skipping.');
            return;
        }

        String jsonResult = parseClarifierResponse(responseText);
        if (String.isBlank(jsonResult)) {
            System.debug(LoggingLevel.WARN,
                'QuestionClarifierAction: could not parse response into JSON — skipping.');
            return;
        }

        try {
            update new Case(
                Id                     = caseId,
                Intent_Analysis__c     = jsonResult
            );
            System.debug(LoggingLevel.INFO,
                'QuestionClarifierAction: wrote clarification JSON to Case ' + caseId);
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'QuestionClarifierAction: DML failed for Case ' + caseId +
                ' — ' + e.getMessage());
        }
    }

    // ─── GPTfy Security Audit helpers ───────────────────────────────────────

    /**
     * Reads the latest Question Clarifier Agent Security Audit for this Case.
     * invokeAgent() often returns an empty body for community users even though
     * GPTfy writes the real answer to ccai__AI_Processed_Data_PII_Added__c.
     */
    @TestVisible
    public static String loadClarifierAuditText(Id caseId) {
        if (caseId == null) {
            return null;
        }

        String contextId = String.valueOf(caseId);

        List<ccai__AI_Response__c> responses = [
            SELECT ccai__AI_Processed_Data_PII_Added__c,
                   ccai__Message__c,
                   ccai__Data_Original__c
            FROM ccai__AI_Response__c
            WHERE ccai__User_Context_Id__c = :contextId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (responses.isEmpty()) {
            Case c = [
                SELECT CreatedDate
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            Datetime windowStart = c.CreatedDate.addSeconds(-10);

            responses = [
                SELECT ccai__AI_Processed_Data_PII_Added__c,
                       ccai__Message__c,
                       ccai__Data_Original__c
                FROM ccai__AI_Response__c
                WHERE ccai__Agent_Name__c = :CLARIFIER_AGENT_AUDIT_NAME
                  AND CreatedById          = :UserInfo.getUserId()
                  AND CreatedDate          >= :windowStart
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }

        if (responses.isEmpty()) {
            return null;
        }

        ccai__AI_Response__c row = responses[0];
        return resolveGptfyResponseText(
            row.ccai__AI_Processed_Data_PII_Added__c,
            row.ccai__Message__c,
            row.ccai__Data_Original__c
        );
    }

    /**
     * Unwraps GPTfy agent Security Audit fields into plain/HTML agent text,
     * normalises it, and returns Intent_Analysis__c JSON.
     */
    @TestVisible
    public static String parseClarifierResponse(String raw) {
        String text = extractMessageFromPiiAdded(raw);
        if (String.isBlank(text)) {
            text = raw;
        }
        if (String.isBlank(text)) {
            return null;
        }
        text = normalizeResponseBody(text);
        return buildJson(text);
    }

    @TestVisible
    public static String resolveGptfyResponseText(
        String piiAdded,
        String message,
        String dataOriginal
    ) {
        String text = extractMessageFromPiiAdded(piiAdded);
        if (String.isNotBlank(text)) {
            return text;
        }
        if (String.isNotBlank(message)) {
            return message;
        }
        return dataOriginal;
    }

    /**
     * GPTfy agent audits store the rendered answer inside
     * ccai__AI_Processed_Data_PII_Added__c as JSON:
     *   {"messages":["{\"message\":\"<p>Cleaned Question: ...</p>\", ...}"],"fncDetails":[]}
     */
    @TestVisible
    public static String extractMessageFromPiiAdded(String piiField) {
        if (String.isBlank(piiField)) {
            return null;
        }
        String trimmed = piiField.trim();
        if (!trimmed.startsWith('{')) {
            return trimmed;
        }

        try {
            Map<String, Object> root =
                (Map<String, Object>) JSON.deserializeUntyped(trimmed);
            List<Object> messages = (List<Object>) root.get('messages');
            if (messages == null || messages.isEmpty()) {
                return null;
            }

            String first = String.valueOf(messages[0]).trim();
            if (first.startsWith('{')) {
                Map<String, Object> msgObj =
                    (Map<String, Object>) JSON.deserializeUntyped(first);
                Object messageVal = msgObj.get('message');
                return messageVal == null ? null : String.valueOf(messageVal);
            }
            return first;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'QuestionClarifierAction.extractMessageFromPiiAdded failed — '
                + e.getMessage());
            return null;
        }
    }

    @TestVisible
    public static String normalizeResponseBody(String responseBody) {
        if (String.isBlank(responseBody)) {
            return responseBody;
        }

        if (responseBody.contains('<')) {
            responseBody = responseBody
                .replaceAll('(?i)<br\\s*/?>', '\n')
                .replaceAll('(?i)</p>', '\n')
                .replaceAll('(?i)</div>', '\n')
                .replaceAll('(?i)</li>', '\n')
                .stripHtmlTags();
        }

        return responseBody
            .replaceAll('(?i)(?<!\\n)(Clarification\\s+\\d+:)', '\n$1')
            .replaceAll('(?i)(?<!\\n)(Options:)', '\nOptions:')
            .replaceAll('\\*\\*', '')
            .replaceAll('(\r?\n){3,}', '\n\n')
            .trim();
    }

    // ─── Parser ───────────────────────────────────────────────────────────────

    @TestVisible
    public static Boolean isSuccessfulClarificationJson(String clarificationJson) {
        if (String.isBlank(clarificationJson)) {
            return false;
        }
        try {
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(clarificationJson);
            if (parsed.containsKey('_error')) {
                return false;
            }
            List<Object> clarifications = (List<Object>) parsed.get('clarifications');
            return clarifications != null && !clarifications.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    @TestVisible
    global static String buildJson(String responseText) {
        String cleanedQuestion = extractCleanedQuestion(responseText);
        if (String.isBlank(cleanedQuestion)) {
            return null;
        }

        List<Object> clarifications = extractClarifications(responseText);

        Map<String, Object> result = new Map<String, Object>{
            'cleanedQuestion'  => cleanedQuestion,
            'clarifications'   => clarifications
        };

        return JSON.serialize(result);
    }

    @TestVisible
    static String extractCleanedQuestion(String text) {
        // Match "Cleaned Question:" then capture everything to end of line.
        // ** markdown bold markers are stripped upstream (CaseQuestionClarifierAgentService)
        // before this method is called. Use greedy (.+) so the full line content
        // is captured even with special characters (curly quotes, dashes, etc.).
        // Strip any trailing \r from Windows-style line endings.
        Matcher m = Pattern.compile(
            '(?im)^Cleaned Question:\\s*(.+)$'
        ).matcher(text);
        if (m.find()) {
            return m.group(1).replaceAll('\\r$', '').trim();
        }
        return null;
    }

    @TestVisible
    static List<Object> extractClarifications(String text) {
        List<Object> result = new List<Object>();

        // Match each "Clarification N: ..." block followed by "Options: ..."
        // ** markdown bold markers are stripped upstream before this method is called.
        // Use greedy capture and strip trailing \r from Windows line endings.
        Matcher m = Pattern.compile(
            '(?im)^Clarification \\d+:\\s*(.+)\\r?\\nOptions:\\s*(.+)$'
        ).matcher(text);

        while (m.find() && result.size() < 3) {
            String question   = m.group(1).replaceAll('\\r$', '').trim();
            String optionsRaw = m.group(2).replaceAll('\\r$', '').trim();

            List<String> options = parseOptions(optionsRaw);
            if (options.isEmpty()) {
                continue;
            }

            result.add(new Map<String, Object>{
                'question' => question,
                'options'  => options
            });
        }

        return result;
    }

    // Parse options from either of these agent-returned formats:
    //   "A) opt1 | B) opt2 | C) opt3"          (pipe-separated, standard)
    //   "A) opt1 &#124; B) opt2 &#124; C) opt3" (HTML-entity pipe)
    //   "A) opt1 B) opt2 C) opt3"               (no separator — agent omitted pipes)
    @TestVisible
    static List<String> parseOptions(String raw) {
        List<String> options = new List<String>();
        if (String.isBlank(raw)) {
            return options;
        }

        // Normalise HTML pipe entity so we always work with literal |
        String normalised = raw.replace('&#124;', '|').replace('&amp;#124;', '|');

        List<String> parts;
        if (normalised.contains('|')) {
            // Standard pipe-separated: "A) opt | B) opt | C) opt"
            parts = normalised.split('\\|');
        } else {
            // No pipe separator: "A) opt B) opt C) opt"
            // Split just before each uppercase letter followed by ) and a space.
            // The lookAhead ensures we don't split inside option text that happens
            // to contain things like "Wi-Fi" or other letter+paren patterns.
            parts = normalised.split('\\s+(?=[A-Z]\\)\\s)');
        }

        for (String part : parts) {
            // Strip leading letter-paren prefix: "A) ", "B) ", etc.
            String cleaned = part.trim().replaceAll('^[A-Za-z]\\)\\s*', '');
            if (String.isNotBlank(cleaned)) {
                options.add(cleaned.trim());
            }
        }
        return options;
    }
}
