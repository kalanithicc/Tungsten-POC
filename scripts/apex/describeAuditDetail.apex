Schema.DescribeSObjectResult d = ccai__AI_Security_Audit_Detail__c.SObjectType.getDescribe();
System.debug('queryable=' + d.isAccessible());
for (String fn : d.fields.getMap().keySet()) {
    Schema.DescribeFieldResult f = d.fields.getMap().get(fn).getDescribe();
    String l = fn.toLowerCase();
    if (l.contains('message') || l.contains('audit') || l.contains('response') || l.contains('parent')
        || l.contains('sequence') || l.contains('role') || l.contains('user') || l.contains('agent')) {
        System.debug(fn + ' | type=' + f.getType() + ' | len=' + f.getLength() + ' | ref=' + f.getReferenceTo());
    }
}
