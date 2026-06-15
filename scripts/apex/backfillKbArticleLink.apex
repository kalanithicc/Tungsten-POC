// Backfills KB_Article_Link__c for all Cases that have a CaseArticle link
// but are missing the URL field (cases resolved before the field was deployed).

Integer updated = 0;
Integer skipped = 0;

List<Case> cases = [
    SELECT Id, CaseNumber, KB_Article_Link__c
    FROM Case
    WHERE Id IN (SELECT CaseId FROM CaseArticle)
      AND KB_Article_Link__c = null
    LIMIT 200
];

for (Case c : cases) {
    List<CaseArticle> cas = [
        SELECT KnowledgeArticleId
        FROM CaseArticle
        WHERE CaseId = :c.Id
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (cas.isEmpty()) { skipped++; continue; }

    List<Knowledge__kav> kavs = [
        SELECT Id
        FROM Knowledge__kav
        WHERE KnowledgeArticleId = :cas[0].KnowledgeArticleId
          AND PublishStatus IN ('Draft', 'Online')
        ORDER BY LastModifiedDate DESC
        LIMIT 1
    ];
    if (kavs.isEmpty()) { skipped++; continue; }

    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    c.KB_Article_Link__c = baseUrl + '/lightning/r/Knowledge__kav/' + kavs[0].Id + '/view';
    updated++;
}

update cases;

System.debug('Backfill complete — updated: ' + updated + ', skipped: ' + skipped);
System.debug('=== BACKFILL COMPLETE ===');
