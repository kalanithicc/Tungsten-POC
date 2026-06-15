ccai__AI_Security_Audit_Detail__c d = [
    SELECT ccai__Message__c, ccai__Type__c, ccai__Status__c
    FROM ccai__AI_Security_Audit_Detail__c
    WHERE Id = 'a0UdN000006NPBxUAO'
    LIMIT 1
][0];

System.debug('type=' + d.ccai__Type__c + ' status=' + d.ccai__Status__c);
String raw = d.ccai__Message__c;

// Try parse as JSON array of turns
try {
    List<Object> turns = (List<Object>) JSON.deserializeUntyped(raw);
    System.debug('Turn count: ' + turns.size());
    for (Integer i = 0; i < turns.size(); i++) {
        Map<String, Object> turn = (Map<String, Object>) turns[i];
        String role = String.valueOf(turn.get('role'));
        String ts = String.valueOf(turn.get('timestamp'));
        String content = String.valueOf(turn.get('content'));
        System.debug('[' + i + '] ' + role + ' @ ' + ts + ' len=' + content.length());
        System.debug('  preview: ' + content.abbreviate(120));
    }
} catch (Exception e) {
    System.debug('Not JSON array: ' + e.getMessage());
    System.debug('starts with: ' + raw.abbreviate(100));
}
