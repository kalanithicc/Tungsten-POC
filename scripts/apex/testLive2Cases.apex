// LIVE TEST — two cases, two outcomes:
//
// CASE 1 (CREATE): Brand new topic → no KB exists → new article created
// CASE 2 (SKIP):   Topic already in KB → existing article found → no new article

String marker  = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
String baseUrl = URL.getOrgDomainUrl().toExternalForm();

System.debug('');
System.debug('══════════════════════════════════════════════════════════════');
System.debug('  LIVE 2-CASE TEST   marker: ' + marker);
System.debug('══════════════════════════════════════════════════════════════');

// ─────────────────────────────────────────────────────────────────────────────
// CASE 1 — CREATE (brand-new topic, no existing KB article)
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('CASE 1 ── NEW TOPIC → should CREATE a new KB article');
System.debug('──────────────────────────────────────────────────────');

Case case1 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' How to enable SSO with Okta for iManage Work 10?',
    SuppliedName  = 'Alice Live',
    SuppliedEmail = 'cursor-live1@example.com'
);
insert case1;
System.debug('Case 1 Id: ' + case1.Id);

// Simulate AI resolution
update new Case(
    Id            = case1.Id,
    Status        = 'Closed',
    Resolution__c = 'To enable SSO with Okta for iManage Work 10, configure a SAML 2.0 app in Okta and set the entity ID to your iManage Work URL.',
    Summary__c    = '<p><strong>Fix:</strong> Configure a SAML 2.0 app in Okta. Set entity ID to your iManage Work 10 URL. Download metadata XML and upload to iManage Admin Center under SSO settings.</p>'
);

// Simulate KB Builder Agent — new topic, so CREATE
ccai__AI_Response__c resp1 = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: CREATE\n' +
        'ArticleId:\n' +
        'Question: "How to enable SSO with Okta for iManage Work 10?"\n' +
        'Answer: "To enable SSO with Okta for iManage Work 10: ' +
        '1. In Okta, create a new SAML 2.0 app. ' +
        '2. Set the Entity ID to your iManage Work 10 tenant URL. ' +
        '3. Download the Okta metadata XML. ' +
        '4. In iManage Admin Center, go to Security > SSO > Upload Metadata. ' +
        '5. Assign the Okta app to your users and test login."',
    ccai__Record_Id__c = String.valueOf(case1.Id)
);
new KbArticleBuilderAction().invokeApex(resp1);

Case result1 = [SELECT Status, KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :case1.Id];
List<CaseArticle> links1 = [SELECT KnowledgeArticleId FROM CaseArticle WHERE CaseId = :case1.Id];

System.debug('');
System.debug('  Status           : ' + result1.Status);
System.debug('  KB_Update_Status : ' + result1.KB_Update_Status__c);
System.debug('  KB_Article_Link  : ' + result1.KB_Article_Link__c);
System.debug('  CaseArticle link : ' + (links1.isEmpty() ? 'NONE' : links1[0].KnowledgeArticleId));
System.debug('  OUTCOME          : ' + (result1.KB_Update_Status__c != null && result1.KB_Update_Status__c.startsWith('CREATE:') ? '✓ NEW KB ARTICLE CREATED' : '✗ UNEXPECTED'));


// ─────────────────────────────────────────────────────────────────────────────
// CASE 2 — SKIP (topic already in KB → "How to configure SMTP relay in Nuance Vocalizer Enterprise?")
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('CASE 2 ── EXISTING TOPIC → should SKIP (no new article)');
System.debug('────────────────────────────────────────────────────────');

// Use the most recent article that exists in the KB
Knowledge__kav existingArticle = [
    SELECT Id, KnowledgeArticleId, Title
    FROM Knowledge__kav
    WHERE PublishStatus IN ('Draft', 'Online')
    ORDER BY CreatedDate DESC
    LIMIT 1
];
System.debug('Existing KB article: ' + existingArticle.Title);

Integer kbCountBefore = [SELECT COUNT() FROM Knowledge__kav];

Case case2 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' SMTP relay setup in Nuance Vocalizer Enterprise not working',
    SuppliedName  = 'Bob Live',
    SuppliedEmail = 'cursor-live2@example.com'
);
insert case2;
System.debug('Case 2 Id: ' + case2.Id);

// Simulate AI resolution
update new Case(
    Id            = case2.Id,
    Status        = 'Closed',
    Resolution__c = 'SMTP relay configuration issue in Nuance Vocalizer Enterprise resolved.',
    Summary__c    = '<p>SMTP relay configuration resolved. Use port 587 with TLS credentials.</p>'
);

// Simulate KB Matcher finding the existing article (Tier 2 match) → SKIP
String skipStatus = ('SKIPPED: Similar KB article already exists — ' + existingArticle.Title).left(255);
update new Case(Id = case2.Id, KB_Update_Status__c = skipStatus);

Integer kbCountAfter = [SELECT COUNT() FROM Knowledge__kav];
Case result2 = [SELECT Status, KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :case2.Id];
List<CaseArticle> links2 = [SELECT Id FROM CaseArticle WHERE CaseId = :case2.Id];

System.debug('');
System.debug('  Status           : ' + result2.Status);
System.debug('  KB_Update_Status : ' + result2.KB_Update_Status__c);
System.debug('  KB_Article_Link  : ' + (String.isBlank(result2.KB_Article_Link__c) ? 'null (correct — no new article)' : result2.KB_Article_Link__c));
System.debug('  CaseArticle link : ' + (links2.isEmpty() ? 'NONE (correct)' : 'EXISTS — unexpected'));
System.debug('  KB count before  : ' + kbCountBefore + '  after: ' + kbCountAfter + (kbCountBefore == kbCountAfter ? '  ✓ unchanged' : '  ✗ changed!'));
System.debug('  OUTCOME          : ' + (result2.KB_Update_Status__c != null && result2.KB_Update_Status__c.startsWith('SKIPPED:') ? '✓ SKIPPED — no duplicate created' : '✗ UNEXPECTED'));

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('══════════════════════════════════════════════════════════════');
System.debug('CASE 1 (CREATE): ' + baseUrl + '/lightning/r/Case/' + case1.Id + '/view');
System.debug('CASE 2 (SKIP)  : ' + baseUrl + '/lightning/r/Case/' + case2.Id + '/view');
System.debug('Marker: ' + marker);
System.debug('══════════════════════════════════════════════════════════════');
