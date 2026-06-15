ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName = 'Question_Clarifier_Agent';
req.userMessage = 'Path B continue probe';
req.userContextId = 'A-00706';
ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);
System.debug('status=' + (resp == null ? 'null' : resp.status));
List<ccai__AI_Response__c> rows = [
    SELECT Name, ccai__User_Context_Id__c, ccai__Parent_AI_Response__c,
           ccai__AI_Parent_Response__c, ccai__Thread_Id__c, ccai__Record_Id__c
    FROM ccai__AI_Response__c
    WHERE CreatedDate = TODAY
      AND ccai__Agent_Name__c = 'Question Clarifier Agent'
    ORDER BY CreatedDate DESC
    LIMIT 3
];
for (ccai__AI_Response__c r : rows) {
    System.debug(r.Name + ' ctx=' + r.ccai__User_Context_Id__c
        + ' parent=' + r.ccai__Parent_AI_Response__c
        + ' aiParent=' + r.ccai__AI_Parent_Response__c
        + ' thread=' + r.ccai__Thread_Id__c
        + ' record=' + r.ccai__Record_Id__c);
}
