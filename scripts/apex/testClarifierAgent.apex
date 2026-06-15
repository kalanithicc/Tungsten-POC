String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

// Create a vague case to force the clarifier to ask follow-up questions
Case c = new Case(
    Origin                      = 'Web',
    Status                      = 'New',
    Priority                    = 'Medium',
    Subject                     = marker + ' Power PDF is not printing correctly',
    SuppliedName                = 'Clarifier Test',
    SuppliedEmail               = 'clarifier@test.com',
    AI_Clarification_Pending__c = true
);
insert c;

System.debug('Case ID  : ' + c.Id);
System.debug('Marker   : ' + marker);

// Enqueue the clarifier exactly as submitForClarification() does
System.enqueueJob(new CaseQuestionClarifierAgentService(
    c.Id,
    c.Subject,
    null
));

System.debug('Clarifier enqueued. Poll Intent_Analysis__c in ~60s.');
System.debug('Case URL : https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
