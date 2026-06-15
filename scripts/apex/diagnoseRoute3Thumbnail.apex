String rawPlain =
    'KB_MATCHES_START\n' +
    'How to Disable Thumbnail Generation for PDF Files in Windows 11\n' +
    'Windows 10/11 Explorer Preview Pane doesn\'t work for any file\n' +
    'KB_MATCHES_END';

String rawHtml =
    'KB_MATCHES_START<br>' +
    'How to Disable Thumbnail Generation for PDF Files in Windows 11<br>' +
    'Windows 10/11 Explorer Preview Pane doesn&#39;t work for any file<br>' +
    'KB_MATCHES_END';

for (String label : new List<String>{ 'PLAIN', 'HTML' }) {
    String body = label == 'PLAIN' ? rawPlain : rawHtml;
    List<String> titles = KbMatchAgentService.parseMatchTitles(body);
    System.debug('=== ' + label + ' === count=' + titles.size());
    for (String t : titles) System.debug('  [' + t + ']');
    List<Knowledge__kav> exact = [
        SELECT Id, Title FROM Knowledge__kav
        WHERE Title IN :titles AND PublishStatus IN ('Draft','Online') LIMIT 5
    ];
    System.debug('Exact matches: ' + exact.size());
}
