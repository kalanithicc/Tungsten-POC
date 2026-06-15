// Test option parsing via buildJson — covers all three formats the agent returns
// FORMAT 1: pipe-separated
String r1 = QuestionClarifierAction.buildJson(
    'Cleaned Question: Test Q\n\nClarification 1: Scanner connection?\nOptions: A) USB | B) Network (Ethernet/Wi-Fi) | C) Not sure'
);
Map<String,Object> m1 = (Map<String,Object>) JSON.deserializeUntyped(r1);
List<Object> opts1 = (List<Object>) ((Map<String,Object>)((List<Object>)m1.get('clarifications'))[0]).get('options');
System.debug('FORMAT 1 (pipe): ' + opts1 + ' count=' + opts1.size()); // expect 3

// FORMAT 2: HTML entity pipe
String r2 = QuestionClarifierAction.buildJson(
    'Cleaned Question: Test Q\n\nClarification 1: Scanner connection?\nOptions: A) USB &#124; B) Network (Ethernet/Wi-Fi) &#124; C) Not sure'
);
Map<String,Object> m2 = (Map<String,Object>) JSON.deserializeUntyped(r2);
List<Object> opts2 = (List<Object>) ((Map<String,Object>)((List<Object>)m2.get('clarifications'))[0]).get('options');
System.debug('FORMAT 2 (&#124;): ' + opts2 + ' count=' + opts2.size()); // expect 3

// FORMAT 3: no separator — the exact broken case
String r3 = QuestionClarifierAction.buildJson(
    'Cleaned Question: Test Q\n\nClarification 1: Scanner connection?\nOptions: A) USB B) Network (Ethernet/Wi-Fi) C) Not sure\n\nClarification 2: Bitness?\nOptions: A) 32-bit B) 64-bit C) Not sure'
);
Map<String,Object> m3 = (Map<String,Object>) JSON.deserializeUntyped(r3);
List<Object> opts3 = (List<Object>) ((Map<String,Object>)((List<Object>)m3.get('clarifications'))[0]).get('options');
List<Object> opts3b = (List<Object>) ((Map<String,Object>)((List<Object>)m3.get('clarifications'))[1]).get('options');
System.debug('FORMAT 3 Q1 (no sep): ' + opts3 + ' count=' + opts3.size()); // expect 3
System.debug('FORMAT 3 Q2 (no sep): ' + opts3b + ' count=' + opts3b.size()); // expect 3
System.debug('=== ALL DONE ===');
