/**
 * Layer 3 diagnostic — invokeAgent from Site Guest User context.
 * Marker: cursor-test-layer3-guest-invoke
 */
String marker = 'cursor-test-layer3-guest-invoke';

User guest = [
    SELECT Id, Name, UserType
    FROM User
    WHERE UserType = 'Guest' AND IsActive = true
    LIMIT 1
];
System.debug('=== LAYER 3 GUEST INVOKE DIAGNOSTIC ===');
System.debug('Guest user: ' + guest.Name + ' (' + guest.Id + ')');

System.runAs(guest) {
    ccai.AIAgenticWebService.RequestWrapper req =
        new ccai.AIAgenticWebService.RequestWrapper();
    req.agentName   = 'Question_Clarifier_Agent';
    req.userMessage = marker + ' How do I configure Power PDF Advanced retention policy?';

    try {
        ccai.AIAgenticWebService.ResponseWrapper resp =
            ccai.AIAgenticUtility.invokeAgent(req);

        if (resp == null) {
            System.debug('[GUEST invokeAgent] RESULT: null response (same as writeFallback path)');
        } else {
            System.debug('[GUEST invokeAgent] status: ' + resp.status);
            System.debug('[GUEST invokeAgent] body length: ' +
                (resp.responseBody == null ? 'NULL' : String.valueOf(resp.responseBody.length())));
            System.debug('[GUEST invokeAgent] body preview: ' +
                (resp.responseBody == null ? 'NULL' : resp.responseBody.abbreviate(200)));
        }
    } catch (Exception e) {
        System.debug('[GUEST invokeAgent] EXCEPTION: ' + e.getTypeName() + ': ' + e.getMessage());
    }
}

// Control: same call as admin (current user)
ccai.AIAgenticWebService.RequestWrapper adminReq =
    new ccai.AIAgenticWebService.RequestWrapper();
adminReq.agentName   = 'Question_Clarifier_Agent';
adminReq.userMessage = marker + ' admin control call';

ccai.AIAgenticWebService.ResponseWrapper adminResp =
    ccai.AIAgenticUtility.invokeAgent(adminReq);
System.debug('[ADMIN invokeAgent] null? ' + (adminResp == null));
if (adminResp != null) {
    System.debug('[ADMIN invokeAgent] status: ' + adminResp.status);
    System.debug('[ADMIN invokeAgent] body length: ' +
        (adminResp.responseBody == null ? 'NULL' : String.valueOf(adminResp.responseBody.length())));
}

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
