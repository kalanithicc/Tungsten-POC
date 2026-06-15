List<Case> cases = [
    SELECT Id, Subject, Intent_Analysis__c, Summary__c
    FROM Case
    WHERE Subject LIKE 'cursor-test-% sequential userContextId'
    ORDER BY CreatedDate DESC
    LIMIT 1
];

if (cases.isEmpty()) {
    System.debug('FAIL: no sequential test case');
} else {
    Case c = cases[0];
    String ctx = String.valueOf(c.Id);

    List<ccai__AI_Response__c> audits = [
        SELECT Id, Name, ccai__Agent_Name__c, ccai__User_Context_Id__c
        FROM ccai__AI_Response__c
        WHERE ccai__User_Context_Id__c = :ctx
        ORDER BY CreatedDate ASC
    ];

    System.debug('=== SEQUENTIAL VERIFY ===');
    System.debug('Case: ' + c.Id);
    System.debug('Audit count: ' + audits.size());

    for (ccai__AI_Response__c a : audits) {
        System.debug('  ' + a.Name + ' | ' + a.ccai__Agent_Name__c);
    }

    System.assertEquals(1, audits.size(),
        'Expected 1 shared audit for sequential flow, found ' + audits.size());

    ccai__AI_Response__c parent = audits[0];
    List<ccai__AI_Security_Audit_Detail__c> details = [
        SELECT Id, Name, ccai__Message__c
        FROM ccai__AI_Security_Audit_Detail__c
        WHERE ccai__AI_Security_Audit__c = :parent.Id AND ccai__Type__c = 'Chat'
        ORDER BY CreatedDate ASC
    ];

    Integer turns = 0;
    for (ccai__AI_Security_Audit_Detail__c d : details) {
        if (String.isNotBlank(d.ccai__Message__c)) {
            turns += ((List<Object>) JSON.deserializeUntyped(d.ccai__Message__c)).size();
        }
    }

    System.debug('Detail rows: ' + details.size() + ' | total turns: ' + turns);
    System.assert(turns >= 4, 'Expected multi-step conversation, turns=' + turns);

    System.debug('PASS: single audit ' + parent.Name);
    System.debug('=== CURSOR TEST COMPLETE ===');
    System.debug('Marker: ' + c.Subject);
}
