// Diagnose Route 3: what does KB_Match_Agent return for the scanner resolution?
String userMessage =
    'Find existing knowledge base articles that are semantically similar to this support case:\n' +
    'Question: ScanSnap iX500 scanner not detected in Power PDF 2025.3\n' +
    'Context: Customer\'s ScanSnap iX500 scanner is not detected in Power PDF 2025.3. ' +
    'Checked that the scanner drivers are up to date. Ran the Power PDF repair tool under ' +
    'Help > Repair Installation. Scanner reappeared after the repair completed.';

ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName   = 'KB_Match_Agent';
req.userMessage = userMessage;

ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);

System.debug('=== KB MATCH AGENT RAW RESPONSE ===');
System.debug('responseBody: ' + resp?.responseBody);

// Also show what Published articles exist in org for reference
List<Knowledge__kav> pubs = [
    SELECT Title, PublishStatus FROM Knowledge__kav
    WHERE PublishStatus = 'Online' ORDER BY LastModifiedDate DESC
];
System.debug('Published articles in org: ' + pubs.size());
for (Knowledge__kav k : pubs) {
    System.debug('  - ' + k.Title);
}
System.debug('=== END ===');
