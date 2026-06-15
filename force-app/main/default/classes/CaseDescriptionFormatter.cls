/**
 * Formats Case.Description for back-office and customer case views (Checkpoint 3).
 *
 *   Question: {text sent to the resolver agent}
 *   Resolution Provided: {AI answer or human agent resolution}
 */
public with sharing class CaseDescriptionFormatter {

    public static final String QUESTION_LABEL     = 'Question:';
    public static final String RESOLUTION_LABEL   = 'Resolution Provided:';

    public static String format(String question, String resolution) {
        String q = String.isBlank(question) ? '' : question.trim();
        String r = String.isBlank(resolution) ? '' : resolution.trim();

        if (String.isBlank(q) && String.isBlank(r)) {
            return '';
        }
        if (String.isBlank(q)) {
            return RESOLUTION_LABEL + '\n' + r;
        }
        if (String.isBlank(r)) {
            return QUESTION_LABEL + '\n' + q;
        }
        return QUESTION_LABEL + '\n' + q + '\n\n' + RESOLUTION_LABEL + '\n' + r;
    }

    /**
     * Prefer GPTfy_Question__c (full agent message incl. MCQ context), else Subject.
     */
    public static String resolveQuestionText(Case c) {
        if (c == null) {
            return '';
        }
        if (String.isNotBlank(c.GPTfy_Question__c)) {
            return c.GPTfy_Question__c.trim();
        }
        return c.Subject == null ? '' : c.Subject.trim();
    }

    /**
     * Plain-text resolution for Case.Description at close time.
     * Prefers Summary__c (AI HTML answer), else Description with the same
     * low-quality sanitization used when copying to Resolution__c.
     */
    public static String resolvePlainResolution(Case c) {
        if (c == null) {
            return '';
        }
        if (String.isNotBlank(c.Summary__c)) {
            return CaseAgentResolutionService.htmlToPlainText(c.Summary__c);
        }
        String descriptionPlain = c.Description == null ? '' : c.Description.trim();
        if (String.isBlank(descriptionPlain)) {
            return '';
        }
        String sanitized = CaseResolutionController.sanitizeRecommendation(descriptionPlain);
        if (String.isBlank(sanitized)) {
            return descriptionPlain;
        }
        return CaseAgentResolutionService.htmlToPlainText(sanitized);
    }

    /**
     * Builds the closed-case Description shown on the Case record and in emails.
     */
    public static String formatOnClose(Case c) {
        return format(resolveQuestionText(c), resolvePlainResolution(c));
    }

    /**
     * Same as formatOnClose but when the resolution plain text is already known
     * (e.g. human agent typed it on the Resolve quick action).
     */
    public static String formatOnClose(Case c, String resolutionPlainText) {
        return format(resolveQuestionText(c), resolutionPlainText);
    }
}
