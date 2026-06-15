String ctx = 'cursor-probe-cross-' + Datetime.now().format('yyyyMMddHHmmss');

ccai.AIAgenticWebService.RequestWrapper req1 = new ccai.AIAgenticWebService.RequestWrapper();
req1.agentName     = 'Question_Clarifier_Agent';
req1.userMessage   = 'Product: TotalAgility\nQuestion: Cross agent probe step 1';
req1.userContextId = ctx;
ccai.AIAgenticUtility.invokeAgent(req1);

ccai.AIAgenticWebService.RequestWrapper req2 = new ccai.AIAgenticWebService.RequestWrapper();
req2.agentName     = 'Case_Resolve_Agent';
req2.userMessage   = 'How do I clear browser cache when login page is blank?';
req2.userContextId = ctx;
ccai.AIAgenticUtility.invokeAgent(req2);

Integer count = [
    SELECT COUNT()
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = :ctx
];
System.debug('Context: ' + ctx);
System.debug('Parent audit count after clarifier + resolver: ' + count);

for (ccai__AI_Response__c a : [
    SELECT Name, ccai__Agent_Name__c, CreatedDate, LastModifiedDate
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = :ctx
    ORDER BY CreatedDate ASC
]) {
    System.debug('  ' + a.Name + ' | ' + a.ccai__Agent_Name__c);
}
