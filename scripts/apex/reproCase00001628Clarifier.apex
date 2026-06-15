String testMessage =
    'Product: PowerPDF\nQuestion: How do I configure to enforce a document retention policy';

ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName   = 'Question_Clarifier_Agent';
req.userMessage = testMessage;

System.debug('=== REPRO CASE 00001628 ===');
System.debug('userMessage: ' + testMessage);

ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);

if (resp == null) {
    System.debug('RESULT: null response');
} else {
    System.debug('status: ' + resp.status);
    System.debug('responseBody length: ' +
        (resp.responseBody == null ? 'NULL' : String.valueOf(resp.responseBody.length())));
    System.debug('responseBody: ' + resp.responseBody);
}
System.debug('=== END ===');
