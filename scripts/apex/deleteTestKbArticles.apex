// Delete all KB articles created today via KbManagement.PublishingService
List<Knowledge__kav> kavs = [
    SELECT Id, Title, KnowledgeArticleId, PublishStatus
    FROM Knowledge__kav
    WHERE CreatedDate = TODAY
      AND PublishStatus IN ('Draft', 'Online')
];
System.debug('Found ' + kavs.size() + ' articles to delete:');

Integer deleted = 0;
Integer errors  = 0;
for (Knowledge__kav k : kavs) {
    try {
        KbManagement.PublishingService.deleteKnowledgeArticle(String.valueOf(k.KnowledgeArticleId));
        System.debug('  Deleted: ' + k.Title);
        deleted++;
    } catch (Exception e) {
        System.debug('  ERROR on "' + k.Title + '": ' + e.getMessage());
        errors++;
    }
}

Integer remaining = [SELECT COUNT() FROM Knowledge__kav WHERE PublishStatus IN ('Draft','Online')];
System.debug('Done. Deleted: ' + deleted + '  Errors: ' + errors + '  Remaining: ' + remaining);
