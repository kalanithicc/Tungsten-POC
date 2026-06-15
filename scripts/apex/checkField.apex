Case c = new Case(Clarification_Pending__c = false, Subject = 'test');
insert c;
Case queried = [SELECT Id, Clarification_Pending__c FROM Case WHERE Id = :c.Id LIMIT 1];
System.debug('Clarification_Pending__c = ' + queried.Clarification_Pending__c);
delete c;
