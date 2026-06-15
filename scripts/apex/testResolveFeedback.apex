// Verifies that KB_Update_Status__c is written in the SAME DML as case close
// so it never fails due to closed-case editing restrictions.

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

Case c = new Case(Subject = marker + ' resolve-feedback test', Status = 'New');
insert c;

// Simulate saveResolution(caseId, text, createKb=true) via direct DML
// (mirrors the single-DML approach now in CaseResolveActionController)
String queuedAt = Datetime.now().format('yyyy-MM-dd HH:mm');
update new Case(
    Id            = c.Id,
    Resolution__c = 'Test resolution for ' + marker,
    Status        = 'Closed',
    KB_Update_Status__c = ('UPDATE QUEUED at ' + queuedAt + ' — article will be linked within 1 min').left(255)
);

Case after = [SELECT Status, Resolution__c, KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('Status: '             + after.Status);
System.debug('Resolution: '         + after.Resolution__c);
System.debug('KB_Update_Status: '   + after.KB_Update_Status__c);

System.assert(after.Status == 'Closed',                              'Case should be Closed');
System.assert(String.isNotBlank(after.KB_Update_Status__c),          'KB_Update_Status__c should be written');
System.assert(after.KB_Update_Status__c.startsWith('UPDATE QUEUED'), 'Status should start with UPDATE QUEUED');

// Simulate KbArticleBuilderAction writing the final result
KbArticleBuilderAction.writeKbStatus(c.Id, 'CREATE', marker + ' KB Article', null);
Case afterCreate = [SELECT KB_Update_Status__c FROM Case WHERE Id = :c.Id];
System.debug('KB_Update_Status final: ' + afterCreate.KB_Update_Status__c);
System.assert(afterCreate.KB_Update_Status__c.startsWith('CREATE:'), 'Final status should start with CREATE:');

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case: https://kesavpoc--gptfy.sandbox.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
