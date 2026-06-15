List<ccai__AI_Response__c> rows = [
    SELECT Name, ccai__Agent_Name__c, ccai__User_Context_Id__c,
           ccai__AI_Processed_Data_PII_Added__c, ccai__Data_Original__c,
           CreatedDate, LastModifiedDate
    FROM ccai__AI_Response__c
    WHERE Id = 'a0RdN0000045Id7UAE'
];
if (rows.isEmpty()) { System.debug('not found'); return; }
ccai__AI_Response__c r = rows[0];
System.debug('Name=' + r.Name + ' agent=' + r.ccai__Agent_Name__c);
System.debug('context=' + r.ccai__User_Context_Id__c);
System.debug('created=' + r.CreatedDate + ' modified=' + r.LastModifiedDate);

String pii = r.ccai__AI_Processed_Data_PII_Added__c;
if (String.isBlank(pii)) {
    System.debug('PII Added: blank');
} else {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(pii);
    List<Object> messages = (List<Object>) root.get('messages');
    System.debug('PII messages count: ' + (messages == null ? 0 : messages.size()));
    if (messages != null) {
        for (Integer i = 0; i < messages.size(); i++) {
            String m = String.valueOf(messages[i]);
            System.debug('--- msg[' + i + '] len=' + m.length());
            System.debug(m.abbreviate(250));
        }
    }
}

String body = QuestionClarifierAction.extractMessageFromPiiAdded(pii);
System.debug('extractMessageFromPiiAdded len=' + (body == null ? 0 : body.length()));
System.debug('has KB_MATCHES=' + (body != null && body.contains('KB_MATCHES_START')));
System.debug('has HTML comment=' + (body != null && body.contains('<!--')));

String norm = KbMatchAgentService.normalizeAgentResponse(body);
System.debug('normalized len=' + (norm == null ? 0 : norm.length()));
System.debug('parseMatchTitles=' + KbMatchAgentService.parseMatchTitles(norm));
System.debug('norm has SCOPE markers=' + norm.contains('KB_UPDATE_SCOPE_START'));
