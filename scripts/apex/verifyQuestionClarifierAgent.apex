// Run this AFTER creating the Question Clarifier Agent in the GPTfy UI.
// Confirms the agent developer name resolves and the invocation works end-to-end.

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
System.debug('=== CURSOR TEST: Question Clarifier Agent ===');

// ─── 1. Create a test Case ───
Case c = new Case(
    Origin                       = 'Web',
    Status                       = 'New',
    Priority                     = 'Medium',
    Subject                      = marker + ' powerpdf license not working after webex install',
    SuppliedName                 = 'Cursor Test',
    SuppliedEmail                = 'cursor-test@example.com',
    AI_Clarification_Pending__c  = true
);
insert c;
System.debug('Case created: ' + c.Id);

// ─── 2. Invoke the agent service directly (synchronous in test context) ───
// Note: in production this runs as a Queueable but we call execute() directly here.
CaseQuestionClarifierAgentService svc = new CaseQuestionClarifierAgentService(
    c.Id,
    'powerpdf license not working after webex install',
    'PowerPDF'
);

// Queue it (Queueable in execute anon runs as a chained job — not blocking)
System.enqueueJob(svc);
System.debug('[STEP 2] CaseQuestionClarifierAgentService enqueued for Case ' + c.Id);

System.debug('=== CURSOR TEST SETUP COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + c.Id);
System.debug('Poll Intent_Analysis__c after ~30s:');
System.debug('  sf data query --query "SELECT Intent_Analysis__c FROM Case WHERE Id = \'' + c.Id + '\'" --target-org gptfy-poc1');
System.debug('Org URL: https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
