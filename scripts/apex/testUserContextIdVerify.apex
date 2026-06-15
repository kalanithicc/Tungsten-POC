/**
 * Verifies all three agents share one Security Audit via Case Id userContextId.
 * Update marker below to match testUserContextIdSetup.apex output, or uses latest cursor case.
 */
String markerFilter = 'cursor-test-% shared userContextId';

List<Case> cases = [
    SELECT Id, Subject, Intent_Analysis__c, Summary__c, KB_Candidates__c, KB_Article_Link__c
    FROM Case
    WHERE Subject LIKE :markerFilter
    ORDER BY CreatedDate DESC
    LIMIT 1
];

if (cases.isEmpty()) {
    System.debug('FAIL: No case found matching "' + markerFilter + '". Run testUserContextIdSetup.apex first.');
} else {
    Case c = cases[0];
    String contextId = String.valueOf(c.Id);

    List<ccai__AI_Response__c> audits = [
        SELECT Id, Name, ccai__User_Context_Id__c, ccai__Agent_Name__c,
               LastModifiedDate
        FROM ccai__AI_Response__c
        WHERE ccai__User_Context_Id__c = :contextId
        ORDER BY LastModifiedDate DESC
    ];

    System.debug('=== USER CONTEXT ID VERIFY ===');
    System.debug('Case: ' + c.Id + ' | ' + c.Subject);
    System.debug('Context Id on audits: expected ' + contextId);

    Integer auditCount = audits.size();
    System.debug('Parent audit count for this Case Id: ' + auditCount);
    System.assert(auditCount == 1,
        'Expected exactly 1 shared Security Audit, found ' + auditCount);

    ccai__AI_Response__c parent = audits[0];
    System.debug('PASS: Single parent audit ' + parent.Name
        + ' | last agent=' + parent.ccai__Agent_Name__c);

    List<ccai__AI_Security_Audit_Detail__c> details = [
        SELECT Id, Name, ccai__Type__c, ccai__Message__c, CreatedDate
        FROM ccai__AI_Security_Audit_Detail__c
        WHERE ccai__AI_Security_Audit__c = :parent.Id
          AND ccai__Type__c = 'Chat'
        ORDER BY CreatedDate ASC, Name ASC
    ];

    Integer totalTurns = 0;
    for (ccai__AI_Security_Audit_Detail__c d : details) {
        if (String.isBlank(d.ccai__Message__c)) {
            continue;
        }
        List<Object> turns = (List<Object>) JSON.deserializeUntyped(d.ccai__Message__c);
        totalTurns += turns.size();
        System.debug('Detail ' + d.Name + ': ' + turns.size() + ' turns');
    }

    System.debug('Total conversation turns across Detail rows: ' + totalTurns);
    System.assert(totalTurns >= 3,
        'Expected multi-agent conversation (>=3 turns), found ' + totalTurns);

    System.debug('Clarifier JSON present: ' + String.isNotBlank(c.Intent_Analysis__c));
    System.debug('Resolver Summary present: ' + String.isNotBlank(c.Summary__c));

    System.debug('=== CURSOR TEST COMPLETE ===');
    System.debug('Marker search: ' + c.Subject);
    System.debug('Audit URL path: /lightning/r/ccai__AI_Response__c/' + parent.Id + '/view');
}
