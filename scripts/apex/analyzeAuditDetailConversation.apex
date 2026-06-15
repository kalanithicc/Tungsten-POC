for (String fn : ccai__AI_Security_Audit_Detail__c.SObjectType.getDescribe().fields.getMap().keySet()) {
    if (fn.startsWith('ccai__')) System.debug(fn);
}

List<ccai__AI_Security_Audit_Detail__c> details = [
    SELECT Id, Name, ccai__AI_Security_Audit__c, ccai__Message__c,
           CreatedDate, LastModifiedDate
    FROM ccai__AI_Security_Audit_Detail__c
    WHERE ccai__AI_Security_Audit__c = 'a0RdN0000045Id7UAE'
    ORDER BY CreatedDate ASC, Name ASC
];
System.debug('Detail count for A-00766: ' + details.size());

for (ccai__AI_Security_Audit_Detail__c d : details) {
    String msg = d.ccai__Message__c;
    System.debug('--- ' + d.Name + ' ' + d.Id + ' ---');
    System.debug('len=' + (msg == null ? 0 : msg.length()) + ' created=' + d.CreatedDate);
    System.debug('preview=' + (msg == null ? '' : msg.abbreviate(200)));
}

// Find parent audit(s) by userContextId
List<ccai__AI_Response__c> parents = [
    SELECT Id, Name, ccai__User_Context_Id__c, ccai__Agent_Name__c
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = 'demoo-route2-001'
];
System.debug('Parent audits for demoo-route2-001: ' + parents.size());
for (ccai__AI_Response__c p : parents) {
    Integer cnt = [
        SELECT COUNT()
        FROM ccai__AI_Security_Audit_Detail__c
        WHERE ccai__AI_Security_Audit__c = :p.Id
    ];
    System.debug('Parent ' + p.Name + ' detail children: ' + cnt);
}
