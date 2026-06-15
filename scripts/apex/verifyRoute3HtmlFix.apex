String rawHtml =
    'KB_MATCHES_START<br>' +
    'How to Disable Thumbnail Generation for PDF Files in Windows 11<br>' +
    'Windows 10/11 Explorer Preview Pane doesn&#39;t work for any file<br>' +
    'KB_MATCHES_END';

String normalized = KbMatchAgentService.normalizeAgentResponse(rawHtml);
List<String> titles = KbMatchAgentService.parseMatchTitles(normalized);

System.debug('Normalized block excerpt: ' + normalized.abbreviate(300));
System.debug('Title count: ' + titles.size());
for (String t : titles) System.debug('  [' + t + ']');

List<Knowledge__kav> exact = [
    SELECT Id, Title FROM Knowledge__kav
    WHERE Title IN :titles AND PublishStatus IN ('Draft','Online') LIMIT 5
];
System.debug('Exact SOQL: ' + exact.size());
for (Knowledge__kav k : exact) System.debug('  matched: ' + k.Title);

System.assert(!exact.isEmpty(), 'HTML agent response must skip when matching article exists');
System.debug('PASS: Route 3 skip confirmed for HTML agent response');
