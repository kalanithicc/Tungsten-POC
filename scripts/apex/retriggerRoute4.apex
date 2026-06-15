// Re-trigger KB creation for the existing Route 4 case (article limit was hit before)
Id caseId = '500dN00000PLSW2QAP';

Case c = [SELECT Id, Subject, Description FROM Case WHERE Id = :caseId LIMIT 1];
System.debug('Retriggering KB creation for: ' + c.Subject);
System.debug('Description length: ' + (c.Description == null ? 0 : c.Description.length()));

// Direct chain to KbMatchAgentService — it will find no match and chain creation
System.enqueueJob(new KbMatchAgentService(caseId));
System.debug('KbMatchAgentService enqueued for Case ' + caseId);
System.debug('Wait 3-5 minutes then check KB_Article_Link__c on the case.');
