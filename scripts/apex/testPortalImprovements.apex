String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

Map<String, String> ctx = CaseResolutionController.getPortalUserContext();
System.debug('[ASSERT] getPortalUserContext userType: ' + ctx.get('userType'));
System.debug('[ASSERT] isGuest=' + ctx.get('isGuest') + ' displayName=' + ctx.get('displayName'));

Case c = new Case(
    Subject = marker + ' C1 clarifier _error fallback test',
    Origin = 'Web',
    Status = 'New',
    AI_Clarification_Pending__c = true
);
insert c;

System.enqueueJob(new CaseQuestionClarifierAgentService(c.Id, c.Subject, null));

System.debug('=== CURSOR TEST ENQUEUED ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + c.Id);
System.debug('Re-query Intent_Analysis__c in ~10s for _error field (C1)');
