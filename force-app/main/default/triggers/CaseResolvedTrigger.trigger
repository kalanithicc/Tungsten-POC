/**
 * Subscriber for the Case_Resolved__e Platform Event.
 *
 * Runs as the Automated Process user (system context), which - unlike the
 * Guest User that publishes the event - is permitted to update Case records.
 * For each event in the batch we flip Status to 'Closed', copy the
 * GPTfy-generated answer into Case.Resolution__c, and format Case.Description
 * with the clarified question plus resolution (Checkpoint 3).
 *
 * Uses Database.update(..., false) (allOrNone = false) so a single bad row
 * never aborts delivery for siblings, nor causes the platform event bus to
 * retry the entire batch up to 9 times.
 */
trigger CaseResolvedTrigger on Case_Resolved__e (after insert) {

    Set<Id> caseIds = new Set<Id>();
    for (Case_Resolved__e evt : Trigger.new) {
        if (String.isNotBlank(evt.CaseId__c)) {
            try {
                caseIds.add((Id) evt.CaseId__c);
            } catch (System.StringException ignored) {
                System.debug(LoggingLevel.WARN,
                    'CaseResolvedTrigger: skipping invalid CaseId__c value: ' + evt.CaseId__c);
            }
        }
    }

    if (caseIds.isEmpty()) {
        return;
    }

    List<Case> toUpdate = new List<Case>();
    for (Case existing : [
        SELECT Id, Status, Subject, GPTfy_Question__c, Description, Summary__c, Resolution__c
        FROM Case
        WHERE Id IN :caseIds
    ]) {
        if (existing.Status == 'Closed') {
            continue;
        }
        // Prefer Summary__c (HTML) as the resolution text.
        // It was written by CaseAgentResolutionService alongside the plain-text
        // Description and already has the correct HTML structure for both the
        // case-detail page and the HTML email we send.
        // Fall back to sanitizing Description (which converts plain text to HTML)
        // for older cases that predate the dual-field strategy.
        String resolutionText;
        if (String.isNotBlank(existing.Summary__c)) {
            resolutionText = existing.Summary__c;
        } else {
            resolutionText = CaseResolutionController.sanitizeRecommendation(
                existing.Description
            );
        }
        toUpdate.add(new Case(
            Id            = existing.Id,
            Status        = 'Closed',
            Resolution__c = resolutionText == null ? '' : resolutionText,
            Description   = CaseDescriptionFormatter.formatOnClose(existing)
        ));
    }

    if (toUpdate.isEmpty()) {
        return;
    }

    Database.SaveResult[] results = Database.update(toUpdate, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
            for (Database.Error err : results[i].getErrors()) {
                System.debug(LoggingLevel.ERROR,
                    'CaseResolvedTrigger: failed to close Case ' + toUpdate[i].Id +
                    ' - ' + err.getStatusCode() + ': ' + err.getMessage());
            }
        }
    }
}