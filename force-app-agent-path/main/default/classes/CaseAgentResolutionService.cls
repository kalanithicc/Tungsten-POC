/**
 * PATH 2 — GPTfy Agent / Vector Store resolution service.
 *
 * Invoked asynchronously by CaseAIAgentTrigger whenever a Case with
 * Origin='Web' is created. Calls the GPTfy "Case Resolve Agent" via the
 * ccai.AIAgenticUtility managed-package API, then writes the answer into
 * Case.Description so the existing LWC polling loop (caseResolutionAssistant)
 * can display it to the guest user — exactly the same handoff used by PATH 1.
 *
 * GPTfy Agent: Case Resolve Agent (a02dN00000BTwgbQAD)
 * API class:   ccai.AIAgenticUtility.invokeAgent()
 */
public without sharing class CaseAgentResolutionService implements Queueable, Database.AllowsCallouts {

    private static final String AGENT_DEVELOPER_NAME = 'Case_Resolve_Agent';

    private final Id     caseId;
    private final String subject;

    public CaseAgentResolutionService(Id caseId, String subject) {
        this.caseId  = caseId;
        this.subject = subject;
    }

    public void execute(QueueableContext ctx) {
        try {
            ccai.AIAgenticWebService.RequestWrapper request = new ccai.AIAgenticWebService.RequestWrapper();
            request.agentName   = AGENT_DEVELOPER_NAME;
            request.userMessage = cleanSubject(subject);

            ccai.AIAgenticWebService.ResponseWrapper response =
                ccai.AIAgenticUtility.invokeAgent(request);

            if (response == null) {
                writeErrorToCase(
                    '[AGENT ERROR] invokeAgent returned null | running user: ' +
                    runningUserContext() +
                    '. Check GPTfy permission sets for this user.');
                return;
            }

            String rawResponse = response.responseBody;
            if (String.isBlank(rawResponse)) {
                writeErrorToCase(
                    '[AGENT ERROR] invokeAgent returned empty body | status=' +
                    response.status + ' | running user: ' + runningUserContext());
                return;
            }

            // Dual-field strategy:
            //   Summary__c  — full HTML response for rich rendering in the LWC.
            //   Description — clean plain-text for email notifications and case views.
            String htmlContent  = stripKbRefsBlock(rawResponse);
            String plainContent = htmlToPlainText(htmlContent);
            String agentQuestion = cleanSubject(subject);

            update new Case(
                Id                = caseId,
                Summary__c        = htmlContent,
                GPTfy_Question__c = agentQuestion,
                Description       = plainContent
            );

        } catch (Exception e) {
            writeErrorToCase(
                '[EXCEPTION] ' + e.getTypeName() + ': ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString()
            );
        }
    }

    private static String cleanSubject(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        // Remove surrounding quotes that users sometimes paste from chat/docs,
        // and strip leading/trailing whitespace — both hurt RAG similarity scoring.
        return raw.replaceAll('^[\\s"\']+|[\\s"\']+$', '').trim();
    }

    /**
     * Converts an HTML response to clean, readable plain text for use in
     * Case.Description (email bodies, case views, reports).
     *
     * Strategy:
     *   - Block-level closing tags  → one or two newlines
     *   - List items (<li>)         → "  - " bullet prefix
     *   - <br/>                     → single newline
     *   - All remaining tags        → stripped
     *   - 3+ consecutive newlines   → collapsed to 2
     */
    public static String htmlToPlainText(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        if (!raw.contains('<')) {
            return raw.replaceAll('(\r?\n){3,}', '\n\n').trim();
        }
        String t = raw
            // Headings get a blank line before and after
            .replaceAll('(?i)<h[1-6][^>]*>', '\n\n')
            .replaceAll('(?i)</h[1-6]>', '\n\n')
            // Paragraphs and divs end with a blank line
            .replaceAll('(?i)</p>', '\n\n')
            .replaceAll('(?i)</div>', '\n')
            // List items become "  - " bullets
            .replaceAll('(?i)<li[^>]*>', '  - ')
            .replaceAll('(?i)</li>', '\n')
            // Lists add a trailing blank line
            .replaceAll('(?i)</ul>', '\n')
            .replaceAll('(?i)</ol>', '\n')
            // Line breaks
            .replaceAll('(?i)<br\\s*/?>', '\n')
            // Strip all remaining tags WITHOUT collapsing whitespace/newlines.
            // Salesforce's stripHtmlTags() normalises runs of whitespace which
            // destroys the \n characters we inserted above, so we use a regex
            // strip instead — safe for the straightforward HTML an AI agent emits.
            .replaceAll('<[^>]+>', '')
            // Decode the handful of HTML entities that typically appear in AI output
            .replace('&amp;',  '&')
            .replace('&lt;',   '<')
            .replace('&gt;',   '>')
            .replace('&nbsp;', ' ')
            .replace('&#39;',  '\'')
            .replace('&quot;', '"')
            // Collapse excessive blank lines
            .replaceAll('(\r?\n){3,}', '\n\n')
            .trim();
        return t;
    }

    /**
     * Removes the KB_REFS_START...KB_REFS_END metadata block from the agent response
     * so the customer-visible fields (Summary__c, Description) contain only the answer.
     */
    public static String stripKbRefsBlock(String raw) {
        if (String.isBlank(raw)) return raw;
        return raw.replaceAll('(?is)\\s*KB_REFS_START.*?KB_REFS_END\\s*', '\n').trim();
    }

    @TestVisible
    private static String runningUserContext() {
        return UserInfo.getUserType() + ' / ' + UserInfo.getUserName();
    }

    private void writeErrorToCase(String errorMessage) {
        String msg = String.isBlank(errorMessage) ? '[AGENT ERROR] Unknown error' : errorMessage;
        if (msg.length() > 32000) {
            msg = msg.substring(0, 32000);
        }

        List<String> failures = new List<String>();

        try {
            update new Case(Id = caseId, Description = msg, Summary__c = null);
            return;
        } catch (Exception ex) {
            failures.add('Description: ' + ex.getMessage());
        }

        try {
            update new Case(
                Id         = caseId,
                Summary__c = '<p>' + msg.replace('<', '&lt;').replace('>', '&gt;') + '</p>'
            );
            return;
        } catch (Exception ex) {
            failures.add('Summary__c: ' + ex.getMessage());
        }

        try {
            update new Case(Id = caseId, GPTfy_Question__c = msg);
            return;
        } catch (Exception ex) {
            failures.add('GPTfy_Question__c: ' + ex.getMessage());
        }

        System.debug(LoggingLevel.ERROR,
            'CaseAgentResolutionService.writeErrorToCase all attempts failed for Case ' +
            caseId + ' — ' + String.join(failures, ' | '));
    }
}
