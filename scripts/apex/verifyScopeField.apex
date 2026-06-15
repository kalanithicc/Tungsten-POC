// Directly write a scope value to KB_Candidates__c to verify the field works for KB Update Scope
Case c = [SELECT Id, KB_Candidates__c FROM Case WHERE Id = '500dN00000PLh1xQAD' LIMIT 1];
c.KB_Candidates__c =
    'REASON_MISSED: The case subject contained the exact article title; RAG may have treated it as ' +
    'an exact duplicate rather than returning a canonical match.\n' +
    'UPDATE_NEEDED: YES\n' +
    'SCOPE: Add a dedicated section on disruption behavior during peak concurrent activation windows ' +
    'and steps to verify connectivity to the license activation server from behind a corporate proxy.';
update c;

Case v = [SELECT KB_Candidates__c FROM Case WHERE Id = '500dN00000PLh1xQAD' LIMIT 1];
System.debug('KB Update Scope written: ' + (String.isNotBlank(v.KB_Candidates__c) ? 'YES ✓' : 'NO — write failed'));
System.debug('Content: ' + v.KB_Candidates__c);
