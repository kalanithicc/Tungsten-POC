// End-to-end test for KB Agent Resolution Feedback
// Tests both CREATE (new article) and UPDATE (existing article) paths
// Verifies: KB_Update_Status__c, KB_Article_Link__c, and CaseArticle linkage

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
Integer passed = 0;
Integer failed = 0;

// ── Helper ────────────────────────────────────────────────────────────────────
void assert(Boolean condition, String label) {
    if (condition) {
        System.debug('  PASS: ' + label);
        passed++;
    } else {
        System.debug('  FAIL: ' + label);
        failed++;
    }
}

System.debug('');
System.debug('=== KB AGENT RESOLUTION FEEDBACK TEST ===');
System.debug('Marker: ' + marker);
System.debug('');

// ─────────────────────────────────────────────────────────────────────────────
// PATH 1: CREATE — new question, no matching article → agent creates a new KB article
// ─────────────────────────────────────────────────────────────────────────────
System.debug('--- PATH 1: CREATE ---');

Case createCase = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' How to reset 2FA on Nuance Dragon Medical?',
    SuppliedName  = 'Cursor Test',
    SuppliedEmail = 'cursor-test@example.com'
);
insert createCase;
System.debug('CREATE Case Id: ' + createCase.Id);

// Simulate the GPTfy KB Builder prompt response for CREATE
String createResponse =
    'Action: CREATE\n' +
    'ArticleId:\n' +
    'Question: "How to reset 2FA on Nuance Dragon Medical?"\n' +
    'Answer: "To reset 2FA on Nuance Dragon Medical: ' +
    '1. Log in to the admin portal at admin.nuance.com. ' +
    '2. Navigate to User Management > Security. ' +
    '3. Select the affected user and click Reset MFA. ' +
    '4. The user will receive a re-enrollment email within 5 minutes."';

ccai__AI_Response__c createAIResp = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c = createResponse,
    ccai__Record_Id__c                   = String.valueOf(createCase.Id)
);

new KbArticleBuilderAction().invokeApex(createAIResp);

Case createAfter = [
    SELECT KB_Update_Status__c, KB_Article_Link__c
    FROM Case WHERE Id = :createCase.Id
];
List<CaseArticle> createLinks = [
    SELECT Id, KnowledgeArticleId FROM CaseArticle WHERE CaseId = :createCase.Id
];

System.debug('  KB_Update_Status__c : ' + createAfter.KB_Update_Status__c);
System.debug('  KB_Article_Link__c  : ' + createAfter.KB_Article_Link__c);
System.debug('  CaseArticle count   : ' + createLinks.size());

assert(createAfter.KB_Update_Status__c != null &&
       createAfter.KB_Update_Status__c.startsWith('CREATE:'),
       'KB_Update_Status__c starts with CREATE:');
assert(String.isNotBlank(createAfter.KB_Article_Link__c),
       'KB_Article_Link__c is populated');
assert(createAfter.KB_Article_Link__c.contains('/lightning/r/Knowledge__kav/'),
       'KB_Article_Link__c is a valid Lightning URL');
assert(!createLinks.isEmpty(),
       'CaseArticle link was created');

// ─────────────────────────────────────────────────────────────────────────────
// PATH 2: UPDATE — question matches existing article → agent updates it
// Target article: ka0dN000000SNePQAW (iManage Cloud 400 Bad Request — Draft)
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('--- PATH 2: UPDATE ---');

// Use the most recent draft article
Knowledge__kav targetArticle = [
    SELECT Id, KnowledgeArticleId, Title, PublishStatus
    FROM Knowledge__kav
    WHERE PublishStatus = 'Draft'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
System.debug('Target article Id   : ' + targetArticle.Id);
System.debug('Target article Title: ' + targetArticle.Title);

Case updateCase = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' iManage Cloud 400 Bad Request follow-up',
    SuppliedName  = 'Cursor Test',
    SuppliedEmail = 'cursor-test@example.com'
);
insert updateCase;
System.debug('UPDATE Case Id: ' + updateCase.Id);

// Simulate the GPTfy KB Builder prompt response for UPDATE
String updateResponse =
    'Action: UPDATE\n' +
    'ArticleId: ' + targetArticle.Id + '\n' +
    'Question: "iManage Cloud 400 Bad Request follow-up — additional steps"\n' +
    'Answer: "Updated resolution for iManage Cloud 400 Bad Request: ' +
    'In addition to clearing the browser cache, also verify that the SharePoint ' +
    'integration service account has full contributor rights on the target document library. ' +
    'This was identified as a secondary cause in recent escalations."';

ccai__AI_Response__c updateAIResp = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c = updateResponse,
    ccai__Record_Id__c                   = String.valueOf(updateCase.Id)
);

new KbArticleBuilderAction().invokeApex(updateAIResp);

Case updateAfter = [
    SELECT KB_Update_Status__c, KB_Article_Link__c
    FROM Case WHERE Id = :updateCase.Id
];
List<CaseArticle> updateLinks = [
    SELECT Id, KnowledgeArticleId FROM CaseArticle WHERE CaseId = :updateCase.Id
];

System.debug('  KB_Update_Status__c : ' + updateAfter.KB_Update_Status__c);
System.debug('  KB_Article_Link__c  : ' + updateAfter.KB_Article_Link__c);
System.debug('  CaseArticle count   : ' + updateLinks.size());

assert(updateAfter.KB_Update_Status__c != null &&
       updateAfter.KB_Update_Status__c.startsWith('UPDATE:'),
       'KB_Update_Status__c starts with UPDATE:');
assert(String.isNotBlank(updateAfter.KB_Article_Link__c),
       'KB_Article_Link__c is populated');
assert(updateAfter.KB_Article_Link__c.contains('/lightning/r/Knowledge__kav/'),
       'KB_Article_Link__c is a valid Lightning URL');
assert(!updateLinks.isEmpty(),
       'CaseArticle link was created');

// Verify article content was actually updated
Knowledge__kav updatedArticle = [
    SELECT Title, Resolution__c
    FROM Knowledge__kav
    WHERE Id = :targetArticle.Id
    LIMIT 1
];
assert(updatedArticle.Resolution__c != null &&
       updatedArticle.Resolution__c.contains('contributor rights'),
       'Article Resolution__c was updated with new content');

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('=== RESULTS: ' + passed + ' passed, ' + failed + ' failed ===');
System.debug('');
System.debug('CREATE Case: https://kesavpoc--gptfy.sandbox.lightning.force.com/lightning/r/Case/' + createCase.Id + '/view');
System.debug('UPDATE Case: https://kesavpoc--gptfy.sandbox.lightning.force.com/lightning/r/Case/' + updateCase.Id + '/view');
System.debug('Marker: ' + marker);
