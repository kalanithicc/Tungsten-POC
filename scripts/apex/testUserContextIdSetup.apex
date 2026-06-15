/**
 * Enqueues clarifier → resolver → KB Match on one Case with shared userContextId.
 * Wait 2–3 minutes, then run testUserContextIdVerify.apex with the same marker.
 */
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
String question = 'How do I clear browser cache when the login page shows a blank screen?';

Case c = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' shared userContextId',
    SuppliedName  = 'Cursor Test',
    SuppliedEmail = 'cursor-test@example.com',
    Product__c    = 'TotalAgility',
    Description   = 'Temporary description before resolver runs.'
);
insert c;

System.enqueueJob(new CaseQuestionClarifierAgentService(
    c.Id, question, 'TotalAgility'
));
System.enqueueJob(new CaseAgentResolutionService(
    c.Id, question
));
System.enqueueJob(new KbMatchAgentService(c.Id));

System.debug('=== USER CONTEXT ID SETUP COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + c.Id);
System.debug('Expected context: ' + String.valueOf(c.Id));
System.debug('Wait 2-3 min then run testUserContextIdVerify.apex');
