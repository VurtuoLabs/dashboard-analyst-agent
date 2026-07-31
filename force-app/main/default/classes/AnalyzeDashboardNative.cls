/**
 * Invocable Apex action for Agentforce, NATIVE, callout-free dashboard analysis.
 *
 * Unlike AnalyzeAnalyticsAssetAction (which calls the Analytics REST API through
 * a Named Credential / OAuth self-callout), this class uses ONLY native Apex:
 *   - SOQL on Dashboard / DashboardComponent to map a dashboard to its reports
 *   - Reports.ReportManager.runReport(reportId, false) to read each report's
 *     factMap (grand totals + groupings) with ZERO HTTP callouts.
 *
 * This removes ALL manual setup (no External Credential, Auth Provider, browser
 * "Allow" OAuth, or Remote Site Setting). The only requirement is that the
 * running user can run the reports and read the underlying data.
 *
 * Verified in org <YOUR_ORG_ID>: a 12-component dashboard resolved to 6
 * reports and ran with "Number of callouts: 0".
 *
 * Limits to respect: up to 500 synchronous report runs per hour per org. A
 * dashboard with N component-reports consumes N runs per analysis, so this
 * class de-duplicates report ids and caps the number of reports it runs.
 */
public with sharing class AnalyzeDashboardNative {
    @TestVisible
    private static final Integer MAX_REPORTS = 25;
    @TestVisible
    private static final Integer MAX_GROUPINGS_PER_REPORT = 12;

    public class Request {
        @InvocableVariable(
            label='Dashboard Id or URL'
            description='15/18-char Dashboard Id (starts with 01Z), or a full Lightning URL like /lightning/r/Dashboard/{id}/view. This is the dashboard the user is currently viewing.'
            required=true
        )
        public String dashboardIdOrUrl;
    }

    public class Response {
        @InvocableVariable(
            label='Summary'
            description='Markdown summary of the dashboard (name, each component report, grand totals, and top groupings) for the agent to reason on.'
        )
        public String summary;

        @InvocableVariable(label='Dashboard Id' description='Resolved 18-char Dashboard Id.')
        public String dashboardId;

        @InvocableVariable(label='Dashboard Name' description='Dashboard title.')
        public String dashboardName;

        @InvocableVariable(label='Component Count' description='Number of report components found on the dashboard.')
        public Decimal componentCount;
    }

    @InvocableMethod(
        label='Analyze Dashboard (Native)'
        description='Reads the Lightning Dashboard the user is viewing using native Reports Apex (no callout) and returns an AI-friendly markdown summary of its components, totals, and groupings.'
    )
    public static List<Response> analyze(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(handle(req));
        }
        return out;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.componentCount = 0;

        if (req == null || String.isBlank(req.dashboardIdOrUrl)) {
            res.summary = 'ERROR: dashboardIdOrUrl is required. Ask the user which dashboard to analyze, or have them open a dashboard first.';
            return res;
        }

        String dashId = extractId(req.dashboardIdOrUrl);
        if (String.isBlank(dashId)) {
            res.summary = 'ERROR: Could not find a Dashboard Id (01Z...) in input: ' + req.dashboardIdOrUrl;
            return res;
        }
        res.dashboardId = dashId;

        try {
            // 1) Dashboard metadata
            List<Dashboard> dashes = [
                SELECT Id, Title, DeveloperName, FolderName
                FROM Dashboard
                WHERE Id = :dashId
                WITH USER_MODE
                LIMIT 1
            ];
            if (dashes.isEmpty()) {
                res.summary = 'ERROR: No dashboard found with Id ' + dashId + ' (or you lack access to it).';
                return res;
            }
            Dashboard dash = dashes[0];
            res.dashboardName = dash.Title;

            // 2) Components -> reports (preserve order, de-dup report ids)
            List<DashboardComponent> comps = [
                SELECT Id, Name, CustomReportId
                FROM DashboardComponent
                WHERE DashboardId = :dashId AND CustomReportId != NULL
                WITH USER_MODE
            ];
            res.componentCount = comps.size();

            List<Id> orderedReportIds = new List<Id>();
            Set<Id> seen = new Set<Id>();
            for (DashboardComponent c : comps) {
                if (!seen.contains(c.CustomReportId)) {
                    seen.add(c.CustomReportId);
                    orderedReportIds.add(c.CustomReportId);
                }
            }

            // 3) Report names
            Map<Id, Report> reportById = new Map<Id, Report>();
            if (!orderedReportIds.isEmpty()) {
                for (Report r : [
                    SELECT Id, Name FROM Report WHERE Id IN :orderedReportIds WITH USER_MODE
                ]) {
                    reportById.put(r.Id, r);
                }
            }

            StringBuilder sb = new StringBuilder();
            sb.add('# Dashboard: ').add(blankToDash(dash.Title)).add('\n');
            sb.add('Folder: ')
                .add(blankToDash(dash.FolderName))
                .add(' | Components: ')
                .add(String.valueOf(comps.size()))
                .add(' | Distinct reports: ')
                .add(String.valueOf(orderedReportIds.size()))
                .add('\n');

            if (orderedReportIds.isEmpty()) {
                sb.add(
                    '\n(This dashboard has no standard report-backed components, so no numeric data could be read natively.)'
                );
                res.summary = sb.toString();
                return res;
            }

            Integer ran = 0;
            for (Id rid : orderedReportIds) {
                if (ran >= MAX_REPORTS) {
                    sb.add(
                        '\n_...truncated: ' +
                            (orderedReportIds.size() - ran) +
                            ' more reports omitted to stay within limits._\n'
                    );
                    break;
                }
                String rName = reportById.containsKey(rid) ? reportById.get(rid).Name : '(report ' + rid + ')';
                sb.add('\n## ').add(rName).add('\n');
                try {
                    Reports.ReportResults results = Reports.ReportManager.runReport(rid, false);
                    renderReport(sb, results);
                } catch (Exception e) {
                    sb.add('_could not run this report: ' + e.getMessage() + '_\n');
                }
                ran++;
            }

            res.summary = sb.toString();
        } catch (Exception e) {
            res.summary = 'ERROR: ' + e.getTypeName() + ': ' + e.getMessage();
        }
        return res;
    }

    /** Pull the grand total and the down-groupings (capped) from a report's factMap. */
    private static void renderReport(StringBuilder sb, Reports.ReportResults results) {
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        if (factMap == null || factMap.isEmpty()) {
            sb.add('_no data_\n');
            return;
        }

        // Grand total
        Reports.ReportFact grand = factMap.get('T!T');
        if (grand instanceof Reports.ReportFactWithSummaries) {
            sb.add('- Total: ').add(aggLine((Reports.ReportFactWithSummaries) grand)).add('\n');
        }

        // Down groupings (rows)
        List<Reports.GroupingValue> downs = results.getGroupingsDown() != null
            ? results.getGroupingsDown().getGroupings()
            : new List<Reports.GroupingValue>();

        Integer count = 0;
        for (Reports.GroupingValue gv : downs) {
            if (count >= MAX_GROUPINGS_PER_REPORT) {
                sb.add('- _...' + (downs.size() - count) + ' more rows omitted._\n');
                break;
            }
            String key = gv.getKey() + '!T';
            Reports.ReportFact row = factMap.get(key);
            String vals = (row instanceof Reports.ReportFactWithSummaries)
                ? aggLine((Reports.ReportFactWithSummaries) row)
                : '(no value)';
            sb.add('- ').add(blankToDash(gv.getLabel())).add(': ').add(vals).add('\n');
            count++;
        }
    }

    private static String aggLine(Reports.ReportFactWithSummaries fact) {
        List<Reports.SummaryValue> aggs = fact.getAggregates();
        if (aggs == null || aggs.isEmpty())
            return '(no value)';
        List<String> parts = new List<String>();
        for (Reports.SummaryValue sv : aggs) {
            String lbl = sv.getLabel();
            parts.add(String.isBlank(lbl) ? String.valueOf(sv.getValue()) : lbl);
        }
        return String.join(parts, ' | ');
    }

    @TestVisible
    private static String extractId(String input) {
        if (String.isBlank(input))
            return null;
        String s = input.trim();
        Pattern p = Pattern.compile('(01Z[a-zA-Z0-9]{12,15})');
        Matcher m = p.matcher(s);
        if (m.find())
            return m.group(1);
        return null;
    }

    private static String blankToDash(String s) {
        return String.isBlank(s) ? '(none)' : s;
    }

    /** Lightweight StringBuilder, Apex has none natively. */
    private class StringBuilder {
        private List<String> parts = new List<String>();
        public StringBuilder add(String s) {
            if (s != null)
                parts.add(s);
            return this;
        }
        public override String toString() {
            return String.join(parts, '');
        }
    }
}
