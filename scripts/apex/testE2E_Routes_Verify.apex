/**
 * End-to-End Test — ALL 4 ROUTES — VERIFICATION
 *
 * Run AFTER testE2E_Routes_Setup.apex and waiting 5+ minutes for async jobs.
 *
 * Route 1: Self-service YES  → Case Closed, Resolution__c set
 * Route 2: Self-service NO   → Case stays open, no Resolution__c
 * Route 3: Agent + KB exists → Case Closed, no KB_Article_Link__c, no CaseArticle
 * Route 4: Agent + no match  → Case Closed, KB_Article_Link__c set, CaseArticle created
 */
Integer passed = 0;
Integer failed = 0;
List<String> report = new List<String>();

// ─── Find the 4 most recent cursor-test cases by route label ─────────────────
List<Case> allCases = [
    SELECT Id, Subject, Status, Resolution__c, Summary__c, Description,
           KB_Article_Link__c, KB_Candidates__c
    FROM Case
    WHERE Subject LIKE 'cursor-test-%'
      AND (Subject LIKE '% R1:%' OR Subject LIKE '% R2:%'
           OR Subject LIKE '% R3:%' OR Subject LIKE '% R4:%')
    ORDER BY CreatedDate DESC
    LIMIT 8
];

if (allCases.isEmpty()) {
    System.debug('ERROR: No test cases found. Run testE2E_Routes_Setup.apex first.');
    return;
}

Case r1 = null; Case r2 = null; Case r3 = null; Case r4 = null;
for (Case c : allCases) {
    if (r1 == null && c.Subject.contains(' R1:')) r1 = c;
    if (r2 == null && c.Subject.contains(' R2:')) r2 = c;
    if (r3 == null && c.Subject.contains(' R3:')) r3 = c;
    if (r4 == null && c.Subject.contains(' R4:')) r4 = c;
}

System.debug('');
System.debug('================================================================');
System.debug('E2E VERIFICATION REPORT');
System.debug('================================================================');

// ─── Route 1: Self-service YES → Closed ─────────────────────────────────────
System.debug('');
System.debug('ROUTE 1 — Self-service: customer says YES → Case should be Closed');
if (r1 == null) {
    report.add('R1 SKIP: case not found');
    System.debug('  SKIP: Route 1 case not found. Re-run setup.');
} else {
    System.debug('  Case Id: ' + r1.Id);
    System.debug('  Status: ' + r1.Status);
    System.debug('  Resolution__c length: ' + (r1.Resolution__c == null ? 'null' : String.valueOf(r1.Resolution__c.length())));
    // Assert: Status = Closed
    if (r1.Status == 'Closed') {
        passed++; System.debug('  [PASS] Status = Closed');
    } else {
        failed++; System.debug('  [FAIL] Status expected Closed, got: ' + r1.Status + ' (event may still be processing)');
    }
    // Assert: Resolution__c set by CaseResolvedTrigger from Summary__c
    if (String.isNotBlank(r1.Resolution__c)) {
        passed++; System.debug('  [PASS] Resolution__c is populated');
    } else {
        failed++; System.debug('  [FAIL] Resolution__c is blank — CaseResolvedTrigger may not have fired');
    }
    // Assert: No KB link (self-service route never creates KB)
    if (String.isBlank(r1.KB_Article_Link__c)) {
        passed++; System.debug('  [PASS] KB_Article_Link__c is blank (correct — not a KB route)');
    } else {
        failed++; System.debug('  [FAIL] KB_Article_Link__c unexpectedly set: ' + r1.KB_Article_Link__c);
    }
    System.debug('  URL: /lightning/r/Case/' + r1.Id + '/view');
}

// ─── Route 2: Self-service NO → stays open ──────────────────────────────────
System.debug('');
System.debug('ROUTE 2 — Self-service: customer says NO → Case should stay open');
if (r2 == null) {
    report.add('R2 SKIP: case not found');
    System.debug('  SKIP: Route 2 case not found. Re-run setup.');
} else {
    System.debug('  Case Id: ' + r2.Id);
    System.debug('  Status: ' + r2.Status);
    System.debug('  Summary__c length: ' + (r2.Summary__c == null ? 'null' : String.valueOf(r2.Summary__c.length())));
    // Assert: Status is NOT Closed
    if (r2.Status != 'Closed') {
        passed++; System.debug('  [PASS] Status = ' + r2.Status + ' (not Closed — correct)');
    } else {
        failed++; System.debug('  [FAIL] Status is Closed — resolveCase() should NOT have been called');
    }
    // Assert: No Resolution__c (only set by CaseResolvedTrigger which fires on YES)
    if (String.isBlank(r2.Resolution__c)) {
        passed++; System.debug('  [PASS] Resolution__c is blank (customer did not confirm resolved)');
    } else {
        failed++; System.debug('  [FAIL] Resolution__c is set unexpectedly: ' + r2.Resolution__c.abbreviate(100));
    }
    // Assert: AI answer (Summary__c) is still there for the agent to see
    if (String.isNotBlank(r2.Summary__c)) {
        passed++; System.debug('  [PASS] Summary__c (AI answer) is present for agent review');
    } else {
        failed++; System.debug('  [FAIL] Summary__c is blank — AI answer missing');
    }
    // Assert: getRecommendation() still returns content (useful for agent view)
    String rec2 = CaseResolutionController.getRecommendation(r2.Id);
    if (String.isNotBlank(rec2)) {
        passed++; System.debug('  [PASS] getRecommendation() returns content (' + rec2.length() + ' chars)');
    } else {
        failed++; System.debug('  [FAIL] getRecommendation() returned blank');
    }
    System.debug('  URL: /lightning/r/Case/' + r2.Id + '/view');
}

// ─── Route 3: Agent + KB exists → SKIP ──────────────────────────────────────
System.debug('');
System.debug('ROUTE 3 — Agent resolve + KB exists → Should SKIP creation, no link');
if (r3 == null) {
    report.add('R3 SKIP: case not found');
    System.debug('  SKIP: Route 3 case not found. Re-run setup.');
} else {
    System.debug('  Case Id: ' + r3.Id);
    System.debug('  Status: ' + r3.Status);
    System.debug('  KB_Article_Link__c: ' + (String.isBlank(r3.KB_Article_Link__c) ? '<blank>' : r3.KB_Article_Link__c));
    System.debug('  KB_Candidates__c (scope): ' + (String.isBlank(r3.KB_Candidates__c) ? '<blank>' : r3.KB_Candidates__c.abbreviate(120)));
    List<CaseArticle> r3Articles = [SELECT Id FROM CaseArticle WHERE CaseId = :r3.Id LIMIT 1];
    // Assert: Case closed by saveResolution
    if (r3.Status == 'Closed') {
        passed++; System.debug('  [PASS] Status = Closed');
    } else {
        failed++; System.debug('  [FAIL] Status expected Closed, got: ' + r3.Status);
    }
    // Assert: Resolution__c set by saveResolution
    if (String.isNotBlank(r3.Resolution__c)) {
        passed++; System.debug('  [PASS] Resolution__c populated by agent');
    } else {
        failed++; System.debug('  [FAIL] Resolution__c is blank');
    }
    // Assert: No KB_Article_Link__c (skipped path never calls writeKbArticleLink)
    if (String.isBlank(r3.KB_Article_Link__c)) {
        passed++; System.debug('  [PASS] KB_Article_Link__c blank (SKIP worked — no new article)');
    } else {
        failed++; System.debug('  [FAIL] KB_Article_Link__c is set unexpectedly — should have been SKIPPED: ' + r3.KB_Article_Link__c);
    }
    // Assert: KB Update Scope populated on skip path
    if (String.isNotBlank(r3.KB_Candidates__c)) {
        passed++; System.debug('  [PASS] KB_Candidates__c (KB Update Scope) populated');
    } else {
        failed++; System.debug('  [FAIL] KB_Candidates__c blank — skip scope not written (async may still be running)');
    }
    // Assert: No CaseArticle created
    if (r3Articles.isEmpty()) {
        passed++; System.debug('  [PASS] No CaseArticle junction — confirmed no KB article was linked');
    } else {
        failed++; System.debug('  [FAIL] CaseArticle exists (' + r3Articles[0].Id + ') — article was created when it should have been skipped');
    }
    System.debug('  URL: /lightning/r/Case/' + r3.Id + '/view');
}

// ─── Route 4: Agent + no match → CREATE ─────────────────────────────────────
System.debug('');
System.debug('ROUTE 4 — Agent resolve + no KB match → Should CREATE new KB article + link');
if (r4 == null) {
    report.add('R4 SKIP: case not found');
    System.debug('  SKIP: Route 4 case not found. Re-run setup.');
} else {
    System.debug('  Case Id: ' + r4.Id);
    System.debug('  Status: ' + r4.Status);
    System.debug('  KB_Article_Link__c: ' + (String.isBlank(r4.KB_Article_Link__c) ? '<blank>' : r4.KB_Article_Link__c));
    List<CaseArticle> r4Articles = [
        SELECT Id, KnowledgeArticleId FROM CaseArticle WHERE CaseId = :r4.Id LIMIT 1
    ];
    Knowledge__kav kbArticle = null;
    if (!r4Articles.isEmpty()) {
        List<Knowledge__kav> kavList = [
            SELECT Id, Title, PublishStatus
            FROM Knowledge__kav
            WHERE KnowledgeArticleId = :r4Articles[0].KnowledgeArticleId
            LIMIT 1
        ];
        kbArticle = kavList.isEmpty() ? null : kavList[0];
    }
    // Assert: Case closed
    if (r4.Status == 'Closed') {
        passed++; System.debug('  [PASS] Status = Closed');
    } else {
        failed++; System.debug('  [FAIL] Status expected Closed, got: ' + r4.Status);
    }
    // Assert: Resolution__c set
    if (String.isNotBlank(r4.Resolution__c)) {
        passed++; System.debug('  [PASS] Resolution__c populated by agent');
    } else {
        failed++; System.debug('  [FAIL] Resolution__c is blank');
    }
    // Assert: KB_Article_Link__c populated
    if (String.isNotBlank(r4.KB_Article_Link__c)) {
        passed++; System.debug('  [PASS] KB_Article_Link__c set: ' + r4.KB_Article_Link__c);
    } else {
        failed++; System.debug('  [FAIL] KB_Article_Link__c is blank — async KB creation not complete yet, or failed');
    }
    // Assert: CaseArticle junction created
    if (!r4Articles.isEmpty()) {
        passed++; System.debug('  [PASS] CaseArticle junction record exists: ' + r4Articles[0].Id);
    } else {
        failed++; System.debug('  [FAIL] No CaseArticle found — KB article not linked to case');
    }
    // Assert: Knowledge__kav exists
    if (kbArticle != null) {
        passed++; System.debug('  [PASS] Knowledge article exists: "' + kbArticle.Title + '" (Status: ' + kbArticle.PublishStatus + ')');
    } else {
        failed++; System.debug('  [FAIL] Knowledge__kav article not found in org');
    }
    System.debug('  URL: /lightning/r/Case/' + r4.Id + '/view');
}

// ─── Final score ─────────────────────────────────────────────────────────────
System.debug('');
System.debug('================================================================');
System.debug('RESULT: ' + passed + ' PASSED  |  ' + failed + ' FAILED');
if (failed == 0) {
    System.debug('STATUS: ALL ROUTES VERIFIED — solution is end-to-end healthy.');
} else if (failed <= 2) {
    System.debug('STATUS: MOSTLY PASSING — check FAIL details above. ' +
        'If Route 3/4 async jobs are still running, wait 2 more min and re-run.');
} else {
    System.debug('STATUS: MULTIPLE FAILURES — review the FAIL lines above carefully.');
}
System.debug('================================================================');
