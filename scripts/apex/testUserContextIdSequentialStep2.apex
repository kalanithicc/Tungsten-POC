/**
 * Step 2 — enqueue resolver after clarifier finished.
 * Set caseId from step 1 output.
 */
Id caseId = null; // REPLACE after step 1, or query latest marker case below

List<Case> cases = [
    SELECT Id, Subject, Intent_Analysis__c
    FROM Case
    WHERE Subject LIKE 'cursor-test-% sequential userContextId'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
if (!cases.isEmpty()) {
    caseId = cases[0].Id;
}

if (caseId == null) {
    System.debug('FAIL: no sequential test case found');
} else {
    String question = 'How do I clear browser cache when the login page shows a blank screen?';
    System.enqueueJob(new CaseAgentResolutionService(caseId, question));
    System.debug('Step 2: enqueued resolver for ' + caseId);
    System.debug('After ~90s run testUserContextIdSequentialStep3.apex');
}
