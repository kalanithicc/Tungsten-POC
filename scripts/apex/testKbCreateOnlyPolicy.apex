// Verifies the "CREATE only, never UPDATE" policy:
//
// PATH A — SKIP: case where KB Matcher finds an existing article → no article created
// PATH B — CREATE: case where no match exists → new article created
// PATH C — SAFETY NET: even if prompt returns UPDATE → we CREATE anyway

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
System.debug('  CREATE-ONLY POLICY TEST   marker: ' + marker);
System.debug('════════════════════════════════════════════════════════');

// ─────────────────────────────────────────────────────────────────────────────
// PATH A — SKIP (Tier 2 match found → stop, no article created)
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('PATH A ── SKIP (existing article found by KB Matcher)');

// Pick any existing KB article to act as the "match"
Knowledge__kav existingKav = [
    SELECT Id, Title, KnowledgeArticleId
    FROM Knowledge__kav
    WHERE PublishStatus IN ('Draft', 'Online')
    ORDER BY CreatedDate DESC
    LIMIT 1
];
System.debug('  Existing article: ' + existingKav.Title);

Case caseA = new Case(
    Origin = 'Web', Status = 'New',
    Subject = marker + ' skip test — ' + existingKav.Title.left(80),
    SuppliedName = 'Skip Test', SuppliedEmail = 'cursor-skip@example.com'
);
insert caseA;

// Simulate KbMatchAgentService finding the existing article
List<Knowledge__kav> matched = new List<Knowledge__kav>{ existingKav };
if (!matched.isEmpty()) {
    String skipStatus = ('SKIPPED: Similar KB article already exists — ' +
        matched[0].Title).left(255);
    update new Case(Id = caseA.Id, KB_Update_Status__c = skipStatus);
}

Integer articlesBefore = [SELECT COUNT() FROM CaseArticle WHERE CaseId = :caseA.Id];
Case afterA = [SELECT KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :caseA.Id];

System.debug('  KB_Update_Status : ' + afterA.KB_Update_Status__c);
System.debug('  KB_Article_Link  : ' + afterA.KB_Article_Link__c);
System.debug('  New articles     : ' + articlesBefore);

ok(afterA.KB_Update_Status__c != null &&
   afterA.KB_Update_Status__c.startsWith('SKIPPED:'),     'KB_Update_Status starts with SKIPPED:');
ok(String.isBlank(afterA.KB_Article_Link__c),             'KB_Article_Link__c is blank (no new article)');
ok(articlesBefore == 0,                                   'No CaseArticle created');

// ─────────────────────────────────────────────────────────────────────────────
// PATH B — CREATE (no match found → new article created)
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('PATH B ── CREATE (no existing article, new one created)');

Case caseB = new Case(
    Origin = 'Web', Status = 'New',
    Subject = marker + ' How to configure SMTP relay in Nuance Vocalizer Enterprise?',
    SuppliedName = 'Create Test', SuppliedEmail = 'cursor-create@example.com'
);
insert caseB;

ccai__AI_Response__c respB = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: CREATE\n' +
        'ArticleId:\n' +
        'Question: "How to configure SMTP relay in Nuance Vocalizer Enterprise?"\n' +
        'Answer: "To configure SMTP relay: 1. Open Vocalizer Admin Console. ' +
        '2. Go to Settings > Notifications > SMTP. ' +
        '3. Enter relay host, port 587, and TLS credentials. ' +
        '4. Click Test Connection, then Save."',
    ccai__Record_Id__c = String.valueOf(caseB.Id)
);
new KbArticleBuilderAction().invokeApex(respB);

Case afterB = [SELECT KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :caseB.Id];
List<CaseArticle> linksB = [SELECT Id FROM CaseArticle WHERE CaseId = :caseB.Id];

System.debug('  KB_Update_Status : ' + afterB.KB_Update_Status__c);
System.debug('  KB_Article_Link  : ' + afterB.KB_Article_Link__c);
System.debug('  CaseArticle count: ' + linksB.size());

ok(afterB.KB_Update_Status__c != null &&
   afterB.KB_Update_Status__c.startsWith('CREATE:'),      'KB_Update_Status starts with CREATE:');
ok(String.isNotBlank(afterB.KB_Article_Link__c),          'KB_Article_Link__c is populated');
ok(afterB.KB_Article_Link__c.startsWith('https://'),      'KB_Article_Link__c is absolute URL');
ok(!linksB.isEmpty(),                                     'CaseArticle link created');

// ─────────────────────────────────────────────────────────────────────────────
// PATH C — SAFETY NET (prompt says UPDATE → still CREATE)
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('PATH C ── SAFETY NET (prompt returns UPDATE → we CREATE anyway)');

Knowledge__kav targetForUpdate = [
    SELECT Id FROM Knowledge__kav
    WHERE PublishStatus IN ('Draft','Online')
    ORDER BY CreatedDate DESC LIMIT 1
];

Case caseC = new Case(
    Origin = 'Web', Status = 'New',
    Subject = marker + ' safety net test — UPDATE ignored',
    SuppliedName = 'Safety Test', SuppliedEmail = 'cursor-safety@example.com'
);
insert caseC;

Integer kbCountBefore = [SELECT COUNT() FROM Knowledge__kav];

ccai__AI_Response__c respC = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: UPDATE\n' +
        'ArticleId: ' + targetForUpdate.Id + '\n' +
        'Question: "Safety net test question?"\n' +
        'Answer: "Safety net test answer — this should trigger CREATE not UPDATE."',
    ccai__Record_Id__c = String.valueOf(caseC.Id)
);
new KbArticleBuilderAction().invokeApex(respC);

Integer kbCountAfter = [SELECT COUNT() FROM Knowledge__kav];
Case afterC = [SELECT KB_Update_Status__c, KB_Article_Link__c FROM Case WHERE Id = :caseC.Id];

System.debug('  KB articles before: ' + kbCountBefore + ' → after: ' + kbCountAfter);
System.debug('  KB_Update_Status  : ' + afterC.KB_Update_Status__c);

ok(kbCountAfter == kbCountBefore + 1,                     'New KB article was CREATED (not updated)');
ok(afterC.KB_Update_Status__c != null &&
   afterC.KB_Update_Status__c.startsWith('CREATE:'),      'KB_Update_Status says CREATE: (not UPDATE:)');

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
System.debug('');
System.debug('════════════════════════════════════════════════════════');
System.debug('  RESULTS: ' + passed + ' passed  |  ' + failed + ' failed');
System.debug('════════════════════════════════════════════════════════');
System.debug('PATH A (SKIP)  Case: ' + baseUrl + '/lightning/r/Case/' + caseA.Id + '/view');
System.debug('PATH B (CREATE) Case: ' + baseUrl + '/lightning/r/Case/' + caseB.Id + '/view');
System.debug('PATH C (SAFETY) Case: ' + baseUrl + '/lightning/r/Case/' + caseC.Id + '/view');
System.debug('Marker: ' + marker);
