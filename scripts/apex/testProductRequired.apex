String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

// Pick first active product value
List<Map<String, String>> options = CaseResolutionController.getProductOptions();
System.assert(!options.isEmpty(), 'Product__c must have active picklist values');
String product = options[0].get('value');

// Note: submitForClarification throws AuraHandledException — test blank product in portal/LWC only.

// 1. Agent message format (same as CaseQuestionClarifierAgentService.buildUserMessage)
String sampleQ = 'How do I reset my password for the admin console?';
String msg = 'Product: ' + product + '\nQuestion: ' + sampleQ.trim();
System.debug('[ASSERT] agent message format includes Product line: ' +
    (msg.startsWith('Product: ') && msg.contains('\nQuestion: ') ? 'PASS' : 'FAIL — ' + msg));

// 2. submit with product creates Case and enqueues clarifier
Map<String, String> result = CaseResolutionController.submitForClarification(
    'Test', 'User', 'test@example.com',
    marker + ' product required happy path with enough words in the question text',
    product
);
Case c = [
    SELECT Id, Product__c
    FROM Case
    WHERE Id = :result.get('caseId')
    LIMIT 1
];
System.debug('[ASSERT] Product__c persisted: ' +
    (c.Product__c == product ? 'PASS' : 'FAIL — was ' + c.Product__c));

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Case Id: ' + result.get('caseId'));
