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

            ccai.AIAgenticWebService.ResponseWrapper response = ccai.AIAgenticUtility.invokeAgent(request);

            if (response != null) {
                update new Case(
                    Id          = caseId,
                    Description = stripHtml(response.responseBody)
                );
            } else {
                String reason = response != null ? response.status : 'null response';
                String errorBody = response != null ? response.responseBody : '';
                writeErrorToCase(
                    '[AGENT ERROR] Status: ' + reason +
                    (String.isNotBlank(errorBody) ? ' | Detail: ' + errorBody : '')
                );
            }

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

    private static String stripHtml(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        String stripped = raw.stripHtmlTags();
        // Collapse excessive blank lines left by block-level tags
        stripped = stripped.replaceAll('(\r?\n){3,}', '\n\n').trim();
        return stripped;
    }

    private void writeErrorToCase(String errorMessage) {
        try {
            update new Case(
                Id          = caseId,
                Description = errorMessage
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CaseAgentResolutionService.writeErrorToCase failed for Case ' +
                caseId + ' — ' + ex.getMessage());
        }
    }
}
