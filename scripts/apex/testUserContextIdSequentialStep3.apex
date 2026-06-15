List<Case> cases = [
    SELECT Id, Subject
    FROM Case
    WHERE Subject LIKE 'cursor-test-% sequential userContextId'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
if (cases.isEmpty()) {
    System.debug('FAIL: no case');
} else {
    System.enqueueJob(new KbMatchAgentService(cases[0].Id));
    System.debug('Step 3: enqueued KB Match for ' + cases[0].Id);
    System.debug('After ~90s run testUserContextIdSequentialVerify.apex');
}
