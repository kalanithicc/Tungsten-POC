// Debug Route 1 — why isn't the Platform Event closing the case?
Id caseId = '500dN00000PLSVzQAP';

Case c = [SELECT Id, Status, Summary__c, Description, Resolution__c FROM Case WHERE Id = :caseId];
System.debug('Current Status: ' + c.Status);
System.debug('Summary__c set: ' + String.isNotBlank(c.Summary__c));

// Re-publish the platform event manually
Case_Resolved__e evt = new Case_Resolved__e(CaseId__c = String.valueOf(caseId));
Database.SaveResult sr = EventBus.publish(evt);
System.debug('Event publish success: ' + sr.isSuccess());
if (!sr.isSuccess()) {
    for (Database.Error e : sr.getErrors()) {
        System.debug('Event publish error: ' + e.getMessage());
    }
}

// Also try direct update to verify the field/validation rules
Case toUpdate = new Case(Id = caseId, Status = 'Closed', Resolution__c = c.Summary__c);
try {
    update toUpdate;
    System.debug('Direct update succeeded — case closed');
} catch (Exception e) {
    System.debug('Direct update FAILED: ' + e.getMessage());
}
