// Diagnostic: call Question Clarifier Agent directly and dump the raw response body
// so we can see what format the agent actually returns via invokeAgent().
String testQuestion = 'My ScanSnap iX500 scanner is not showing up in Power PDF after I upgraded to 2025.3';

ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName   = 'Question_Clarifier_Agent';
req.userMessage = testQuestion;

ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);

System.debug('=== CLARIFIER AGENT DIAGNOSTIC ===');
if (resp == null) {
    System.debug('RESULT: response is NULL');
} else {
    System.debug('status: '       + resp.status);
    System.debug('responseBody length: ' + (resp.responseBody == null ? 'NULL' : String.valueOf(resp.responseBody.length())));
    System.debug('responseBody: ' + resp.responseBody);

    if (String.isNotBlank(resp.responseBody)) {
        // Run through the same normalization as CaseQuestionClarifierAgentService
        String body = resp.responseBody;
        if (body.contains('<')) {
            body = body.replaceAll('(?i)<br\\s*/?>', '\n')
                       .replaceAll('(?i)</p>', '\n')
                       .replaceAll('(?i)</div>', '\n')
                       .replaceAll('(?i)</li>', '\n')
                       .stripHtmlTags();
        }
        body = body
            .replaceAll('(?i)(?<!\\n)(Clarification\\s+\\d+:)', '\n$1')
            .replaceAll('(?i)(?<!\\n)(Options:)', '\nOptions:')
            .replaceAll('\\*\\*', '')
            .replaceAll('(\r?\n){3,}', '\n\n')
            .trim();

        System.debug('=== NORMALIZED BODY ===');
        System.debug(body);

        // Attempt to parse
        String jsonResult = QuestionClarifierAction.buildJson(body);
        System.debug('=== PARSE RESULT ===');
        System.debug('buildJson returned: ' + (jsonResult == null ? 'NULL (parse failed)' : jsonResult));
    }
}
System.debug('=== END DIAGNOSTIC ===');
