String piiAdded = [
    SELECT ccai__AI_Processed_Data_PII_Added__c
    FROM ccai__AI_Response__c
    WHERE Name = 'A-00661'
    LIMIT 1
].ccai__AI_Processed_Data_PII_Added__c;

String jsonResult = QuestionClarifierAction.parseClarifierResponse(piiAdded);
System.debug('[ASSERT] K7 audit A-00661 parses to MCQs: ' +
    (jsonResult != null && jsonResult.contains('"question"') ? 'PASS' : 'FAIL'));
System.debug('Preview: ' + (jsonResult == null ? 'NULL' : jsonResult.abbreviate(250)));
