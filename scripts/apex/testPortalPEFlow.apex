// Simulate the portal submit flow:
// 1. Create case as guest would (with AI_Clarification_Pending__c = true)
// 2. Publish the new Platform Event (as guest user would)
// 3. CaseAIRequestTrigger fires as Automated Process → enqueues clarifier
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

Case c = new Case(
    Origin                      = 'Web',
    Status                      = 'New',
    Priority                    = 'Medium',
    Subject                     = marker + ' Power PDF crashes when merging files',
    SuppliedName                = 'Portal PE Test',
    SuppliedEmail               = 'pe-test@test.com',
    AI_Clarification_Pending__c = true
);
insert c;

// Publish PE — trigger fires as Automated Process and enqueues clarifier
Case_AI_Requested__e evt = new Case_AI_Requested__e(
    CaseId__c      = c.Id,
    RequestType__c = 'CLARIFY',
    Question__c    = c.Subject,
    Product__c     = null
);
Database.SaveResult sr = EventBus.publish(evt);

System.debug('PE published  : ' + sr.isSuccess());
System.debug('Case ID       : ' + c.Id);
System.debug('Marker        : ' + marker);
System.debug('Case URL      : https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
System.debug('Poll Intent_Analysis__c in ~60s to confirm clarifier ran as Automated Process');
