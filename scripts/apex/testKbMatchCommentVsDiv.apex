String commentFormat =
    '<!--\nKB_MATCHES_START\nNONE\nKB_MATCHES_END\n-->\n' +
    '<!--\nKB_UPDATE_SCOPE_START\nREASON_MISSED: test\nUPDATE_NEEDED: YES\nSCOPE: test\nKB_UPDATE_SCOPE_END\n-->';

String divFormat =
    '<div>KB_MATCHES_START<br>PDF thumbnails are not displayed in Windows Explorer after installing Power PDF<br>KB_MATCHES_END</div>' +
    '<div>KB_UPDATE_SCOPE_START<br>REASON_MISSED: test<br>KB_UPDATE_SCOPE_END</div>';

for (String label : new List<String>{ 'comment', 'div' }) {
    String raw = label == 'comment' ? commentFormat : divFormat;
    String norm = KbMatchAgentService.normalizeAgentResponse(raw);
    List<String> titles = KbMatchAgentService.parseMatchTitles(norm);
    System.debug('=== ' + label + ' ===');
    System.debug('normalized len=' + norm.length() + ' preview=' + norm.abbreviate(200));
    System.debug('titles=' + titles + ' count=' + titles.size());
    System.debug('has MATCH markers=' + norm.contains('KB_MATCHES_START'));
    System.debug('has SCOPE markers=' + norm.contains('KB_UPDATE_SCOPE_START'));
}
