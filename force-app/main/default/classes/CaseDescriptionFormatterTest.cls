@IsTest
private class CaseDescriptionFormatterTest {

    @IsTest
    static void format_includesQuestionAndResolution() {
        String result = CaseDescriptionFormatter.format(
            'How do I configure retention in PowerPDF?',
            'Open Settings and enable retention policy.'
        );
        System.assert(result.startsWith(CaseDescriptionFormatter.QUESTION_LABEL));
        System.assert(result.contains(CaseDescriptionFormatter.RESOLUTION_LABEL));
        System.assert(result.contains('How do I configure retention in PowerPDF?'));
        System.assert(result.contains('Open Settings and enable retention policy.'));
    }

    @IsTest
    static void resolveQuestionText_prefersGptfyQuestion() {
        Case c = new Case(
            Subject = 'Short subject',
            GPTfy_Question__c = 'Full agent message with MCQ context'
        );
        System.assertEquals(
            'Full agent message with MCQ context',
            CaseDescriptionFormatter.resolveQuestionText(c)
        );
    }

    @IsTest
    static void resolveQuestionText_fallsBackToSubject() {
        Case c = new Case(Subject = 'Subject only');
        System.assertEquals('Subject only', CaseDescriptionFormatter.resolveQuestionText(c));
    }
}
