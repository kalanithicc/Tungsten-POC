/**
 * Probe: two invokeAgent calls with same userContextId — one or two parent audits?
 */
String ctx = 'cursor-probe-merge-' + Datetime.now().format('yyyyMMddHHmmss');

ccai.AIAgenticWebService.RequestWrapper req1 =
    new ccai.AIAgenticWebService.RequestWrapper();
req1.agentName     = 'Question_Clarifier_Agent';
req1.userMessage   = 'Product: TotalAgility\nQuestion: Probe merge call 1';
req1.userContextId = ctx;
ccai.AIAgenticUtility.invokeAgent(req1);

ccai.AIAgenticWebService.RequestWrapper req2 =
    new ccai.AIAgenticWebService.RequestWrapper();
req2.agentName     = 'Question_Clarifier_Agent';
req2.userMessage   = 'Product: TotalAgility\nQuestion: Probe merge call 2 follow up';
req2.userContextId = ctx;
ccai.AIAgenticUtility.invokeAgent(req2);

Integer count = [
    SELECT COUNT()
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = :ctx
];
System.debug('Context: ' + ctx);
System.debug('Parent audit count after 2 SAME-agent calls: ' + count);

for (ccai__AI_Response__c a : [
    SELECT Name, ccai__Agent_Name__c, CreatedDate, LastModifiedDate
    FROM ccai__AI_Response__c
    WHERE ccai__User_Context_Id__c = :ctx
    ORDER BY CreatedDate ASC
]) {
    System.debug('  ' + a.Name + ' created=' + a.CreatedDate + ' modified=' + a.LastModifiedDate);
}
