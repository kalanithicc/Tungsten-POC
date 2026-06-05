Map<String, Schema.SObjectField> flds = Schema.SObjectType.ccai__AI_Prompt__c.fields.getMap();
for(String f : flds.keySet()) {
    System.debug(f);
}