// Verifies the manual resolution → KB creation path is fully wired.
// Simulates exactly what happens when an agent types a resolution in the
// caseResolveAction LWC and clicks Save with "Create KB article" checked.

String marker  = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
Integer passed = 0;
Integer failed = 0;

void ok(Boolean condition, String label) {
    if (condition) { System.debug('  ✓ PASS: ' + label); passed++; }
    else           { System.debug('  ✗ FAIL: ' + label); failed++; }
}

System.debug('');
System.debug('══════════════════════════════════════════════════════════════');
System.debug('  MANUAL RESOLUTION → KB PATH TEST   marker: ' + marker);
System.debug('══════════════════════════════════════════════════════════════');

// ── Step 1: Agent opens Case, types a resolution, clicks Save ────────────────
// Simulate CaseResolveActionController.saveResolution(caseId, text, createKb=true)

Case c = new Case(
    Origin       = 'Web',
    Status       = 'New',
    Subject      = marker + ' Kofax TotalAgility fails to start after Windows Server 2022 update',
    SuppliedName = 'Agent Test',
    SuppliedEmail= 'cursor-agent@example.com'
);
insert c;
System.debug('Case created: ' + c.Id);

// Call the actual controller method exactly as the LWC does
CaseResolveActionController.SaveResult result = CaseResolveActionController.saveResolution(
    c.Id,
    'Kofax TotalAgility fails to start after Windows Server 2022 KB5025272 update. ' +
    'Resolution: 1. Open Services.msc and locate "KTA Workflow Agent". ' +
    '2. Right-click → Properties → Log On tab. ' +
    '3. Change to "This Account" and re-enter the service account credentials. ' +
    '4. Restart the service. Root cause: KB5025272 resets service account permissions.',
    true
);

System.debug('SaveResult.caseClosed    : ' + result.caseClosed);
System.debug('SaveResult.articleQueued : ' + result.articleQueued);

// ── Step 2: Verify Case fields written correctly ─────────────────────────────
Case afterSave = [
    SELECT Status, Resolution__c, Description, KB_Update_Status__c
    FROM Case WHERE Id = :c.Id
];

System.debug('');
System.debug('After saveResolution():');
System.debug('  Status           : ' + afterSave.Status);
System.debug('  Resolution__c    : ' + (String.isNotBlank(afterSave.Resolution__c) ? afterSave.Resolution__c.left(80) + '...' : 'BLANK'));
System.debug('  Description      : ' + (String.isNotBlank(afterSave.Description) ? afterSave.Description.left(80) + '...' : 'BLANK ✗'));
System.debug('  KB_Update_Status : ' + afterSave.KB_Update_Status__c);

ok(afterSave.Status == 'Closed',                              'Case is Closed');
ok(result.caseClosed == true,                                 'SaveResult.caseClosed = true');
ok(result.articleQueued == true,                              'SaveResult.articleQueued = true');
ok(String.isNotBlank(afterSave.Resolution__c),                'Resolution__c written');
ok(String.isNotBlank(afterSave.Description),                  'Description written (KB prompt can read it)');
ok(afterSave.Description == afterSave.Resolution__c,          'Description = Resolution__c (same content)');
ok(afterSave.KB_Update_Status__c != null &&
   afterSave.KB_Update_Status__c.startsWith('UPDATE QUEUED'), 'KB_Update_Status = UPDATE QUEUED');

// ── Step 3: Simulate KB Builder Agent receiving the answer → CREATE article ──
// (In production, KbCreationService → KbMatchAgentService → GPTfy KB Builder prompt
//  → KbArticleBuilderAction would run async. We verify it works with the fix in place.)

ccai__AI_Response__c aiResp = new ccai__AI_Response__c(
    ccai__AI_Processed_Data_PII_Added__c =
        'Action: CREATE\n' +
        'ArticleId:\n' +
        'Question: "Kofax TotalAgility fails to start after Windows Server 2022 update"\n' +
        'Answer: "' + afterSave.Description.replace('"', '\'') + '"',
    ccai__Record_Id__c = String.valueOf(c.Id)
);
new KbArticleBuilderAction().invokeApex(aiResp);

// ── Step 4: Verify KB article created and linked ─────────────────────────────
Case afterKb = [
    SELECT KB_Update_Status__c, KB_Article_Link__c
    FROM Case WHERE Id = :c.Id
];
List<CaseArticle> links = [SELECT KnowledgeArticleId FROM CaseArticle WHERE CaseId = :c.Id];

System.debug('');
System.debug('After KbArticleBuilderAction:');
System.debug('  KB_Update_Status : ' + afterKb.KB_Update_Status__c);
System.debug('  KB_Article_Link  : ' + afterKb.KB_Article_Link__c);
System.debug('  CaseArticle link : ' + (links.isEmpty() ? 'NONE' : links[0].KnowledgeArticleId));

ok(afterKb.KB_Update_Status__c != null &&
   afterKb.KB_Update_Status__c.startsWith('CREATE:'),         'KB_Update_Status = CREATE:');
ok(String.isNotBlank(afterKb.KB_Article_Link__c),             'KB_Article_Link__c populated');
ok(afterKb.KB_Article_Link__c.startsWith('https://'),         'KB_Article_Link__c is absolute URL');
ok(!links.isEmpty(),                                          'CaseArticle junction created');

// ── Summary ──────────────────────────────────────────────────────────────────
System.debug('');
System.debug('══════════════════════════════════════════════════════════════');
System.debug('  RESULTS: ' + passed + ' passed  |  ' + failed + ' failed');
System.debug('══════════════════════════════════════════════════════════════');
System.debug('Case: ' + baseUrl + '/lightning/r/Case/' + c.Id + '/view');
System.debug('Marker: ' + marker);
