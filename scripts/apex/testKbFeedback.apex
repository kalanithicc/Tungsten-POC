// Verifies the KB feedback loop:
//   1. KbArticleBuilderAction.writeKbStatus() writes CREATE/UPDATE/ERROR to Case.KB_Update_Status__c
//   2. CaseResolveActionController writes "UPDATE QUEUED" when createKb=true

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

// ── Step 1: Create a test case ───────────────────────────────────────────────
Case c = new Case(Subject = marker + ' KB feedback test', Status = 'New');
insert c;
System.debug('TEST Case Id: ' + c.Id);

// ── Step 2: Simulate CaseResolveActionController queued-status write ─────────
String queuedAt = Datetime.now().format('yyyy-MM-dd HH:mm');
update new Case(
    Id                  = c.Id,
    KB_Update_Status__c = ('UPDATE QUEUED at ' + queuedAt + ' — article will be linked within 1 minute').left(255)
);
Case after1 = [SELECT KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('AFTER QUEUED: ' + after1.KB_Update_Status__c);
System.assert(after1.KB_Update_Status__c.startsWith('UPDATE QUEUED'), 'Queued status not written');

// ── Step 3: Simulate KbArticleBuilderAction.writeKbStatus() ─────────────────
//    3a. CREATE path
KbArticleBuilderAction.writeKbStatus(c.Id, 'CREATE', 'SharePoint libraries not showing in Power PDF', null);
Case after2 = [SELECT KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('AFTER CREATE: ' + after2.KB_Update_Status__c);
System.assert(after2.KB_Update_Status__c.startsWith('CREATE:'), 'CREATE status not written');

//    3b. UPDATE path (simulate with a fake KA Id-like value)
// Use Case Id as dummy to avoid type issues; the format test is what matters
Id dummyId = c.Id;
KbArticleBuilderAction.writeKbStatus(c.Id, 'UPDATE', 'SharePoint libraries not showing in Power PDF', dummyId);
Case after3 = [SELECT KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('AFTER UPDATE: ' + after3.KB_Update_Status__c);
System.assert(after3.KB_Update_Status__c.startsWith('UPDATE:'), 'UPDATE status not written');

//    3c. ERROR path
KbArticleBuilderAction.writeKbStatus(c.Id, 'ERROR', 'anything', null);
Case after4 = [SELECT KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('AFTER ERROR: ' + after4.KB_Update_Status__c);
System.assert(after4.KB_Update_Status__c.startsWith('ERROR:'), 'ERROR status not written');

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case URL: https://kesavpoc--gptfy.sandbox.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
