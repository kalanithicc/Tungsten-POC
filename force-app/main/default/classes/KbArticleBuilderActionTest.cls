/**
 * Unit tests for KbArticleBuilderAction.
 *
 * Tests the parser and article create/update logic via the ccai.AIPromptActionInterface
 * entry point (invokeApex). No callouts needed — the class only receives a
 * ccai__AI_Response__c record and performs DML.
 */
@IsTest
private class KbArticleBuilderActionTest {

    private static final String CREATE_RESPONSE =
        'Action: CREATE\n' +
        'ArticleId:\n' +
        'Question: "How do I reset my E-Invoicing password?"\n' +
        'Answer: "Navigate to the login page and click Forgot Password to reset your password."';

    private static final String UPDATE_RESPONSE_PREFIX =
        'Action: UPDATE\n' +
        'ArticleId: %ARTICLE_ID%\n' +
        'Question: "How do I reset my E-Invoicing password?"\n' +
        'Answer: "Navigate to the login page and click Forgot Password. If that fails, contact your administrator."';

    // ─── Parser tests ──────────────────────────────────────────────────────────

    @IsTest
    static void parseResponse_extractsCreateAction() {
        KbArticleBuilderAction.PromptResult result =
            KbArticleBuilderAction.parseResponse(CREATE_RESPONSE);

        System.assertNotEquals(null, result);
        System.assertEquals('CREATE', result.action);
        System.assertEquals(null, result.articleId);
        System.assertEquals('How do I reset my E-Invoicing password?', result.question);
        System.assert(result.answer.contains('Forgot Password'));
    }

    @IsTest
    static void parseResponse_extractsUpdateAction() {
        String response = UPDATE_RESPONSE_PREFIX.replace('%ARTICLE_ID%', 'ka0TEST000000001AAA');

        KbArticleBuilderAction.PromptResult result =
            KbArticleBuilderAction.parseResponse(response);

        System.assertNotEquals(null, result);
        System.assertEquals('UPDATE', result.action);
        System.assertEquals('ka0TEST000000001AAA', result.articleId);
    }

    @IsTest
    static void parseResponse_defaultsToCreateWhenActionMissing() {
        String legacyResponse =
            'Question: "What is TotalAgility?"\n' +
            'Answer: "TotalAgility is a business process automation platform."';

        KbArticleBuilderAction.PromptResult result =
            KbArticleBuilderAction.parseResponse(legacyResponse);

        System.assertNotEquals(null, result);
        System.assertEquals('CREATE', result.action);
        System.assertEquals('What is TotalAgility?', result.question);
    }

    @IsTest
    static void parseResponse_returnsNullForBlankInput() {
        System.assertEquals(null, KbArticleBuilderAction.parseResponse(''));
    }

    @IsTest
    static void parseResponse_returnsNullForUnrecognisedFormat() {
        System.assertEquals(null,
            KbArticleBuilderAction.parseResponse('This is just some free text with no structure.'));
    }

    // ─── invokeApex tests ──────────────────────────────────────────────────────

    @IsTest
    static void invokeApex_createsArticle_onCreateAction() {
        Case c = new Case(
            Origin  = 'Phone',
            Status  = 'New',
            Subject = 'KB article builder test — CREATE path'
        );
        insert c;

        ccai__AI_Response__c response = new ccai__AI_Response__c(
            ccai__AI_Processed_Data_PII_Added__c = CREATE_RESPONSE,
            ccai__Record_Id__c                   = String.valueOf(c.Id)
        );

        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(response);
        Test.stopTest();

        List<CaseArticle> links = [
            SELECT KnowledgeArticleId
            FROM CaseArticle
            WHERE CaseId = :c.Id
        ];
        System.assertEquals(1, links.size(), 'One CaseArticle link must be created');
    }

    @IsTest
    static void invokeApex_updatesDraftArticle_onUpdateAction() {
        Knowledge__kav existing = new Knowledge__kav(
            Title         = 'How do I reset my E-Invoicing password?',
            UrlName       = 'e-invoicing-password-reset-' + Datetime.now().getTime(),
            Language      = 'en_US',
            Resolution__c = 'Old answer: click Forgot Password.'
        );
        insert existing;

        Case c = new Case(
            Origin  = 'Phone',
            Status  = 'New',
            Subject = 'KB article builder test — UPDATE path'
        );
        insert c;

        String updateResponse = UPDATE_RESPONSE_PREFIX.replace(
            '%ARTICLE_ID%', String.valueOf(existing.Id));

        ccai__AI_Response__c response = new ccai__AI_Response__c(
            ccai__AI_Processed_Data_PII_Added__c = updateResponse,
            ccai__Record_Id__c                   = String.valueOf(c.Id)
        );

        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(response);
        Test.stopTest();

        Knowledge__kav updated = [
            SELECT Resolution__c
            FROM Knowledge__kav
            WHERE Id = :existing.Id
        ];
        System.assert(updated.Resolution__c.contains('contact your administrator'),
            'Draft article Resolution__c should be updated with merged answer');

        Integer articleCount = [
            SELECT COUNT()
            FROM Knowledge__kav
            WHERE Title = 'How do I reset my E-Invoicing password?'
        ];
        System.assertEquals(1, articleCount,
            'UPDATE path must not create a duplicate article');
    }

    @IsTest
    static void invokeApex_fallsBackToCreateWhenUpdateTargetMissing() {
        Case c = new Case(
            Origin  = 'Phone',
            Status  = 'New',
            Subject = 'KB builder test — UPDATE fallback'
        );
        insert c;

        String badUpdateResponse =
            'Action: UPDATE\n' +
            'ArticleId: ka0INVALID00000001AAA\n' +
            'Question: "Missing article test"\n' +
            'Answer: "Fallback create answer text."';

        ccai__AI_Response__c response = new ccai__AI_Response__c(
            ccai__AI_Processed_Data_PII_Added__c = badUpdateResponse,
            ccai__Record_Id__c                   = String.valueOf(c.Id)
        );

        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(response);
        Test.stopTest();

        List<CaseArticle> links = [
            SELECT KnowledgeArticleId
            FROM CaseArticle
            WHERE CaseId = :c.Id
        ];
        System.assertEquals(1, links.size(),
            'Should fall back to CREATE and still link one article');
    }

    @IsTest
    static void invokeApex_skipsOnGPTfyErrorJson() {
        Case c = new Case(
            Origin  = 'Phone',
            Status  = 'New',
            Subject = 'KB builder test — GPTfy error JSON'
        );
        insert c;

        String errorJson =
            '{"error" : {"message" : "An error occured, please contact your System Admin."}}';

        ccai__AI_Response__c response = new ccai__AI_Response__c(
            ccai__AI_Processed_Data_PII_Added__c = errorJson,
            ccai__Record_Id__c                   = String.valueOf(c.Id)
        );

        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(response);
        Test.stopTest();

        Integer articleCount = [
            SELECT COUNT() FROM CaseArticle WHERE CaseId = :c.Id
        ];
        System.assertEquals(0, articleCount,
            'No articles should be created when GPTfy returns an error JSON envelope');
    }

    @IsTest
    static void invokeApex_skipsOnBlankResponse() {
        Case c = new Case(
            Origin  = 'Phone',
            Status  = 'New',
            Subject = 'Blank response test'
        );
        insert c;

        ccai__AI_Response__c response = new ccai__AI_Response__c(
            ccai__Message__c   = '',
            ccai__Record_Id__c = String.valueOf(c.Id)
        );

        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(response);
        Test.stopTest();

        Integer articleCount = [
            SELECT COUNT() FROM CaseArticle WHERE CaseId = :c.Id
        ];
        System.assertEquals(0, articleCount,
            'No articles should be created when the response is blank');
    }

    @IsTest
    static void invokeApex_handlesNullResponse() {
        KbArticleBuilderAction action = new KbArticleBuilderAction();

        Test.startTest();
        action.invokeApex(null);
        Test.stopTest();

        System.assert(true, 'invokeApex(null) must not throw');
    }

    @IsTest
    static void buildUrlSlug_isUrlSafe() {
        String slug = KbArticleBuilderAction.buildUrlSlug(
            'How do I reset my E-Invoicing password?', 0);
        System.assert(
            slug.startsWith('how-do-i-reset-my-e-invoicing-password-0-'),
            'Slug must be lowercase, hyphenated, and include the index: ' + slug);
        System.assert(
            !slug.contains(' ') && !slug.contains('?'),
            'Slug must not contain spaces or special characters: ' + slug);
    }
}
