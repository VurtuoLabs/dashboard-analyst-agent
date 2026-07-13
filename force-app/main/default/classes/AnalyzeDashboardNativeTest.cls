@isTest
private class AnalyzeDashboardNativeTest {
    @isTest
    static void extractsIdFromUrl() {
        String url = 'https://elecom.my.salesforce.com/lightning/r/Dashboard/01ZWt000001t6sGMAQ/view';
        System.assertEquals('01ZWt000001t6sGMAQ', AnalyzeDashboardNative.extractId(url));
    }

    @isTest
    static void extractsIdFromRaw() {
        System.assertEquals('01ZWt000001t6sGMAQ', AnalyzeDashboardNative.extractId('01ZWt000001t6sGMAQ'));
    }

    @isTest
    static void returnsNullForNoId() {
        System.assertEquals(null, AnalyzeDashboardNative.extractId('no id here'));
        System.assertEquals(null, AnalyzeDashboardNative.extractId(''));
    }

    @isTest
    static void blankInputReturnsError() {
        AnalyzeDashboardNative.Request r = new AnalyzeDashboardNative.Request();
        r.dashboardIdOrUrl = '';
        List<AnalyzeDashboardNative.Response> out = AnalyzeDashboardNative.analyze(
            new List<AnalyzeDashboardNative.Request>{ r }
        );
        System.assertEquals(1, out.size());
        System.assert(out[0].summary.startsWith('ERROR:'), out[0].summary);
    }

    @isTest
    static void unparseableInputReturnsError() {
        AnalyzeDashboardNative.Request r = new AnalyzeDashboardNative.Request();
        r.dashboardIdOrUrl = 'definitely not an id';
        List<AnalyzeDashboardNative.Response> out = AnalyzeDashboardNative.analyze(
            new List<AnalyzeDashboardNative.Request>{ r }
        );
        System.assert(out[0].summary.contains('Could not find a Dashboard Id'), out[0].summary);
    }

    @isTest
    static void nonexistentDashboardReturnsError() {
        // A well-formed but non-existent dashboard id.
        AnalyzeDashboardNative.Request r = new AnalyzeDashboardNative.Request();
        r.dashboardIdOrUrl = '01Z000000000001AAA';
        Test.startTest();
        List<AnalyzeDashboardNative.Response> out = AnalyzeDashboardNative.analyze(
            new List<AnalyzeDashboardNative.Request>{ r }
        );
        Test.stopTest();
        System.assertEquals('01Z000000000001AAA', out[0].dashboardId);
        // No dashboard with this id (or no access) -> graceful error summary.
        System.assert(out[0].summary.startsWith('ERROR:'), out[0].summary);
    }
}
