// Verify the dual-field HTML/plain-text strategy for email-safe Case.Description
// Run: sf apex run --file scripts/apex/testEmailBodyFix.apex --target-org gptfy-poc1

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss') + ' email-body-fix';

// ── 1. Simulate what the agent typically returns ────────────────────────────
String fakeHtml =
    '<div><strong>Possible Causes:</strong></div>' +
    '<ul>' +
    '<li>Permissions may block SharePoint folder visibility.</li>' +
    '<li>Connector bug in older versions.</li>' +
    '</ul>' +
    '<div><strong>Recommended Actions:</strong></div>' +
    '<ul>' +
    '<li>Verify folder permissions in SharePoint.</li>' +
    '<li>Update Power PDF to the latest build.</li>' +
    '</ul>' +
    '<div>If the issue persists, contact support.</div>';

// ── 2. Call htmlToPlainText ─────────────────────────────────────────────────
String plain = CaseAgentResolutionService.htmlToPlainText(fakeHtml);

System.debug('=== PLAIN TEXT RESULT ===');
System.debug(JSON.serialize(plain)); // JSON-encode to see exact whitespace/chars

// ── 3. Basic assertions ────────────────────────────────────────────────────
System.assert(!plain.contains('<'),              'Plain text MUST NOT contain HTML tags');
System.assert(plain.contains('Possible Causes'), 'Heading text must be preserved');
System.assert(plain.contains('Permissions may'), 'List item text must be preserved');
System.assert(plain.toLowerCase().contains('- permissions') ||
              plain.toLowerCase().contains('permissions may'),
              'List items should have bullet prefix or plain text — got: ' + plain);

// ── 4. Create a real case and verify both fields are written correctly ─────
Case c = new Case(
    Subject = marker,
    Origin  = 'Web',
    Status  = 'New',
    Description = marker
);
insert c;
System.debug('Test Case Id: ' + c.Id);
System.debug('Lightning URL: https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');

// Write both fields exactly as the service does
update new Case(
    Id          = c.Id,
    Summary__c  = fakeHtml,
    Description = plain
);

// ── 5. Read back and assert ────────────────────────────────────────────────
Case result = [SELECT Description, Summary__c FROM Case WHERE Id = :c.Id LIMIT 1];

System.assert(String.isNotBlank(result.Summary__c),       'Summary__c must be populated with HTML');
System.assert(!result.Description.contains('<'),           'Description must be HTML-free for emails');
System.assert(result.Summary__c.contains('<strong>'),      'Summary__c must preserve HTML tags');
System.assert(result.Summary__c.contains('<li>'),          'Summary__c must preserve list HTML');

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Summary__c length: ' + result.Summary__c.length() + ' chars (HTML for LWC)');
System.debug('Description length: ' + result.Description.length() + ' chars (plain text for emails)');
System.debug('Description (plain):');
System.debug(result.Description);
System.debug('Case Id: ' + c.Id);
