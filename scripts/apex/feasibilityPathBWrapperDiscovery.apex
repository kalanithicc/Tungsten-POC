// Discover RequestWrapper / ResponseWrapper properties available in org
Map<String, Schema.SObjectField> fMap = ccai__AI_Response__c.SObjectType.getDescribe().fields.getMap();
List<String> interesting = new List<String>();
for (String fn : fMap.keySet()) {
    String l = fn.toLowerCase();
    if (l.contains('context') || l.contains('record') || l.contains('thread')
        || l.contains('session') || l.contains('conversation') || l.contains('parent')) {
        interesting.add(fn);
    }
}
System.debug('AI_Response context/record fields: ' + interesting);

// Try setting common wrapper property names via reflection pattern
ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName = 'Question_Clarifier_Agent';
req.userMessage = 'Product: Test\nQuestion: Path B discovery';

// Probe optional fields — compile-time may fail if we guess wrong; use dynamic if needed
try {
    // Document what we can read from a minimal invoke (admin)
    ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);
    if (resp != null) {
        System.debug('response.status=' + resp.status);
        System.debug('response.responseBody blank=' + String.isBlank(resp.responseBody));
    }

    List<ccai__AI_Response__c> latest = [
        SELECT Name, ccai__Record_Id__c, ccai__User_Context_Id__c,
               ccai__Agent_Name__c, CreatedDate
        FROM ccai__AI_Response__c
        WHERE ccai__Agent_Name__c = 'Question Clarifier Agent'
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (!latest.isEmpty()) {
        System.debug('Latest audit after probe: ' + latest[0].Name
            + ' recordId=' + latest[0].ccai__Record_Id__c
            + ' contextId=' + latest[0].ccai__User_Context_Id__c);
    }
} catch (Exception e) {
    System.debug('invoke err: ' + e.getMessage());
}

System.debug('=== PATH B WRAPPER DISCOVERY DONE ===');
