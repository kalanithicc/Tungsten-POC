Id caseId = '500dN00000PPWXlQAP';
String ctx = String.valueOf(caseId);

for (ccai__AI_Response__c a : [
    SELECT Name, ccai__Agent_Name__c, ccai__User_Context_Id__c,
           ccai__Parent_AI_Response__c, ccai__AI_Parent_Response__c, ccai__Thread_Id__c
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = :ctx
    ORDER BY CreatedDate ASC
]) {
    Integer detailCount = [
        SELECT COUNT()
        FROM ccai__AI_Security_Audit_Detail__c
        WHERE ccai__AI_Security_Audit__c = :a.Id
    ];
    System.debug(a.Name + ' | agent=' + a.ccai__Agent_Name__c
        + ' | parent=' + a.ccai__Parent_AI_Response__c
        + ' | aiParent=' + a.ccai__AI_Parent_Response__c
        + ' | thread=' + a.ccai__Thread_Id__c
        + ' | details=' + detailCount);
}

// Compare REST-style single audit
for (ccai__AI_Response__c a : [
    SELECT Name, ccai__Agent_Name__c, ccai__User_Context_Id__c
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = 'demoo-route2-001'
    LIMIT 5
]) {
    Integer detailCount = [
        SELECT COUNT()
        FROM ccai__AI_Security_Audit_Detail__c
        WHERE ccai__AI_Security_Audit__c = :a.Id
    ];
    System.debug('REST ctx audit: ' + a.Name + ' agent=' + a.ccai__Agent_Name__c
        + ' details=' + detailCount);
}
