// Full E2E Test — two scenarios:
//
// SCENARIO A: Create Case → Resolve it → CREATE new KB article → verify link on Case
// SCENARIO B: Pre-create KB article → Create Case → Resolve it → UPDATE that KB → verify link on Case

String marker  = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
Integer passed = 0;
Integer failed = 0;

void ok(Boolean condition, String label) {
    if (condition) { System.debug('  ✓ PASS: ' + label); passed++; }
    else           { System.debug('  ✗ FAIL: ' + label); failed++; }
}

System.debug('');
System.debug('════════════════════════════════════════════════════════');
System.debug('  E2E KB CREATE + UPDATE TEST   marker: ' + marker);
System.debug('════════════════════════════════════════════════════════');

// ─────────────────────────────────────────────────────────────────────────────
// SCENARIO A — CREATE
// 1. Create Case
// 2. Simulate AI resolution writing answer to Case
// 3. Simulate KB Builder Agent → CREATE new KB article
// 4. Verify KB_Update_Status__c, KB_Article_Link__c, CaseArticle
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('SCENARIO A ── CREATE new KB article from Case');
System.debug('─────────────────────────────────────────────');

// Step 1: Create Case
Case caseA = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' How to fix Nuance Dragon Medical One crashing on Windows 11?',
    SuppliedName  = 'Alice Test',
    SuppliedEmail = 'alice-cursor-test@example.com'
);
insert caseA;
System.debug('Step 1 — Case created: ' + caseA.Id);

// Step 2: Simulate AI resolution (GPTfy writes answer into Description + Summary__c)
String aiAnswer =
    '<p><strong>Root Cause:</strong> Dragon Medical One crashes on Windows 11 due to ' +
    'an incompatible audio driver version bundled with the 2024.1 release.</p>' +
    '<p><strong>Fix:</strong> Update to Dragon Medical One 2024.3+, then reinstall ' +
    'the Nuance-certified audio driver from the support portal. Reboot required.</p>';

update new Case(
    Id          = caseA.Id,
    Status      = 'Closed',
    Description = 'Dragon Medical One crashes on Windows 11 — audio driver conflict.',
    Summary__c  = aiAnswer,
    Resolution__c = aiAnswer
);
System.debug('Step 2 — Case resolved with AI answer');

// Step 3: Simulate KB Builder Agent response → CREATE
ccai__AI_Response__c aiRespA = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: CREATE\n' +
        'ArticleId:\n' +
        'Question: "How to fix Nuance Dragon Medical One crashing on Windows 11?"\n' +
        'Answer: "Dragon Medical One crashes on Windows 11 due to an incompatible audio driver ' +
        'in the 2024.1 release. Resolution: Update to Dragon Medical One 2024.3+, reinstall ' +
        'the Nuance-certified audio driver from support.nuance.com, then reboot the machine."',
    ccai__Record_Id__c = String.valueOf(caseA.Id)
);
new KbArticleBuilderAction().invokeApex(aiRespA);
System.debug('Step 3 — KbArticleBuilderAction invoked (CREATE)');

// Step 4: Verify
Case afterA       = [SELECT Status, KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :caseA.Id];
List<CaseArticle> linksA = [SELECT KnowledgeArticleId FROM CaseArticle WHERE CaseId = :caseA.Id];

System.debug('');
System.debug('  Status            : ' + afterA.Status);
System.debug('  KB_Update_Status  : ' + afterA.KB_Update_Status__c);
System.debug('  KB_Article_Link   : ' + afterA.KB_Article_Link__c);
System.debug('  CaseArticle count : ' + linksA.size());

ok(afterA.Status == 'Closed',                               'Case is Closed');
ok(afterA.KB_Update_Status__c != null
   && afterA.KB_Update_Status__c.startsWith('CREATE:'),     'KB_Update_Status starts with CREATE:');
ok(String.isNotBlank(afterA.KB_Article_Link__c),            'KB_Article_Link__c is populated');
ok(afterA.KB_Article_Link__c.startsWith('https://'),        'KB_Article_Link__c is absolute URL');
ok(!linksA.isEmpty(),                                       'CaseArticle link created');

// Capture new article Id for Scenario B
Id newArticleKaId = linksA.isEmpty() ? null : linksA[0].KnowledgeArticleId;


// ─────────────────────────────────────────────────────────────────────────────
// SCENARIO B — UPDATE
// 1. Use the KB article created in Scenario A (or create a fresh one)
// 2. Create a NEW Case about the same topic
// 3. Simulate AI resolution
// 4. Simulate KB Builder Agent → UPDATE the existing KB article
// 5. Verify KB_Update_Status__c, KB_Article_Link__c, updated content
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('SCENARIO B ── UPDATE existing KB article from Case');
System.debug('───────────────────────────────────────────────────');

// Resolve the Knowledge__kav.Id from the KnowledgeArticleId we just created
Knowledge__kav targetKav = [
    SELECT Id, KnowledgeArticleId, Title, Resolution__c, PublishStatus
    FROM Knowledge__kav
    WHERE KnowledgeArticleId = :newArticleKaId
      AND PublishStatus IN ('Draft', 'Online')
    ORDER BY LastModifiedDate DESC
    LIMIT 1
];
System.debug('Target KB article   : ' + targetKav.Title + '  (Id: ' + targetKav.Id + ')');

// Step 1: Create a new Case (follow-up question on same topic)
Case caseB = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Subject       = marker + ' Dragon Medical One still crashing after driver update — extra steps?',
    SuppliedName  = 'Bob Test',
    SuppliedEmail = 'bob-cursor-test@example.com'
);
insert caseB;
System.debug('Step 1 — Case created: ' + caseB.Id);

// Step 2: Simulate AI resolution
String aiAnswerB =
    '<p><strong>Additional Fix:</strong> If Dragon Medical One still crashes after the driver update, ' +
    'also disable Windows Fast Startup (Power Options → Turn on fast startup → uncheck) and set ' +
    'the microphone exclusivity mode to OFF in Sound settings. This resolves 95% of remaining crashes.</p>';

update new Case(
    Id            = caseB.Id,
    Status        = 'Closed',
    Description   = 'Dragon Medical One still crashing after driver update — Fast Startup conflict.',
    Summary__c    = aiAnswerB,
    Resolution__c = aiAnswerB
);
System.debug('Step 2 — Case resolved with AI answer');

// Step 3: Simulate KB Builder Agent response → UPDATE (references the article from Scenario A)
ccai__AI_Response__c aiRespB = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: UPDATE\n' +
        'ArticleId: ' + targetKav.Id + '\n' +
        'Question: "Dragon Medical One still crashing after driver update?"\n' +
        'Answer: "If Dragon Medical One still crashes after updating the audio driver: ' +
        '1. Disable Windows Fast Startup (Power Options → uncheck). ' +
        '2. Set microphone exclusivity mode to OFF in Sound settings. ' +
        '3. Run Dragon as Administrator for first launch. ' +
        'This resolves 95% of remaining post-update crash reports."',
    ccai__Record_Id__c = String.valueOf(caseB.Id)
);
new KbArticleBuilderAction().invokeApex(aiRespB);
System.debug('Step 3 — KbArticleBuilderAction invoked (UPDATE)');

// Step 4: Verify
Case afterB       = [SELECT Status, KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :caseB.Id];
List<CaseArticle> linksB = [SELECT KnowledgeArticleId FROM CaseArticle WHERE CaseId = :caseB.Id];
Knowledge__kav updatedKav = [SELECT Resolution__c FROM Knowledge__kav WHERE Id = :targetKav.Id];

System.debug('');
System.debug('  Status            : ' + afterB.Status);
System.debug('  KB_Update_Status  : ' + afterB.KB_Update_Status__c);
System.debug('  KB_Article_Link   : ' + afterB.KB_Article_Link__c);
System.debug('  CaseArticle count : ' + linksB.size());
System.debug('  Article updated   : ' + (updatedKav.Resolution__c != null && updatedKav.Resolution__c.contains('Fast Startup')));

ok(afterB.Status == 'Closed',                               'Case is Closed');
ok(afterB.KB_Update_Status__c != null
   && afterB.KB_Update_Status__c.startsWith('UPDATE:'),     'KB_Update_Status starts with UPDATE:');
ok(String.isNotBlank(afterB.KB_Article_Link__c),            'KB_Article_Link__c is populated');
ok(afterB.KB_Article_Link__c.startsWith('https://'),        'KB_Article_Link__c is absolute URL');
ok(!linksB.isEmpty(),                                       'CaseArticle link created');
ok(updatedKav.Resolution__c != null
   && updatedKav.Resolution__c.contains('Fast Startup'),    'KB article content updated with new answer');

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('════════════════════════════════════════════════════════');
System.debug('  RESULTS: ' + passed + ' passed  |  ' + failed + ' failed');
System.debug('════════════════════════════════════════════════════════');
System.debug('');
System.debug('SCENARIO A — Case (CREATE): ' + baseUrl + '/lightning/r/Case/' + caseA.Id + '/view');
System.debug('SCENARIO B — Case (UPDATE): ' + baseUrl + '/lightning/r/Case/' + caseB.Id + '/view');
System.debug('KB Article (created & updated): ' + baseUrl + '/lightning/r/Knowledge__kav/' + targetKav.Id + '/view');
System.debug('Marker: ' + marker);
