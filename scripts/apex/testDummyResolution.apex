// Dummy resolution test — creates a Case, simulates AI recommendation arriving,
// then resolves via CaseResolutionController.resolveCase() (Platform Event path).

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

// 1. Create a test Case
Case c = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' Case 360 polling test',
    SuppliedName  = 'Cursor Test User',
    SuppliedEmail = 'cursor-test@example.com'
);
insert c;
System.debug('Created Case Id: ' + c.Id);

// 2. Simulate GPTfy writing an AI recommendation into Description + Summary__c
update new Case(
    Id          = c.Id,
    Description = 'Your issue is caused by high-frequency polling intervals on the Case 360 report component. Reduce the poll interval from 2.5 s to 10 s for large orgs to avoid SOQL governor limit breaches.',
    Summary__c  = '<p><strong>Root Cause:</strong> High-frequency polling (every 2.5 s) on the Case 360 report component causes excessive SOQL queries.</p><p><strong>Fix:</strong> Reduce poll interval to 10 s for large orgs. Consider caching the last result and only re-querying on user interaction.</p>'
);

// 3. Verify getRecommendation returns the sanitized recommendation
String rec = CaseResolutionController.getRecommendation(c.Id);
System.debug('Recommendation: ' + rec);
System.assert(String.isNotBlank(rec), 'getRecommendation should return content');

// 4. Resolve the Case via Platform Event
CaseResolutionController.resolveCase(c.Id);
System.debug('resolveCase published — CaseResolvedTrigger will close the Case asynchronously');

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case: https://kesavpoc--gptfy.sandbox.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
