List<Case> cases = [
    SELECT Id, Subject, CreatedDate
    FROM Case
    WHERE Subject LIKE 'cursor-test-% shared userContextId'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
if (cases.isEmpty()) {
    System.debug('No test case found');
} else {
    Case c = cases[0];
    String ctx = String.valueOf(c.Id);
    System.debug('Case: ' + c.Id + ' | ' + c.Subject);

    for (ccai__AI_Response__c a : [
        SELECT Name, ccai__User_Context_Id__c, ccai__Agent_Name__c, CreatedDate, LastModifiedDate
        FROM ccai__AI_Response__c
        WHERE ccai__User_Context_Id__c = :ctx
        ORDER BY CreatedDate ASC
    ]) {
        System.debug(a.Name + ' | agent=' + a.ccai__Agent_Name__c
            + ' | context=' + a.ccai__User_Context_Id__c
            + ' | created=' + a.CreatedDate);
    }

    // Also check audits without context but recent
    for (ccai__AI_Response__c a : [
        SELECT Name, ccai__User_Context_Id__c, ccai__Agent_Name__c, CreatedDate
        FROM ccai__AI_Response__c
        WHERE CreatedDate >= :c.CreatedDate.addSeconds(-5)
        ORDER BY CreatedDate ASC
        LIMIT 10
    ]) {
        System.debug('RECENT: ' + a.Name + ' | ctx=' + a.ccai__User_Context_Id__c
            + ' | agent=' + a.ccai__Agent_Name__c);
    }
}
