/**
 * Feasibility check: can we build a Case conversation LWC from Security Audits?
 * Read-only diagnostics — no DML.
 */
System.debug('=== CONVERSATION LWC FEASIBILITY ===');

// 1. Object access
Schema.DescribeSObjectResult auditDesc =
    ccai__AI_Response__c.SObjectType.getDescribe();
System.debug('Audit queryable: ' + auditDesc.isAccessible());
System.debug('Audit createable: ' + auditDesc.isCreateable());

// 2. Recent agent audits — Record Id population
List<AggregateResult> byRecordId = [
    SELECT COUNT(Id) cnt
    FROM ccai__AI_Response__c
    WHERE CreatedDate = LAST_N_DAYS:30
      AND ccai__Record_Id__c != null
];
Integer withRecordId = (Integer) byRecordId[0].get('cnt');

List<AggregateResult> agentAudits = [
    SELECT COUNT(Id) cnt
    FROM ccai__AI_Response__c
    WHERE CreatedDate = LAST_N_DAYS:30
      AND ccai__Agent_Name__c != null
];
Integer agentCount = (Integer) agentAudits[0].get('cnt');

List<AggregateResult> agentWithRecord = [
    SELECT COUNT(Id) cnt
    FROM ccai__AI_Response__c
    WHERE CreatedDate = LAST_N_DAYS:30
      AND ccai__Agent_Name__c != null
      AND ccai__Record_Id__c != null
];
Integer agentWithRecordId = (Integer) agentWithRecord[0].get('cnt');

System.debug('Last 30d audits with Record_Id: ' + withRecordId);
System.debug('Last 30d agent audits: ' + agentCount);
System.debug('Last 30d agent audits WITH Record_Id: ' + agentWithRecordId);

// 3. User Context Id usage
List<AggregateResult> withContext = [
    SELECT COUNT(Id) cnt
    FROM ccai__AI_Response__c
    WHERE CreatedDate = LAST_N_DAYS:30
      AND ccai__User_Context_Id__c != null
];
Integer contextCount = (Integer) withContext[0].get('cnt');
System.debug('Last 30d audits with User_Context_Id: ' + contextCount);

// 4. Sample Case-linked audits (prompt path usually has Record_Id)
List<ccai__AI_Response__c> caseLinked = [
    SELECT Id, Name, ccai__Agent_Name__c, ccai__Record_Id__c,
           ccai__User_Context_Id__c, CreatedDate,
           ccai__Data_Original__c, ccai__Message__c
    FROM ccai__AI_Response__c
    WHERE ccai__Record_Id__c != null
      AND ccai__Record_Id__c LIKE '500%'
    ORDER BY CreatedDate DESC
    LIMIT 5
];
System.debug('Sample Case-linked audits: ' + caseLinked.size());
for (ccai__AI_Response__c a : caseLinked) {
    System.debug('  ' + a.Name + ' | agent=' + a.ccai__Agent_Name__c
        + ' | record=' + a.ccai__Record_Id__c
        + ' | context=' + a.ccai__User_Context_Id__c
        + ' | originalLen=' + (a.ccai__Data_Original__c == null ? 0 : a.ccai__Data_Original__c.length()));
}

// 5. Clarifier / resolver agent audits for a recent portal case
List<Case> recentCases = [
    SELECT Id, CaseNumber, Subject, CreatedDate
    FROM Case
    WHERE Origin = 'Web'
      AND Subject LIKE 'cursor-test%'
    ORDER BY CreatedDate DESC
    LIMIT 3
];
System.debug('Recent cursor-test cases: ' + recentCases.size());

for (Case c : recentCases) {
    Datetime windowStart = c.CreatedDate.addMinutes(-2);
    Datetime windowEnd   = c.CreatedDate.addHours(2);

    List<ccai__AI_Response__c> clarifierAudits = [
        SELECT Id, Name, ccai__Agent_Name__c, ccai__Record_Id__c,
               ccai__User_Context_Id__c, CreatedDate,
               ccai__AI_Processed_Data_PII_Added__c
        FROM ccai__AI_Response__c
        WHERE ccai__Agent_Name__c = 'Question Clarifier Agent'
          AND CreatedDate >= :windowStart
          AND CreatedDate <= :windowEnd
        ORDER BY CreatedDate ASC
        LIMIT 10
    ];

    List<ccai__AI_Response__c> byRecord = [
        SELECT Id, Name, ccai__Agent_Name__c, ccai__Record_Id__c
        FROM ccai__AI_Response__c
        WHERE ccai__Record_Id__c = :String.valueOf(c.Id)
        ORDER BY CreatedDate ASC
    ];

    System.debug('--- Case ' + c.CaseNumber + ' ' + c.Id + ' ---');
    System.debug('  Audits by Record_Id: ' + byRecord.size());
    System.debug('  Clarifier audits in time window: ' + clarifierAudits.size());

    for (ccai__AI_Response__c a : clarifierAudits) {
        String pii = a.ccai__AI_Processed_Data_PII_Added__c;
        String parsed = QuestionClarifierAction.extractMessageFromPiiAdded(pii);
        System.debug('  Audit ' + a.Name + ' recordId=' + a.ccai__Record_Id__c
            + ' context=' + a.ccai__User_Context_Id__c
            + ' parseOk=' + String.isNotBlank(parsed)
            + ' preview=' + (parsed == null ? '' : parsed.abbreviate(80)));
    }
}

// 6. Can we build message DTOs from PII Added?
Integer parseable = 0;
Integer totalSample = 0;
for (ccai__AI_Response__c a : [
    SELECT ccai__AI_Processed_Data_PII_Added__c, ccai__Agent_Name__c
    FROM ccai__AI_Response__c
    WHERE CreatedDate = LAST_N_DAYS:14
      AND ccai__Agent_Name__c != null
    LIMIT 50
]) {
    if (String.isBlank(a.ccai__AI_Processed_Data_PII_Added__c)) {
        continue;
    }
    totalSample++;
    if (String.isNotBlank(QuestionClarifierAction.extractMessageFromPiiAdded(
        a.ccai__AI_Processed_Data_PII_Added__c))) {
        parseable++;
    }
}
System.debug('Parseable PII Added (agent audits, sample ' + totalSample + '): ' + parseable);

System.debug('=== FEASIBILITY COMPLETE ===');
