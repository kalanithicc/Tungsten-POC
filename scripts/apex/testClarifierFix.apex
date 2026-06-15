// Verify the clarification agent now parses HTML responses correctly
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss') + ' clarifier-fix';

Case c = new Case(
    Origin                      = 'Web',
    Status                      = 'New',
    Priority                    = 'Medium',
    Subject                     = 'My ScanSnap iX500 scanner is not showing up in Power PDF after I upgraded to 2025.3',
    SuppliedName                = 'cursor test',
    SuppliedEmail               = 'cursor@test.com',
    AI_Clarification_Pending__c = true
);
insert c;
System.debug('Case created: ' + c.Id);

System.enqueueJob(new CaseQuestionClarifierAgentService(
    c.Id,
    c.Subject,
    null
));
System.debug('Marker: ' + marker);
System.debug('Case URL: https://gptfypoc-dev-ed.develop.my.salesforce.com/lightning/r/Case/' + c.Id + '/view');
System.debug('Wait 30s then query:');
System.debug('SELECT Subject, Intent_Analysis__c FROM Case WHERE Id = \'' + c.Id + '\'');
