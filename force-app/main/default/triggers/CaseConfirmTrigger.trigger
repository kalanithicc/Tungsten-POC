/**
 * Handles Case_Clarification_Confirmed__e platform events published by
 * CaseResolutionController.confirmQuestion() when the guest confirms the
 * clarified question.
 *
 * Runs as the Automated Process user (system context) which has permission
 * to update Cases — the Guest User License forbids direct Case updates.
 *
 * Steps:
 *   1. Build the final question subject (cleaned question + MCQ context)
 *   2. Update Case.Subject with the finalised question
 *   3. Clear Case.Clarification_Pending__c → false
 *      This update causes CaseAIAgentTrigger (after update) to detect the
 *      flag change and enqueue the AI resolution service.
 */
trigger CaseConfirmTrigger on Case_Clarification_Confirmed__e (after insert) {
    List<Case> toUpdate = new List<Case>();

    for (Case_Clarification_Confirmed__e evt : Trigger.new) {
        if (String.isBlank(evt.CaseId__c)) {
            continue;
        }

        Id caseId = null;
        try {
            caseId = Id.valueOf(evt.CaseId__c);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CaseConfirmTrigger: invalid CaseId "' + evt.CaseId__c + '" — skipping.');
            continue;
        }

        String finalSubject = String.isBlank(evt.CleanedQuestion__c)
            ? 'Support request'
            : evt.CleanedQuestion__c.trim();

        if (finalSubject.length() > 255) {
            finalSubject = finalSubject.substring(0, 255);
        }

        toUpdate.add(new Case(
            Id                        = caseId,
            Subject                   = finalSubject,
            AI_Clarification_Pending__c = false,
            Intent_Analysis__c        = null
        ));
    }

    if (!toUpdate.isEmpty()) {
        try {
            update toUpdate;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'CaseConfirmTrigger: DML update failed — ' + e.getMessage());
        }
    }
}
