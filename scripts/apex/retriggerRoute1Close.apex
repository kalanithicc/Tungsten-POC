Id caseId = '500dN00000PLq6uQAD';
Case_Resolved__e evt = new Case_Resolved__e(CaseId__c = String.valueOf(caseId));
Database.SaveResult sr = EventBus.publish(evt);
System.debug('Republish success: ' + sr.isSuccess());
if (!sr.isSuccess()) System.debug('Error: ' + sr.getErrors()[0].getMessage());
