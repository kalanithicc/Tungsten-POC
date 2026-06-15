// End-to-end verification of the dual-field email fix:
// 1. Confirm CaseResolvedTrigger copies Summary__c (HTML) to Resolution__c
// 2. Confirm Description is plain text (email-safe)
// Run: sf apex run --file scripts/apex/testEmailBodyFix2.apex --target-org gptfy-poc1

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss') + ' resolved-email-fix';

String fakeHtml =
    '<div><strong>Possible Causes:</strong></div>' +
    '<ul><li>Permissions may block SharePoint folder visibility.</li>' +
    '<li>Connector bug in older hotfix versions.</li></ul>' +
    '<div><strong>Resolution:</strong></div>' +
    '<ul><li>Update Power PDF to the latest build.</li>' +
    '<li>Verify SharePoint folder permissions.</li></ul>';

String fakePlain = CaseAgentResolutionService.htmlToPlainText(fakeHtml);

// ── 1. Create case ─────────────────────────────────────────────────────────
Case c = new Case(
    Subject       = marker,
    SuppliedEmail = 'cursor-test@example.com',
    Origin        = 'Web',
    Status        = 'New',
    Summary__c    = fakeHtml,
    Description   = fakePlain
);
insert c;
System.debug('Case Id: ' + c.Id);
System.debug('Lightning URL: https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');

// ── 2. Publish Case_Resolved__e (simulates guest clicking "Yes, resolved") ─
Case_Resolved__e evt = new Case_Resolved__e(CaseId__c = String.valueOf(c.Id));
Database.SaveResult sr = EventBus.publish(evt);
System.assert(sr.isSuccess(), 'Platform Event publish must succeed');

// ── 3. Wait is not possible in anon Apex — instruct user to poll ───────────
System.debug('=== PLATFORM EVENT PUBLISHED — poll in ~5s ===');
System.debug('Run: sf data query --query "SELECT Status, Resolution__c, Description FROM Case WHERE Id=\'' + c.Id + '\'" --target-org gptfy-poc1');
System.debug('Expected: Status=Closed, Resolution__c contains HTML tags (<strong>), Description has no HTML tags');
System.debug('Marker: ' + marker);
System.debug('=== CURSOR TEST COMPLETE ===');
