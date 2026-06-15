// Quick probe: does SOSL find an existing article for the Route 3 subject?
String subject = 'cursor-test-R3-TotalAgility service crash after Windows Server update';
String cands = KbCandidateSearchService.searchAndSerialize(subject);
System.debug('SOSL result (abbrev 400): ' + cands.abbreviate(400));
System.debug('Is NONE? ' + KbCandidateSearchService.NONE_MARKER.equals(cands));

// Also check what buildSearchTerms extracts
// (we have to test this via a fresh SOQL since the static method is @TestVisible only)
String subjectNorm = subject.toLowerCase().replaceAll('[^a-z0-9\\s]', ' ').replaceAll('\\s+', ' ').trim();
System.debug('Normalized subject: ' + subjectNorm);

// Direct SOSL to confirm
List<List<SObject>> results = [
    FIND 'totalagility OR TotalAgility OR agility'
    IN ALL FIELDS
    RETURNING Knowledge__kav(Id, Title, PublishStatus LIMIT 5)
];
System.debug('Direct SOSL for "totalagility" found: ' +
    (results.isEmpty() || results[0].isEmpty() ? '0 records' : String.valueOf(results[0].size()) + ' records'));
if (!results.isEmpty()) {
    for (SObject kav : results[0]) {
        System.debug('  → ' + ((Knowledge__kav)kav).Title + ' | ' + ((Knowledge__kav)kav).PublishStatus);
    }
}
