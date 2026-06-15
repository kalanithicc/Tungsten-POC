// Quick check: verify cleanedQuestion is populated in getClarification() result
System.debug('=== CURSOR TEST: cleanedQuestion check ===');

// Clear field so it falls through to the AI_Response path
update new Case(Id = '500dN00000PIuJuQAL', Intent_Analysis__c = null);

String result = CaseResolutionController.getClarification('500dN00000PIuJuQAL');
if (result == null) {
    System.debug('[ASSERT] getClarification returned null — FAIL');
} else {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
    String cq = (String) parsed.get('cleanedQuestion');
    System.debug('[ASSERT] cleanedQuestion = ' + (String.isNotBlank(cq) ? 'PASS — "' + cq + '"' : 'FAIL — empty or null'));
    List<Object> clarifications = (List<Object>) parsed.get('clarifications');
    System.debug('[ASSERT] clarifications count = ' + clarifications.size() + (clarifications.size() > 0 ? ' — PASS' : ' — FAIL (expected > 0)'));
}
System.debug('=== DONE ===');
