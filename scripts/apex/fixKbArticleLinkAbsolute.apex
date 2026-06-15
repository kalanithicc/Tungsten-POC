// One-time fix: converts relative KB_Article_Link__c URLs to absolute URLs
// for cases written before the absolute-URL fix was deployed.

String baseUrl = URL.getOrgDomainUrl().toExternalForm();
Integer updated = 0;

List<Case> cases = [
    SELECT Id, KB_Article_Link__c
    FROM Case
    WHERE KB_Article_Link__c LIKE '/lightning%'
    LIMIT 200
];

for (Case c : cases) {
    c.KB_Article_Link__c = baseUrl + c.KB_Article_Link__c;
    updated++;
}
if (!cases.isEmpty()) {
    update cases;
}

System.debug('Fixed ' + updated + ' cases with absolute URL. Base URL: ' + baseUrl);
System.debug('=== FIX COMPLETE ===');
