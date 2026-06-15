/**
 * Production clarifier service — uses a GPTfy Agent with RAG access instead
 * of a blind prompt, so the clarification questions are informed by what the
 * Knowledge Base actually contains (or lacks) for the submitted question.
 *
 * Flow:
 *   1. Guest submits question → CaseResolutionController.submitForClarification()
 *      creates Case with AI_Clarification_Pending__c = true and enqueues this job.
 *   2. This job calls the GPTfy "Question Clarifier Agent" via
 *      ccai.AIAgenticUtility.invokeAgent(). The agent:
 *        a. Searches the vector store with the raw question.
 *        b. Rewrites the question in professional English.
 *        c. Generates 0–3 clarification questions based on KB gaps — NOT generic
 *           "which version?" questions, but questions the KB search revealed matter.
 *   3. If invokeAgent returns an empty body (common for community users), recover
 *      the answer from the GPTfy Security Audit PII Added field instead.
 *   4. QuestionClarifierAction parses the text and writes JSON to Intent_Analysis__c.
 *   5. CaseResolutionController.getClarification() returns the JSON to the LWC.
 *
 * GPTfy Agent developer name: Question_Clarifier_Agent
 */
public without sharing class CaseQuestionClarifierAgentService
    implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String AGENT_DEVELOPER_NAME = 'Question_Clarifier_Agent';

    private final Id     caseId;
    private final String rawQuestion;
    private final String product;

    public CaseQuestionClarifierAgentService(Id caseId, String rawQuestion, String product) {
        this.caseId      = caseId;
        this.rawQuestion = rawQuestion;
        this.product     = product;
    }

    public void execute(QueueableContext ctx) {
        System.debug(LoggingLevel.INFO,
            'CaseQuestionClarifierAgentService: starting for Case ' + caseId);
        try {
            String effectiveProduct = product;
            if (String.isBlank(effectiveProduct)) {
                Case caseRow = [
                    SELECT Product__c
                    FROM Case
                    WHERE Id = :caseId
                    LIMIT 1
                ];
                effectiveProduct = caseRow.Product__c;
            }

            String userMessage = buildUserMessage(rawQuestion, effectiveProduct);

            ccai.AIAgenticWebService.RequestWrapper request =
                new ccai.AIAgenticWebService.RequestWrapper();
            request.agentName     = AGENT_DEVELOPER_NAME;
            request.userMessage   = userMessage;
            request.userContextId = String.valueOf(caseId);

            ccai.AIAgenticWebService.ResponseWrapper response =
                ccai.AIAgenticUtility.invokeAgent(request);

            String responseBody = response == null ? null : response.responseBody;
            if (writeClarificationFromRaw(responseBody)) {
                return;
            }

            String auditText = QuestionClarifierAction.loadClarifierAuditText(caseId);
            if (writeClarificationFromRaw(auditText)) {
                System.debug(LoggingLevel.INFO,
                    'CaseQuestionClarifierAgentService: recovered clarifier output from Security Audit for Case '
                    + caseId);
                return;
            }

            if (response == null) {
                writeFallbackWithError(
                    'invokeAgent returned null (running user: ' + runningUserContext() +
                    '). Check GPTfy permission sets for this user.');
                return;
            }

            if (String.isBlank(responseBody)) {
                writeFallbackWithError(
                    'invokeAgent returned empty body | status=' + response.status +
                    ' | running user: ' + runningUserContext());
                return;
            }

            writeFallbackWithError(
                'Could not parse clarifier agent response (running user: ' +
                runningUserContext() + ')');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CaseQuestionClarifierAgentService: exception for Case ' + caseId +
                ' — ' + e.getTypeName() + ': ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString());
            writeFallbackWithError(e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @TestVisible
    private Boolean writeClarificationFromRaw(String raw) {
        String jsonResult = QuestionClarifierAction.parseClarifierResponse(raw);
        if (String.isBlank(jsonResult)) {
            return false;
        }
        update new Case(Id = caseId, Intent_Analysis__c = jsonResult);
        System.debug(LoggingLevel.INFO,
            'CaseQuestionClarifierAgentService: clarification JSON written to Case ' + caseId);
        return true;
    }

    @TestVisible
    static String buildUserMessage(String rawQuestion, String product) {
        String cleanQ = String.isBlank(rawQuestion) ? '' : rawQuestion.trim();
        if (String.isNotBlank(product)) {
            return 'Product: ' + product + '\nQuestion: ' + cleanQ;
        }
        return cleanQ;
    }

    @TestVisible
    private static String runningUserContext() {
        return UserInfo.getUserType() + ' / ' + UserInfo.getUserName();
    }

    private void writeFallbackWithError(String errorDetail) {
        try {
            Case c = [SELECT Subject FROM Case WHERE Id = :caseId LIMIT 1];
            Map<String, Object> payload = new Map<String, Object>{
                'cleanedQuestion' => String.isBlank(c.Subject) ? '' : c.Subject,
                'clarifications'  => new List<Object>()
            };
            if (String.isNotBlank(errorDetail)) {
                payload.put('_error', errorDetail);
            }
            update new Case(Id = caseId, Intent_Analysis__c = JSON.serialize(payload));
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CaseQuestionClarifierAgentService.writeFallback failed for Case ' +
                caseId + ' — ' + ex.getMessage());
        }
    }
}
