List<ccai__AI_Response__c> rows = [
    SELECT Name, ccai__Agent_Name__c, ccai__AI_Processed_Data_PII_Added__c
    FROM ccai__AI_Response__c
    WHERE Name IN ('A-00656', 'A-00707', 'A-00706')
];
for (ccai__AI_Response__c r : rows) {
    String pii = r.ccai__AI_Processed_Data_PII_Added__c;
    System.debug('=== ' + r.Name + ' (' + r.ccai__Agent_Name__c + ') ===');
    if (String.isBlank(pii)) {
        System.debug('PII Added: blank');
        continue;
    }
    try {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(pii);
        List<Object> messages = (List<Object>) root.get('messages');
        System.debug('messages count: ' + (messages == null ? 0 : messages.size()));
        if (messages != null) {
            for (Integer i = 0; i < messages.size(); i++) {
                String m = String.valueOf(messages[i]);
                System.debug('  msg[' + i + '] len=' + m.length() + ' preview=' + m.abbreviate(120));
            }
        }
    } catch (Exception e) {
        System.debug('parse err: ' + e.getMessage());
    }
}
