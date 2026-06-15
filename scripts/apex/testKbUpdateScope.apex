/**
 * Smoke-test: KB exists → skip creation → KB_Candidates__c ("KB Update Scope") is populated.
 *
 * Requires at least one Published Knowledge article in the org.
 * The KB_Match_Agent RAG only indexes Published articles.
 */
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss') + ' scope-test';
System.debug('=== KB UPDATE SCOPE TEST STARTING === Marker: ' + marker);

// Find a published KB article to reference in the case subject
List<Knowledge__kav> pubs = [
    SELECT Id, Title
    FROM Knowledge__kav
    WHERE PublishStatus = 'Online'
    ORDER BY LastModifiedDate DESC
    LIMIT 1
];
if (pubs.isEmpty()) {
    System.debug('SKIP: No published KB articles in org — publish an article first and re-run.');
    return;
}
String articleTitle = pubs[0].Title;
System.debug('Reference article: ' + articleTitle);

// Create a case whose subject closely matches the existing article
Case c = new Case(
    Subject     = marker + ': ' + articleTitle,
    Description = 'Customer is experiencing the exact scenario described in existing KB.',
    Status      = 'Open',
    Origin      = 'Web'
);
insert c;
System.debug('Case created: ' + c.Id);
System.debug('Case URL: https://gptfypoc-dev-ed.develop.my.salesforce.com/lightning/r/Case/' + c.Id + '/view');

// Trigger the KB match gate directly (same path as agent manual resolution with Create KB ticked)
System.enqueueJob(new KbMatchAgentService(c.Id));
System.debug('KbMatchAgentService enqueued for Case: ' + c.Id);
System.debug('Wait ~30-60 seconds then run:');
System.debug('sf data query --query "SELECT Id, Subject, KB_Candidates__c, KB_Article_Link__c FROM Case WHERE Id = \'' + c.Id + '\'" --target-org gptfy-poc1');
System.debug('=== CURSOR TEST COMPLETE === Marker: ' + marker);
