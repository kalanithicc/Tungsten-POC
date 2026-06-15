/**
 * Unit tests for CaseResolveActionController.
 *
 * KB creation is now fully asynchronous (KbCreationService Queueable +
 * KbArticleBuilderAction Prompt Action). These tests only verify:
 *   - Case is closed with the correct resolution text (all paths)
 *   - SaveResult.articleQueued = true when createKb = true
 *   - SaveResult.articleQueued is null when createKb = false
 *   - Guard clauses throw AuraHandledException as expected
 */
@IsTest
private class CaseResolveActionControllerTest {

    @IsTest
    static void saveResolution_closesCaseAndCopiesText() {
        Case c = new Case(
            Origin                        = 'Web',
            Status                        = 'New',
            Subject                       = 'Test case to resolve',
            AI_Clarification_Pending__c   = true
        );
        insert c;

        String solution = 'Restart the service and clear the cache.';

        Test.startTest();
        CaseResolveActionController.saveResolution(c.Id, solution, false);
        Test.stopTest();

        Case after = [
            SELECT Status, Resolution__c, Description
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertEquals('Closed', after.Status,
            'saveResolution must flip Status to Closed');
        System.assertEquals(solution, after.Resolution__c,
            'saveResolution must copy the supplied text into Resolution__c verbatim');
        System.assertEquals(
            CaseDescriptionFormatter.formatOnClose(c, solution),
            after.Description,
            'Description must show Question and Resolution Provided labels on close'
        );
    }

    @IsTest
    static void saveResolution_overwritesExistingResolution() {
        Case c = new Case(
            Origin        = 'Web',
            Status        = 'Working',
            Subject       = 'Has prior resolution',
            Resolution__c = 'Old text'
        );
        insert c;

        Test.startTest();
        CaseResolveActionController.saveResolution(c.Id, 'New text', false);
        Test.stopTest();

        Case after = [SELECT Status, Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', after.Status);
        System.assertEquals('New text', after.Resolution__c,
            'Agent-supplied resolution must overwrite any prior value');
    }

    @IsTest
    static void saveResolution_throwsForNullCaseId() {
        Boolean threw = false;
        try {
            Test.startTest();
            CaseResolveActionController.saveResolution(null, 'Some text', false);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'saveResolution(null, ...) must throw AuraHandledException');
    }

    @IsTest
    static void saveResolution_throwsForBlankResolution() {
        Case c = new Case(Origin = 'Web', Status = 'New', Subject = 'Test');
        insert c;

        Boolean threwForNull = false;
        try {
            CaseResolveActionController.saveResolution(c.Id, null, false);
        } catch (AuraHandledException e) {
            threwForNull = true;
        }
        System.assert(threwForNull, 'Null resolution must throw');

        Boolean threwForEmpty = false;
        try {
            CaseResolveActionController.saveResolution(c.Id, '   ', false);
        } catch (AuraHandledException e) {
            threwForEmpty = true;
        }
        System.assert(threwForEmpty, 'Whitespace-only resolution must throw');
    }

    @IsTest
    static void saveResolution_wrapsDmlFailure() {
        Case c = new Case(Origin = 'Web', Status = 'New', Subject = 'To be deleted');
        insert c;
        Id deletedId = c.Id;
        delete c;
        Database.emptyRecycleBin(new List<Id>{ deletedId });

        Boolean threw = false;
        try {
            Test.startTest();
            CaseResolveActionController.saveResolution(deletedId, 'solution', false);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw,
            'Updating a hard-deleted Case must surface as AuraHandledException');
    }

    @IsTest
    static void saveResolution_queuesKbJobWhenCreateKbTrue() {
        Case c = new Case(
            Origin  = 'Web',
            Status  = 'New',
            Subject = 'Printer keeps jamming on tray 2'
        );
        insert c;

        Test.startTest();
        CaseResolveActionController.SaveResult result =
            CaseResolveActionController.saveResolution(
                c.Id, 'Open tray 2, remove residue, reseat cartridge.', true);
        Test.stopTest();

        System.assertEquals(true, result.caseClosed,
            'caseClosed flag must be set');
        System.assertEquals(true, result.articleQueued,
            'articleQueued must be true when createKb = true');
        System.assertEquals(null, result.articleWarning,
            'No warning should appear on the happy path');

        Case after = [SELECT Status, Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', after.Status,
            'Case must be closed regardless of async KB job');
    }

    @IsTest
    static void saveResolution_skipsKbWhenCreateKbFalse() {
        Case c = new Case(
            Origin  = 'Web',
            Status  = 'New',
            Subject = 'Skip KB test'
        );
        insert c;

        Test.startTest();
        CaseResolveActionController.SaveResult result =
            CaseResolveActionController.saveResolution(c.Id, 'Resolution only, no KB.', false);
        Test.stopTest();

        System.assertEquals(true, result.caseClosed,
            'Case must still be closed');
        System.assertEquals(null, result.articleQueued,
            'articleQueued must be null when createKb is false');
        System.assertEquals(null, result.articleWarning,
            'No warning should appear when createKb is false');
    }
}
