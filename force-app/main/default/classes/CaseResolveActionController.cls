/**
 * Apex controller for the caseResolveAction LWC quick action.
 *
 * Runs WITH SHARING because this is an authenticated agent-facing path
 * on the internal Case record page.
 *
 * Behaviour on Save:
 *   1. Updates Case.Resolution__c with the agent-typed text and flips
 *      Status to 'Closed' in one DML.
 *   2. When createKb = true, enqueues KbMatchAgentService (Queueable) which
 *      uses the KB_Match_Agent (RAG) to decide: if a similar article already
 *      exists it stops; otherwise it invokes the GPTfy KB Creation Prompt and
 *      — via KbArticleBuilderAction — creates a new Knowledge article.
 *   3. Returns a SaveResult so the LWC can render a precise toast.
 *
 * KB creation is fully asynchronous and best-effort. If the Queueable fails,
 * the case is already closed and the resolution is saved.
 */
public with sharing class CaseResolveActionController {

    /**
     * Result envelope returned to the LWC.
     */
    public class SaveResult {
        @AuraEnabled public Boolean caseClosed;
        @AuraEnabled public Boolean articleQueued;
        @AuraEnabled public String  articleWarning;
    }

    /**
     * Saves the agent-authored resolution text, closes the Case, and
     * optionally enqueues async KB article generation.
     *
     * @param caseId          The Id of the Case to resolve. Required.
     * @param resolutionText  Plain-text resolution. Required, may not be blank.
     * @param createKb        When true, enqueues KbCreationService to generate
     *                        6 draft Knowledge articles via the KB Creation Prompt.
     *
     * @throws AuraHandledException if inputs are missing or the Case DML fails.
     */
    @AuraEnabled
    public static SaveResult saveResolution(Id caseId, String resolutionText, Boolean createKb) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
        if (String.isBlank(resolutionText)) {
            throw new AuraHandledException('Resolution text is required.');
        }

        Case existing = [
            SELECT Subject, GPTfy_Question__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        String questionText = CaseDescriptionFormatter.resolveQuestionText(existing);

        Case toUpdate = new Case(
            Id            = caseId,
            Resolution__c = resolutionText,
            Status        = 'Closed',
            Description   = CaseDescriptionFormatter.formatOnClose(existing, resolutionText)
        );

        try {
            update toUpdate;
        } catch (DmlException e) {
            String detail = e.getNumDml() > 0
                ? e.getDmlMessage(0)
                : e.getMessage();
            throw new AuraHandledException('Unable to save resolution: ' + detail);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save resolution: ' + e.getMessage());
        }

        SaveResult result = new SaveResult();
        result.caseClosed = true;

        if (createKb == true) {
            System.enqueueJob(new KbMatchAgentService(caseId));
            result.articleQueued = true;
        }

        return result;
    }
}
