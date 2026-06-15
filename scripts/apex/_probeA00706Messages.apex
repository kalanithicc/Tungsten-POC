List<ccai__AI_Response__c> a = [
    SELECT Name, ccai__User_Context_Id__c, ccai__AI_Processed_Data_PII_Added__c, LastModifiedDate
    FROM ccai__AI_Response__c
    WHERE Name = 'A-00706'
];
if (a.isEmpty()) { System.debug('A-00706 not found'); return; }
String pii = a[0].ccai__AI_Processed_Data_PII_Added__c;
Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(pii);
List<Object> messages = (List<Object>) root.get('messages');
System.debug('A-00706 messages count: ' + messages.size());
System.debug('lastModified: ' + a[0].LastModifiedDate);
for (Integer i = 0; i < messages.size(); i++) {
    System.debug('msg[' + i + ']=' + String.valueOf(messages[i]).abbreviate(100));
}
