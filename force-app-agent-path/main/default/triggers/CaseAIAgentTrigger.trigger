/**
 * PATH 2 — GPTfy Agent / Vector Store path (legacy direct-resolve gate).
 *
 * Fires after a new Case with Origin='Web' is inserted when the case does NOT
 * go through the clarification flow (AI_Clarification_Pending__c != true).
 *
 * The primary portal path uses submitForClarification → confirmQuestion, which
 * enqueues CaseAgentResolutionService directly in the guest session.
 *
 * Deactivate Case_Resolution_RTF (legacy Flow prompt path). Never run both
 * Case_Resolution_RTF and this trigger for the same case pattern.
 */
trigger CaseAIAgentTrigger on Case (after insert) {
    for (Case c : Trigger.new) {
        if (c.Origin != 'Web' || String.isBlank(c.Subject)) {
            continue;
        }

        // Only fire on INSERT for cases that skip the clarification flow
        // (i.e. AI_Clarification_Pending__c is false on creation).
        //
        // For cases going through the clarification flow, the guest confirms via
        // CaseResolutionController.confirmQuestion(), which enqueues
        // CaseAgentResolutionService directly — in the LWC user's session context
        // rather than the Automated Process context that Platform Event triggers run in.
        // GPTfy agent invocations must NOT run as Automated Process.
        if (c.AI_Clarification_Pending__c != true) {
            System.enqueueJob(new CaseAgentResolutionService(c.Id, c.Subject));
        }
    }
}
