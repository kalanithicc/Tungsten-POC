// cursor-test: Question Clarification Flow — end-to-end verification
// Note: Uses SObject.put() for new fields to work around the anonymous Apex
// schema cache lag in Developer Edition orgs.

String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
System.debug('=== CURSOR TEST: Question Clarification Flow === marker=' + marker);

// ─── 1. Create Case — use deployed controller method to exercise real code path ───
// Invoke CaseResolutionController.submitForClarification() via Invocable
// (deployed code compiles against refreshed schema)
Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(
    JSON.serialize(
        CaseResolutionController.submitForClarification(
            'Cursor', 'Test', 'cursor-test@example.com',
            marker + ' SSO not working tried everything please help',
            null
        )
    )
);
String caseId     = (String) result.get('caseId');
String caseNumber = (String) result.get('caseNumber');

System.debug('[ASSERT] submitForClarification created Case: ' + (caseId != null ? 'PASS' : 'FAIL'));
System.debug('Case Id: ' + caseId + ' | CaseNumber: ' + caseNumber);

// ─── 2. Query via dynamic SOQL to verify AI_Clarification_Pending__c = true ───
List<SObject> rows = Database.query(
    'SELECT Id, AI_Clarification_Pending__c, Intent_Analysis__c FROM Case WHERE Id = \'' + caseId + '\' LIMIT 1'
);
SObject c = rows[0];
Boolean pending = (Boolean) c.get('AI_Clarification_Pending__c');
System.debug('[ASSERT] AI_Clarification_Pending__c=true: ' + (pending == true ? 'PASS' : 'FAIL — was ' + pending));

// ─── 3. Simulate QuestionClarifierAction writing JSON to Intent_Analysis__c ───
String mockJson = '{"cleanedQuestion":"How do I enable SSO in my application?","clarifications":['
    + '{"question":"Which SSO protocol?","options":["SAML 2.0","OAuth 2.0","OIDC","Not sure"]},'
    + '{"question":"What error do you see?","options":["Invalid credentials","Redirect loop","Timeout","No error"]}'
    + ']}';
SObject toUpdate = Schema.getGlobalDescribe().get('Case').newSObject();
toUpdate.put('Id', Id.valueOf(caseId));
toUpdate.put('Intent_Analysis__c', mockJson);
update toUpdate;
System.debug('[ASSERT] Mock clarification JSON written to Intent_Analysis__c: PASS');

// ─── 4. Test getClarification() returns the JSON ───
String clarJson = CaseResolutionController.getClarification(Id.valueOf(caseId));
System.debug('[ASSERT] getClarification() returns JSON: ' + (clarJson != null ? 'PASS — ' + clarJson.abbreviate(150) : 'FAIL — null'));

// ─── 5. Publish platform event (simulate confirmQuestion) ───
CaseResolutionController.confirmQuestion(Id.valueOf(caseId), 'How do I enable SSO? [Protocol: SAML 2.0; Error: Invalid credentials]');
System.debug('[ASSERT] confirmQuestion() published event: PASS (no exception)');

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + caseId);
System.debug('CaseNumber: ' + caseNumber);
System.debug('Org URL: https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + caseId + '/view');
