/**
 * Unit tests for CaseResolutionController.
 *
 * Covers the three @AuraEnabled methods plus a few edge cases so that
 * code coverage comfortably exceeds the 75% Salesforce minimum.
 * Tests run as a system user, so guest-profile permissions are NOT
 * exercised here. Phase 9's smoke test in incognito covers that path.
 */
@IsTest
private class CaseResolutionControllerTest {

    @IsTest
    static void createSupportCase_insertsCaseAndReturnsIdAndNumber() {
        Test.startTest();
        Map<String, String> result = CaseResolutionController.createSupportCase(
            'Jane', 'Doe', 'jane@example.com', 'Cannot login to my account', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result map should not be null');
        System.assertNotEquals(null, result.get('caseId'), 'caseId should be returned');
        System.assertNotEquals(null, result.get('caseNumber'), 'caseNumber should be returned');

        Case inserted = [
            SELECT Id, Subject, Status, Origin, Priority, SuppliedName, SuppliedEmail, Product__c
            FROM Case
            WHERE Id = :result.get('caseId')
        ];
        System.assertEquals('Web', inserted.Origin, 'Origin must be Web for the Flow trigger to fire');
        System.assertEquals('New', inserted.Status);
        System.assertEquals('Medium', inserted.Priority);
        System.assertEquals('Cannot login to my account', inserted.Subject);
        System.assertEquals('Jane Doe', inserted.SuppliedName);
        System.assertEquals('jane@example.com', inserted.SuppliedEmail);
        System.assertEquals(null, inserted.Product__c, 'Product__c should be null when not supplied');
    }

    @IsTest
    static void createSupportCase_persistsProductWhenSupplied() {
        // Pick the first active picklist value at runtime so the test stays in
        // sync with whatever real values are configured on the org.
        List<Map<String, String>> options = CaseResolutionController.getProductOptions();
        System.assert(!options.isEmpty(), 'Product__c must have at least one active picklist value');
        String chosen = options[0].get('value');

        Test.startTest();
        Map<String, String> result = CaseResolutionController.createSupportCase(
            'Pat', 'Smith', 'pat@example.com', 'Need help with the product', chosen
        );
        Test.stopTest();

        Case inserted = [SELECT Product__c FROM Case WHERE Id = :result.get('caseId')];
        System.assertEquals(chosen, inserted.Product__c,
            'Product__c should be populated when supplied');
    }

    @IsTest
    static void createSupportCase_truncatesLongSubject() {
        String longSubject = 'a'.repeat(300);

        Test.startTest();
        Map<String, String> result = CaseResolutionController.createSupportCase(
            'Long', 'Subject', 'l@example.com', longSubject, null
        );
        Test.stopTest();

        Case inserted = [SELECT Subject FROM Case WHERE Id = :result.get('caseId')];
        System.assertEquals(255, inserted.Subject.length(), 'Subject must be truncated to 255 chars');
    }

    @IsTest
    static void createSupportCase_handlesNullInputsGracefully() {
        Test.startTest();
        Map<String, String> result = CaseResolutionController.createSupportCase(
            null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result.get('caseId'), 'Case should still be created with null inputs');
    }

    @IsTest
    static void getRecommendation_returnsNullWhenDescriptionBlank() {
        Case c = new Case(Origin = 'Web', Status = 'New', Subject = 'Test');
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when Description is blank');
    }

    @IsTest
    static void getRecommendation_replacesLowQualityRagResponse() {
        Case c = new Case(
            Origin      = 'Web',
            Status      = 'New',
            Subject     = 'Test',
            Description = 'What was that?'
        );
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assertEquals(
            CaseResolutionController.NO_ANSWER_MESSAGE,
            result,
            'Unprofessional RAG text should be replaced with the polite no-answer message'
        );
    }

    @IsTest
    static void sanitizeRecommendation_returnsNullForBlank() {
        System.assertEquals(null, CaseResolutionController.sanitizeRecommendation(null));
        System.assertEquals(null, CaseResolutionController.sanitizeRecommendation('   '));
    }

    @IsTest
    static void getRecommendation_replacesConversationalRagFailure() {
        Case c = new Case(
            Origin      = 'Web',
            Status      = 'New',
            Subject     = 'Test',
            Description = 'I didn\'t get that. Can you repeat?'
        );
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assertEquals(CaseResolutionController.NO_ANSWER_MESSAGE, result);
    }

    @IsTest
    static void getRecommendation_replacesSayThatOneMoreTimeRagFailure() {
        Case c = new Case(
            Origin      = 'Web',
            Status      = 'New',
            Subject     = 'Test',
            Description = 'Say that one more time?'
        );
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assertEquals(CaseResolutionController.NO_ANSWER_MESSAGE, result);
    }

    @IsTest
    static void getRecommendation_replacesSayThatAgainRagFailure() {
        Case c = new Case(
            Origin      = 'Web',
            Status      = 'New',
            Subject     = 'Test',
            Description = 'Sorry, can you say that again?'
        );
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assertEquals(CaseResolutionController.NO_ANSWER_MESSAGE, result);
    }

    @IsTest
    static void sanitizeRecommendation_wrapsValidAnswerInParagraphTag() {
        String answer = 'Restart the service, then clear the cache folder.';
        String result = CaseResolutionController.sanitizeRecommendation(answer);
        System.assert(result.contains('Restart the service'),
            'Valid KB answer text must be preserved');
        System.assert(result.startsWith('<p>') && result.endsWith('</p>'),
            'Plain-text answers should be wrapped in <p> tags for rich-text rendering');
    }

    @IsTest
    static void getRecommendation_returnsHtmlWhenDescriptionPopulated() {
        Case c = new Case(
            Origin      = 'Web',
            Status      = 'New',
            Subject     = 'Test',
            Description = 'Here is the AI-generated answer.'
        );
        insert c;

        Test.startTest();
        String result = CaseResolutionController.getRecommendation(c.Id);
        Test.stopTest();

        System.assert(result != null, 'Should return a non-null result');
        System.assert(result.contains('Here is the AI-generated answer.'),
            'Answer text must be present in the returned HTML');
    }

    @IsTest
    static void plainTextToHtml_convertsDoubleNewlineToParagraphs() {
        String input = 'First section.\n\nSecond section.';
        String result = CaseResolutionController.plainTextToHtml(input);
        System.assert(result.contains('<p>First section.</p>'), 'First paragraph should be wrapped');
        System.assert(result.contains('<p>Second section.</p>'), 'Second paragraph should be wrapped');
    }

    @IsTest
    static void plainTextToHtml_convertsSingleNewlineToBreak() {
        String input = 'Line one.\nLine two.';
        String result = CaseResolutionController.plainTextToHtml(input);
        System.assert(result.contains('<br/>'), 'Single newline should become <br/>');
        System.assert(result.contains('Line one.') && result.contains('Line two.'),
            'Both lines must be present');
    }

    @IsTest
    static void plainTextToHtml_passesHtmlThroughUnchanged() {
        String html = '<p>Already formatted.</p>';
        String result = CaseResolutionController.plainTextToHtml(html);
        System.assertEquals(html, result, 'Existing HTML must not be double-processed');
    }

    @IsTest
    static void plainTextToHtml_handlesBlankInput() {
        System.assertEquals(null, CaseResolutionController.plainTextToHtml(null));
        System.assertEquals('   ', CaseResolutionController.plainTextToHtml('   '));
    }

    @IsTest
    static void plainTextToHtml_splitsInlineSectionHeaders() {
        // Simulates the agent returning everything as one paragraph with no newlines,
        // e.g. "Intro text. Token Generation: Do this. Token Permissions: Do that."
        String input = 'Please review the following steps. Token Generation: Ensure the token is correct. Token Permissions: The token must have correct permissions.';
        String result = CaseResolutionController.plainTextToHtml(input);
        // Each section should end up in its own <p> block
        System.assert(result.contains('<p>'), 'Result should contain paragraph tags');
        Integer paraCount = result.countMatches('<p>');
        System.assert(paraCount >= 2,
            'Inline section headers should produce at least 2 paragraphs, got: ' + paraCount + ' | ' + result);
    }

    @IsTest
    static void getRecommendation_returnsNullForNullId() {
        Test.startTest();
        String result = CaseResolutionController.getRecommendation(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null Id should return null, not throw');
    }

    @IsTest
    static void resolveCase_closesCaseAndCopiesDescription() {
        String agentQ = 'Product: Test\nQuestion: How do I verify close formatting?';
        Case c = new Case(
            Origin                        = 'Web',
            Status                        = 'New',
            Subject                       = 'How do I verify close formatting?',
            GPTfy_Question__c             = agentQ,
            Summary__c                    = '<p>AI answer text</p>',
            Description                   = 'AI answer text',
            AI_Clarification_Pending__c   = true
        );
        insert c;

        Test.startTest();
        CaseResolutionController.resolveCase(c.Id);
        Test.stopTest();

        Case closed = [
            SELECT Status, Resolution__c, Description, GPTfy_Question__c
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertEquals('Closed', closed.Status,
            'CaseResolvedTrigger should close the Case via system context');
        System.assertEquals('<p>AI answer text</p>', closed.Resolution__c,
            'Resolution__c should keep the HTML answer from Summary__c');
        System.assert(
            closed.Description.contains(CaseDescriptionFormatter.QUESTION_LABEL),
            'Closed Description should include Question label'
        );
        System.assert(
            closed.Description.contains(CaseDescriptionFormatter.RESOLUTION_LABEL),
            'Closed Description should include Resolution Provided label'
        );
        System.assert(
            closed.Description.contains(agentQ),
            'Closed Description should include the resolver question'
        );
        System.assert(
            closed.Description.contains('AI answer text'),
            'Closed Description should include the plain resolution text'
        );
    }

    @IsTest
    static void resolveCase_sanitizesLowQualityDescriptionOnClose() {
        Case c = new Case(
            Origin                        = 'Web',
            Status                        = 'New',
            Subject                       = 'Test',
            Description                   = 'What was that?',
            AI_Clarification_Pending__c   = true
        );
        insert c;

        Test.startTest();
        CaseResolutionController.resolveCase(c.Id);
        Test.stopTest();

        Case closed = [SELECT Status, Resolution__c, Description FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', closed.Status);
        System.assertEquals(
            CaseResolutionController.NO_ANSWER_MESSAGE,
            closed.Resolution__c,
            'Low-quality Description should not be stored on Resolution__c'
        );
        System.assert(
            closed.Description.contains(CaseDescriptionFormatter.RESOLUTION_LABEL),
            'Closed Description should still use the formatted layout'
        );
    }

    @IsTest
    static void resolveCase_leavesAlreadyClosedCaseUntouched() {
        Case c = new Case(
            Origin        = 'Web',
            Status        = 'Closed',
            Subject       = 'Test',
            Description   = 'AI answer text',
            Resolution__c = 'Pre-existing resolution'
        );
        insert c;

        Test.startTest();
        CaseResolutionController.resolveCase(c.Id);
        Test.stopTest();

        Case after = [SELECT Status, Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', after.Status, 'Status should remain Closed');
        System.assertEquals('Pre-existing resolution', after.Resolution__c,
            'Already-closed cases must not have Resolution__c overwritten');
    }

    @IsTest
    static void resolveCase_throwsForNullId() {
        Boolean threw = false;
        try {
            Test.startTest();
            CaseResolutionController.resolveCase(null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'resolveCase(null) should throw AuraHandledException');
    }

    @IsTest
    static void getProductOptions_returnsActiveValues() {
        Test.startTest();
        List<Map<String, String>> options = CaseResolutionController.getProductOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options list should not be null');
        System.assert(!options.isEmpty(),
            'Product__c should have at least one active picklist value configured');
        for (Map<String, String> entry : options) {
            System.assert(String.isNotBlank(entry.get('label')),
                'Each option must have a non-blank label');
            System.assert(String.isNotBlank(entry.get('value')),
                'Each option must have a non-blank value');
        }
    }

    @IsTest
    static void getPortalUserContext_returnsRunningUserFields() {
        Test.startTest();
        Map<String, String> ctx = CaseResolutionController.getPortalUserContext();
        Test.stopTest();

        System.assertNotEquals(null, ctx.get('userType'));
        System.assertEquals('false', ctx.get('isGuest'),
            'Test runs as system user, not Site Guest');
        System.assert(String.isNotBlank(ctx.get('displayName')));
        System.assertNotEquals(null, ctx.get('firstName'));
        System.assertNotEquals(null, ctx.get('lastName'));
        System.assertNotEquals(null, ctx.get('email'));
    }
}
