/**
 * Sequential agent chain — mirrors real portal flow (no parallel jobs).
 * Run testUserContextIdSequentialVerify.apex after ~3 minutes.
 */
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
String question = 'How do I clear browser cache when the login page shows a blank screen?';

Case c = new Case(
    Origin                      = 'Web',
    Status                      = 'New',
    Priority                    = 'Medium',
    Subject                     = marker + ' sequential userContextId',
    SuppliedName                = 'Cursor Test',
    SuppliedEmail               = 'cursor-test@example.com',
    Product__c                  = 'TotalAgility',
    AI_Clarification_Pending__c = true,
    Description                 = 'Placeholder before resolver.'
);
insert c;

System.enqueueJob(new CaseQuestionClarifierAgentService(
    c.Id, question, 'TotalAgility'
));

System.debug('=== SEQUENTIAL SETUP (step 1: clarifier only) ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + c.Id);
System.debug('After ~90s run testUserContextIdSequentialStep2.apex with Case Id ' + c.Id);
