/**
 * Verifies the 3-tier KB candidate resolution:
 *   1. extractKbRefTitles / stripKbRefsBlock on CaseAgentResolutionService
 *   2. KbCreationService.lookupAndSerializeByRefTitles (Tier 1)
 *   3. KbMatchAgentService.parseMatchTitles parsing
 *
 * Does NOT create live records or invoke GPTfy agents.
 */

System.debug('=== KB CANDIDATE HYBRID TEST START ===');

// ── Test 1: extractKbRefTitles ────────────────────────────────────────────────
String agentResponseWithRefs =
    'To resolve your issue, please follow these steps:\n' +
    '1. Open the settings panel.\n' +
    '2. Click "Reconfigure connector".\n\n' +
    'KB_REFS_START\n' +
    'SharePoint Connector Configuration Guide\n' +
    'Power PDF Advanced SharePoint Integration\n' +
    'KB_REFS_END';

String extracted = CaseAgentResolutionService.extractKbRefTitles(agentResponseWithRefs);
System.debug('Test 1a - extractKbRefTitles: ' + extracted);
System.assert(extracted != null, 'extractKbRefTitles returned null');
System.assert(extracted.contains('REF:SharePoint Connector Configuration Guide'),
    'Expected REF:SharePoint Connector Configuration Guide in: ' + extracted);
System.assert(extracted.contains('REF:Power PDF Advanced SharePoint Integration'),
    'Expected REF:Power PDF Advanced SharePoint Integration in: ' + extracted);

// ── Test 2: stripKbRefsBlock ──────────────────────────────────────────────────
String stripped = CaseAgentResolutionService.stripKbRefsBlock(agentResponseWithRefs);
System.debug('Test 2 - stripped response: ' + stripped);
System.assert(!stripped.contains('KB_REFS_START'), 'KB_REFS_START still present after strip');
System.assert(!stripped.contains('KB_REFS_END'), 'KB_REFS_END still present after strip');
System.assert(!stripped.contains('SharePoint Connector Configuration Guide'), 
    'Article title still present after strip');
System.assert(stripped.contains('Reconfigure connector'), 
    'Main answer content was incorrectly stripped');

// ── Test 3: extractKbRefTitles when no block present ─────────────────────────
String responseNoRefs = 'No relevant information was found in the knowledge base.';
String noRefs = CaseAgentResolutionService.extractKbRefTitles(responseNoRefs);
System.debug('Test 3 - no refs (should be null): ' + noRefs);
System.assert(noRefs == null, 'Expected null when no KB_REFS block');

// ── Test 4: KbCreationService.lookupAndSerializeByRefTitles with real titles ──
// Query a few real published Knowledge articles to get their actual titles
List<Knowledge__kav> existingArticles = [
    SELECT Id, Title, PublishStatus
    FROM Knowledge__kav
    WHERE PublishStatus IN ('Draft', 'Online')
    LIMIT 2
];

if (!existingArticles.isEmpty()) {
    // Build REF: format using real article titles
    List<String> refParts = new List<String>();
    for (Knowledge__kav a : existingArticles) {
        refParts.add('REF:' + a.Title);
    }
    String refString = String.join(refParts, '|');
    System.debug('Test 4 - refString: ' + refString);

    String serialized = KbCreationService.lookupAndSerializeByRefTitles(refString);
    System.debug('Test 4 - serialized candidates (first 500 chars): ' +
        (serialized != null ? serialized.abbreviate(500) : 'NULL'));
    System.assert(serialized != null, 'lookupAndSerializeByRefTitles returned null for real titles');
    System.assert(serialized.contains('CANDIDATE_1'), 'Expected CANDIDATE_1 in serialized output');
} else {
    System.debug('Test 4 - SKIPPED: no published Knowledge articles found in org');
}

// ── Test 5: KbMatchAgentService.parseMatchTitles ─────────────────────────────
String agentMatchResponse =
    'Based on my search, here are the most similar articles:\n\n' +
    'KB_MATCHES_START\n' +
    'SharePoint Connector Configuration Guide\n' +
    'Power PDF Advanced SharePoint Integration\n' +
    'KB_MATCHES_END';

List<String> matchTitles = KbMatchAgentService.parseMatchTitles(agentMatchResponse);
System.debug('Test 5 - parseMatchTitles: ' + matchTitles);
System.assert(matchTitles.size() == 2, 'Expected 2 titles, got ' + matchTitles.size());
System.assert(matchTitles[0] == 'SharePoint Connector Configuration Guide', 'Title 1 mismatch');

// ── Test 6: parseMatchTitles NONE response ────────────────────────────────────
String noneResponse =
    'KB_MATCHES_START\n' +
    'NONE\n' +
    'KB_MATCHES_END';
List<String> noneList = KbMatchAgentService.parseMatchTitles(noneResponse);
System.debug('Test 6 - NONE response (should be empty list): ' + noneList);
System.assert(noneList.isEmpty(), 'Expected empty list for NONE response');

System.debug('=== ALL TESTS PASSED ===');
System.debug('=== KB CANDIDATE HYBRID TEST COMPLETE ===');
