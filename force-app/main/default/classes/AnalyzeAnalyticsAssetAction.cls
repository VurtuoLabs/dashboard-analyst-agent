public with sharing class AnalyzeAnalyticsAssetAction {
    private static final String API_VERSION = 'v66.0';
    private static final String DEFAULT_NAMED_CREDENTIAL = 'Salesforce_API';
    private static final Integer HTTP_TIMEOUT_MS = 20000;

    public class Request {
        @InvocableVariable(label='Source Mode')
        public String sourceMode;

        @InvocableVariable(label='Dashboard URL or ID')
        public String dashboardIdOrUrl;

        @InvocableVariable(label='Raw Payload JSON')
        public String rawPayloadJson;

        @InvocableVariable(label='Refresh Before Read')
        public Boolean refreshBeforeRead;

        @InvocableVariable(label='Max Rows Per Series')
        public Integer maxRowsPerSeries;

        @InvocableVariable(label='Named Credential')
        public String namedCredential;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Dashboard Title')
        public String dashboardTitle;

        @InvocableVariable(label='Normalized Data Text')
        public String normalizedDataText;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    private class DashboardMarkdownException extends Exception {
    }

    private class Envelope implements Comparable {
        public Integer index;
        public Integer row;
        public Integer column;
        public Map<String, Object> meta = new Map<String, Object>();
        public Map<String, Object> data = new Map<String, Object>();
        public String type;
        public String visualizationType;
        public String title;

        public Integer compareTo(Object otherObj) {
            Envelope other = (Envelope) otherObj;

            Integer myRow = row == null ? 999999 : row;
            Integer otherRow = other.row == null ? 999999 : other.row;
            if (myRow != otherRow) {
                return myRow < otherRow ? -1 : 1;
            }

            Integer myCol = column == null ? 999999 : column;
            Integer otherCol = other.column == null ? 999999 : other.column;
            if (myCol != otherCol) {
                return myCol < otherCol ? -1 : 1;
            }

            Integer myIdx = index == null ? 999999 : index;
            Integer otherIdx = other.index == null ? 999999 : other.index;
            if (myIdx != otherIdx) {
                return myIdx < otherIdx ? -1 : 1;
            }
            return 0;
        }
    }

    private class PathLeaf {
        public String key;
        public String label;
    }

    @InvocableMethod(
        label='Analyze Dashboard as Markdown'
        description='Fetches a standard dashboard and converts it to Markdown in on-screen order'
        callout=true
    )
    public static List<Response> analyze(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            responses.add(processRequest(req));
        }
        return responses;
    }

    private static Response processRequest(Request req) {
        Response res = new Response();
        res.success = false;
        res.dashboardTitle = null;
        res.normalizedDataText = null;
        res.errorMessage = null;

        try {
            Map<String, Object> root = loadDashboardPayload(req);
            if (root.isEmpty()) {
                throw new DashboardMarkdownException('Could not retrieve the dashboard JSON.');
            }

            String markdown = buildMarkdown(root);

            res.success = true;
            res.dashboardTitle = resolveDashboardTitle(root);
            res.normalizedDataText = markdown;
            res.errorMessage = null;
        } catch (Exception e) {
            res.success = false;
            res.dashboardTitle = null;
            res.normalizedDataText = null;
            res.errorMessage = e.getMessage();
            System.debug('AnalyzeAnalyticsAssetAction ERROR: ' + e.getMessage() + ' line=' + e.getLineNumber());
        }

        return res;
    }

    // ============================================================
    // Load payload
    // ============================================================

    private static Map<String, Object> loadDashboardPayload(Request req) {
        if (req != null && !String.isBlank(req.rawPayloadJson)) {
            return safeMap(JSON.deserializeUntyped(req.rawPayloadJson));
        }

        String dashboardId = extractDashboardId(req == null ? null : req.dashboardIdOrUrl);
        if (String.isBlank(dashboardId)) {
            throw new DashboardMarkdownException('Please provide dashboardIdOrUrl or rawPayloadJson.');
        }

        String namedCredential = (req == null || String.isBlank(req.namedCredential))
            ? DEFAULT_NAMED_CREDENTIAL
            : req.namedCredential;

        HttpRequest httpReq = new HttpRequest();
        httpReq.setMethod('GET');
        httpReq.setTimeout(HTTP_TIMEOUT_MS);
        httpReq.setHeader('Accept', 'application/json');
        httpReq.setEndpoint(
            'callout:' +
                namedCredential +
                '/services/data/' +
                API_VERSION +
                '/analytics/dashboards/' +
                EncodingUtil.urlEncode(dashboardId, 'UTF-8')
        );

        Http http = new Http();
        HttpResponse httpRes = http.send(httpReq);

        if (httpRes.getStatusCode() == 301 || httpRes.getStatusCode() == 302) {
            String location = httpRes.getHeader('Location');
            if (!String.isBlank(location)) {
                Integer servicesIdx = location.indexOf('/services/');
                if (servicesIdx >= 0) {
                    httpReq.setEndpoint('callout:' + namedCredential + location.substring(servicesIdx));
                    httpRes = http.send(httpReq);
                }
            }
        }

        if (httpRes.getStatusCode() != 200) {
            throw new DashboardMarkdownException(
                'Dashboard Results API failed. status=' +
                    httpRes.getStatusCode() +
                    ', body=' +
                    abbreviate(httpRes.getBody(), 1000)
            );
        }

        return safeMap(JSON.deserializeUntyped(httpRes.getBody()));
    }

    private static String extractDashboardId(String input) {
        if (String.isBlank(input)) {
            return null;
        }
        Matcher m = Pattern.compile('(01Z[a-zA-Z0-9]{12,15})').matcher(input);
        if (m.find()) {
            return m.group(1);
        }
        return input;
    }

    // ============================================================
    // Markdown build
    // ============================================================

    private static String buildMarkdown(Map<String, Object> root) {
        List<String> sections = new List<String>();
        sections.add('# Dashboard: ' + resolveDashboardTitle(root));

        List<Envelope> envelopes = buildOrderedEnvelopes(root);
        for (Envelope env : envelopes) {
            String block = renderComponent(env);
            if (!String.isBlank(block)) {
                sections.add(block.trim());
            }
        }

        return String.join(sections, '\n\n').trim();
    }

    private static String resolveDashboardTitle(Map<String, Object> root) {
        Map<String, Object> attrs = safeMap(root.get('attributes'));
        String title = firstNonBlankString(attrs, new List<String>{ 'dashboardName', 'name' });
        if (!String.isBlank(title)) {
            return title;
        }

        Map<String, Object> dashboardMetadata = safeMap(root.get('dashboardMetadata'));
        title = firstNonBlankString(dashboardMetadata, new List<String>{ 'name', 'title' });
        if (!String.isBlank(title)) {
            return title;
        }

        return 'Dashboard';
    }

    private static List<Envelope> buildOrderedEnvelopes(Map<String, Object> root) {
        List<Envelope> out = new List<Envelope>();

        Map<String, Object> dashboardMetadata = safeMap(root.get('dashboardMetadata'));
        List<Object> metaComponents = safeList(dashboardMetadata.get('components'));
        List<Object> layoutComponents = safeList(safeMap(dashboardMetadata.get('layout')).get('components'));
        List<Object> componentDataList = safeList(root.get('componentData'));

        Map<String, Map<String, Object>> dataByComponentId = new Map<String, Map<String, Object>>();
        for (Object obj : componentDataList) {
            Map<String, Object> data = safeMap(obj);
            String componentId = getString(data, 'componentId');
            if (!String.isBlank(componentId)) {
                dataByComponentId.put(componentId, data);
            }
        }

        for (Integer i = 0; i < metaComponents.size(); i++) {
            Map<String, Object> meta = safeMap(metaComponents[i]);
            Map<String, Object> layout = (i < layoutComponents.size())
                ? safeMap(layoutComponents[i])
                : new Map<String, Object>();

            Envelope env = new Envelope();
            env.index = i;
            env.row = toInteger(layout.get('row'));
            env.column = toInteger(layout.get('column'));
            env.meta = meta;
            env.type = getString(meta, 'type');
            env.visualizationType = getString(safeMap(meta.get('properties')), 'visualizationType');
            env.title = resolveComponentTitle(meta);
            env.data = resolveComponentData(meta, componentDataList, dataByComponentId);

            out.add(env);
        }

        out.sort();
        return out;
    }

    private static Map<String, Object> resolveComponentData(
        Map<String, Object> meta,
        List<Object> componentDataList,
        Map<String, Map<String, Object>> dataByComponentId
    ) {
        String componentId = getString(meta, 'id');
        if (!String.isBlank(componentId) && dataByComponentId.containsKey(componentId)) {
            return dataByComponentId.get(componentId);
        }

        Integer dataIndex = toInteger(meta.get('componentData'));
        if (dataIndex != null && dataIndex >= 0 && dataIndex < componentDataList.size()) {
            return safeMap(componentDataList[dataIndex]);
        }

        return new Map<String, Object>();
    }

    private static String resolveComponentTitle(Map<String, Object> meta) {
        String title = firstNonBlankString(meta, new List<String>{ 'header', 'title', 'name' });
        if (!String.isBlank(title)) {
            return title;
        }
        return 'Untitled chart';
    }

    private static String renderComponent(Envelope env) {
        if ('Dashboard'.equalsIgnoreCase(env.type) || 'RichText'.equalsIgnoreCase(env.visualizationType)) {
            String richTitle = extractRichTextHeading(env.meta);
            if (String.isBlank(richTitle)) {
                richTitle = env.title;
            }
            if (String.isBlank(richTitle)) {
                return null;
            }
            return '## ' + richTitle;
        }

        String title = env.title;
        if (String.isBlank(title)) {
            title = 'Untitled chart';
        }

        List<String> lines = new List<String>();
        lines.add('## ' + title);

        if (env.data.isEmpty()) {
            lines.add('- No data');
            return String.join(lines, '\n');
        }

        Map<String, Object> status = safeMap(env.data.get('status'));
        String componentDataStatus = getString(status, 'componentDataStatus');
        if ('ERROR'.equalsIgnoreCase(componentDataStatus)) {
            lines.add('- Error: ' + nullToDefault(getString(status, 'errorMessage'), 'Unknown'));
            return String.join(lines, '\n');
        }

        Map<String, Object> reportResult = safeMap(env.data.get('reportResult'));
        if (reportResult.isEmpty()) {
            lines.add('- No data');
            return String.join(lines, '\n');
        }

        List<String> body = renderReportComponent(reportResult, env.meta);
        if (body.isEmpty()) {
            lines.add('- No data');
        } else {
            lines.addAll(body);
        }

        return String.join(lines, '\n');
    }

    // ============================================================
    // Report render
    // ============================================================

    private static List<String> renderReportComponent(Map<String, Object> reportResult, Map<String, Object> meta) {
        List<String> out = new List<String>();

        List<Object> totalRows = safeList(getFact(reportResult, null, null).get('rows'));
        List<Object> groupsDown = safeList(safeMap(reportResult.get('groupingsDown')).get('groupings'));
        List<Object> groupsAcross = safeList(safeMap(reportResult.get('groupingsAcross')).get('groupings'));

        if (!totalRows.isEmpty()) {
            return renderDetailRows(reportResult);
        }

        if (groupsDown.isEmpty() && groupsAcross.isEmpty()) {
            out.add(renderMetricLine(reportResult));
            return out;
        }

        if (!groupsDown.isEmpty() && groupsAcross.isEmpty()) {
            if (isTwoLevel(groupsDown)) {
                String visType = getString(safeMap(meta.get('properties')), 'visualizationType');
                if ('Scatter'.equalsIgnoreCase(visType)) {
                    out.add('- Note: this scatter chart\'s X/Y values cannot be precisely reconstructed via the Dashboard Results API.');
                    out.addAll(renderScatterFallback(reportResult, groupsDown));
                    return out;
                }

                out.addAll(renderTwoLevel(reportResult, meta, groupsDown));
                return out;
            }

            Integer depth = maxDepth(groupsDown);
            if (depth <= 1) {
                return renderSingleLevel(reportResult, groupsDown, false);
            }

            return renderRecursive(reportResult, groupsDown);
        }

        if (groupsDown.isEmpty() && !groupsAcross.isEmpty()) {
            return renderSingleLevel(reportResult, groupsAcross, true);
        }

        return renderMatrix(reportResult, groupsDown, groupsAcross);
    }

    private static String renderMetricLine(Map<String, Object> reportResult) {
        Map<String, Object> totalFact = getFact(reportResult, null, null);
        List<Object> aggs = safeList(totalFact.get('aggregates'));

        if (aggs.isEmpty()) {
            return '- No data';
        }

        if (aggs.size() == 1) {
            return '- Total: ' + formatAggregateValue(reportResult, 0, safeMap(aggs[0]), false);
        }

        List<String> parts = new List<String>();
        for (Integer i = 0; i < aggs.size(); i++) {
            String label = getAggregateLabel(reportResult, i);
            if (String.isBlank(label)) {
                label = 'Value' + String.valueOf(i + 1);
            }
            parts.add(label + '=' + formatAggregateValue(reportResult, i, safeMap(aggs[i]), false));
        }
        return '- Total: ' + String.join(parts, ', ');
    }

    private static List<String> renderDetailRows(Map<String, Object> reportResult) {
        List<String> out = new List<String>();

        Map<String, Object> reportMetadata = safeMap(reportResult.get('reportMetadata'));
        Map<String, Object> ext = safeMap(reportResult.get('reportExtendedMetadata'));
        Map<String, Object> detailColumnInfo = safeMap(ext.get('detailColumnInfo'));

        List<Object> detailColumns = safeList(reportMetadata.get('detailColumns'));
        List<Object> rows = safeList(getFact(reportResult, null, null).get('rows'));

        for (Object rowObj : rows) {
            Map<String, Object> row = safeMap(rowObj);
            List<Object> dataCells = safeList(row.get('dataCells'));
            List<String> parts = new List<String>();

            for (Integer i = 0; i < dataCells.size(); i++) {
                Map<String, Object> cell = safeMap(dataCells[i]);
                String cellValue = firstNonBlankString(cell, new List<String>{ 'label', 'value' });
                if (String.isBlank(cellValue)) {
                    continue;
                }

                String colKey = (i < detailColumns.size() &&
                    detailColumns[i] != null)
                    ? String.valueOf(detailColumns[i])
                    : null;

                String colLabel = null;
                if (!String.isBlank(colKey) && detailColumnInfo.containsKey(colKey)) {
                    colLabel = getString(safeMap(detailColumnInfo.get(colKey)), 'label');
                }
                if (String.isBlank(colLabel)) {
                    colLabel = 'Value';
                }

                parts.add(colLabel + ': ' + cellValue);
            }

            if (!parts.isEmpty()) {
                out.add('- ' + String.join(parts, ', '));
            }
        }

        if (out.isEmpty()) {
            out.add('- No data');
        }
        return out;
    }

    private static List<String> renderSingleLevel(
        Map<String, Object> reportResult,
        List<Object> groups,
        Boolean acrossOnly
    ) {
        List<String> out = new List<String>();
        Boolean hasPositive = false;

        for (Object gObj : groups) {
            Map<String, Object> g = safeMap(gObj);
            Map<String, Object> fact = acrossOnly
                ? getFact(reportResult, null, getString(g, 'key'))
                : getFact(reportResult, getString(g, 'key'), null);

            Decimal v = firstAggregateValue(fact);
            if (v != null && v > 0) {
                hasPositive = true;
                break;
            }
        }

        for (Object gObj : groups) {
            Map<String, Object> g = safeMap(gObj);
            String label = getString(g, 'label');

            Map<String, Object> fact = acrossOnly
                ? getFact(reportResult, null, getString(g, 'key'))
                : getFact(reportResult, getString(g, 'key'), null);

            Decimal v = firstAggregateValue(fact);

            if ((String.isBlank(label) || '-'.equals(label)) && (v == null || v == 0)) {
                continue;
            }
            if (hasPositive && v != null && v == 0) {
                continue;
            }

            out.add('- ' + displayLabel(label) + ': ' + renderFactSingleValue(reportResult, fact));
        }

        if (out.isEmpty()) {
            out.add('- No data');
        }
        return out;
    }

    private static List<String> renderTwoLevel(
        Map<String, Object> reportResult,
        Map<String, Object> meta,
        List<Object> parentGroups
    ) {
        List<String> out = new List<String>();
        Map<String, Object> ext = safeMap(reportResult.get('reportExtendedMetadata'));
        String groupByType = getString(
            safeMap(safeMap(meta.get('properties')).get('visualizationProperties')),
            'groupByType'
        );
        String childGroupingLabel = getGroupingLabelByLevel(ext, 1);

        Boolean showPct = false;
        if (!String.isBlank(groupByType) && groupByType.toLowerCase().contains('stacked100')) {
            showPct = true;
        } else if ('ステータス'.equals(childGroupingLabel)) {
            showPct = true;
        }

        for (Object pObj : parentGroups) {
            Map<String, Object> parent = safeMap(pObj);
            String parentLabel = getString(parent, 'label');
            String parentKey = getString(parent, 'key');

            Map<String, Object> parentFact = getFact(reportResult, parentKey, null);
            Decimal parentTotal = firstAggregateValue(parentFact);

            if ((String.isBlank(parentLabel) || '-'.equals(parentLabel)) && (parentTotal == null || parentTotal == 0)) {
                continue;
            }

            List<Object> childGroups = safeList(parent.get('groupings'));
            Boolean childHasPositive = false;
            for (Object cObjCheck : childGroups) {
                Map<String, Object> childCheck = safeMap(cObjCheck);
                Decimal childValCheck = firstAggregateValue(getFact(reportResult, getString(childCheck, 'key'), null));
                if (childValCheck != null && childValCheck > 0) {
                    childHasPositive = true;
                    break;
                }
            }

            List<String> parts = new List<String>();
            for (Object cObj : childGroups) {
                Map<String, Object> child = safeMap(cObj);
                String childLabel = getString(child, 'label');
                String childKey = getString(child, 'key');

                Map<String, Object> childFact = getFact(reportResult, childKey, null);
                Decimal childVal = firstAggregateValue(childFact);

                if ((String.isBlank(childLabel) || '-'.equals(childLabel)) && (childVal == null || childVal == 0)) {
                    continue;
                }
                if (childHasPositive && childVal != null && childVal == 0) {
                    continue;
                }

                String childValueText = renderFactSingleValue(reportResult, childFact);
                if (showPct && childVal != null && parentTotal != null && parentTotal != 0) {
                    Decimal pct = (childVal * 100) / parentTotal;
                    parts.add(displayLabel(childLabel) + '=' + childValueText + ' (' + formatPercent(pct) + ')');
                } else {
                    parts.add(displayLabel(childLabel) + '=' + childValueText);
                }
            }

            if (!parts.isEmpty()) {
                out.add('- ' + displayLabel(parentLabel) + ': ' + String.join(parts, ', '));
            }
        }

        if (out.isEmpty()) {
            out.add('- No data');
        }
        return out;
    }

    private static List<String> renderScatterFallback(Map<String, Object> reportResult, List<Object> groupsDown) {
        List<String> out = new List<String>();

        for (Object gObj : groupsDown) {
            Map<String, Object> g = safeMap(gObj);
            String label = displayLabel(getString(g, 'label'));
            Map<String, Object> fact = getFact(reportResult, getString(g, 'key'), null);
            List<Object> aggs = safeList(fact.get('aggregates'));

            List<String> parts = new List<String>();
            for (Integer i = 0; i < aggs.size(); i++) {
                parts.add(
                    'Value' + String.valueOf(i + 1) + '=' + formatAggregateValue(reportResult, i, safeMap(aggs[i]), false)
                );
            }

            out.add('- ' + label + ': ' + String.join(parts, ', '));
        }

        if (out.isEmpty()) {
            out.add('- No data');
        }
        return out;
    }

    private static List<String> renderRecursive(Map<String, Object> reportResult, List<Object> groupsDown) {
        List<String> out = new List<String>();
        appendRecursiveLines(out, reportResult, groupsDown, 0);

        if (out.isEmpty()) {
            out.add('- No data');
        }
        return out;
    }

    private static void appendRecursiveLines(
        List<String> out,
        Map<String, Object> reportResult,
        List<Object> groups,
        Integer depth
    ) {
        for (Object gObj : groups) {
            Map<String, Object> g = safeMap(gObj);
            String label = displayLabel(getString(g, 'label'));
            String key = getString(g, 'key');
            List<Object> children = safeList(g.get('groupings'));

            if (children.isEmpty()) {
                out.add(
                    indent(depth) +
                        '- ' +
                        label +
                        ': ' +
                        renderFactSingleValue(reportResult, getFact(reportResult, key, null))
                );
            } else {
                out.add(indent(depth) + '- ' + label);
                appendRecursiveLines(out, reportResult, children, depth + 1);
            }
        }
    }

    private static List<String> renderMatrix(
        Map<String, Object> reportResult,
        List<Object> downGroups,
        List<Object> acrossGroups
    ) {
        List<String> out = new List<String>();

        List<PathLeaf> rowLeaves = flattenLeaves(downGroups, null);
        List<PathLeaf> colLeaves = flattenLeaves(acrossGroups, null);

        if (rowLeaves.isEmpty() || colLeaves.isEmpty()) {
            out.add('- No data');
            return out;
        }

        List<String> header = new List<String>();
        header.add('Item');
        for (PathLeaf colLeaf : colLeaves) {
            header.add(escapeTableCell(colLeaf.label));
        }

        List<String> separators = new List<String>();
        for (Integer i = 0; i < header.size(); i++) {
            separators.add('---');
        }

        out.add('| ' + String.join(header, ' | ') + ' |');
        out.add('| ' + String.join(separators, ' | ') + ' |');

        for (PathLeaf rowLeaf : rowLeaves) {
            List<String> cells = new List<String>();
            cells.add(escapeTableCell(rowLeaf.label));

            for (PathLeaf colLeaf : colLeaves) {
                Map<String, Object> fact = getFact(reportResult, rowLeaf.key, colLeaf.key);
                cells.add(escapeTableCell(renderFactSingleValue(reportResult, fact)));
            }

            out.add('| ' + String.join(cells, ' | ') + ' |');
        }

        return out;
    }

    private static List<PathLeaf> flattenLeaves(List<Object> groups, String currentPath) {
        List<PathLeaf> out = new List<PathLeaf>();

        for (Object obj : groups) {
            Map<String, Object> g = safeMap(obj);
            String label = displayLabel(getString(g, 'label'));
            String path = String.isBlank(currentPath) ? label : currentPath + ' > ' + label;

            List<Object> children = safeList(g.get('groupings'));
            if (children.isEmpty()) {
                PathLeaf leaf = new PathLeaf();
                leaf.key = getString(g, 'key');
                leaf.label = path;
                out.add(leaf);
            } else {
                out.addAll(flattenLeaves(children, path));
            }
        }

        return out;
    }

    private static Boolean isTwoLevel(List<Object> groupsDown) {
        if (groupsDown.isEmpty()) {
            return false;
        }

        for (Object gObj : groupsDown) {
            Map<String, Object> g = safeMap(gObj);
            List<Object> children = safeList(g.get('groupings'));
            if (children.isEmpty()) {
                return false;
            }
            for (Object cObj : children) {
                if (!safeList(safeMap(cObj).get('groupings')).isEmpty()) {
                    return false;
                }
            }
        }
        return true;
    }

    private static Integer maxDepth(List<Object> groups) {
        Integer maxDepth = 0;

        for (Object gObj : groups) {
            Map<String, Object> g = safeMap(gObj);
            List<Object> children = safeList(g.get('groupings'));
            if (children.isEmpty()) {
                maxDepth = Math.max(maxDepth, 1);
            } else {
                maxDepth = Math.max(maxDepth, 1 + maxDepth(children));
            }
        }

        return maxDepth;
    }

    // ============================================================
    // Facts / labels / formatting
    // ============================================================

    private static Map<String, Object> getFact(Map<String, Object> reportResult, String downKey, String acrossKey) {
        String dk = String.isBlank(downKey) ? 'T' : downKey;
        String ak = String.isBlank(acrossKey) ? 'T' : acrossKey;
        return safeMap(safeMap(reportResult.get('factMap')).get(dk + '!' + ak));
    }

    private static Decimal firstAggregateValue(Map<String, Object> fact) {
        List<Object> aggs = safeList(fact.get('aggregates'));
        if (aggs.isEmpty()) {
            return null;
        }
        return toDecimal(safeMap(aggs[0]).get('value'));
    }

    private static String renderFactSingleValue(Map<String, Object> reportResult, Map<String, Object> fact) {
        List<Object> aggs = safeList(fact.get('aggregates'));
        if (aggs.isEmpty()) {
            return '-';
        }
        return formatAggregateValue(reportResult, 0, safeMap(aggs[0]), false);
    }

    private static String formatAggregateValue(
        Map<String, Object> reportResult,
        Integer idx,
        Map<String, Object> agg,
        Boolean keepPercentSign
    ) {
        Decimal v = toDecimal(agg.get('value'));
        if (v == null) {
            String label = getString(agg, 'label');
            if (String.isBlank(label)) {
                return '-';
            }
            return keepPercentSign ? label : label.replace('%', '');
        }

        String dataType = getAggregateDataType(reportResult, idx);
        if ('percent'.equalsIgnoreCase(dataType) && keepPercentSign) {
            return formatPercent(v);
        }
        return formatNumber(v);
    }

    private static String getAggregateDataType(Map<String, Object> reportResult, Integer idx) {
        if (reportResult == null) {
            return null;
        }

        Map<String, Object> reportMetadata = safeMap(reportResult.get('reportMetadata'));
        Map<String, Object> ext = safeMap(reportResult.get('reportExtendedMetadata'));
        Map<String, Object> aggregateColumnInfo = safeMap(ext.get('aggregateColumnInfo'));
        List<Object> aggs = safeList(reportMetadata.get('aggregates'));

        if (idx == null || idx < 0 || idx >= aggs.size()) {
            return null;
        }

        String aggKey = getAggregateKeyAt(aggs, idx);
        if (!String.isBlank(aggKey) && aggregateColumnInfo.containsKey(aggKey)) {
            return getString(safeMap(aggregateColumnInfo.get(aggKey)), 'dataType');
        }
        return null;
    }

    private static String getAggregateLabel(Map<String, Object> reportResult, Integer idx) {
        if (reportResult == null) {
            return null;
        }

        Map<String, Object> reportMetadata = safeMap(reportResult.get('reportMetadata'));
        Map<String, Object> ext = safeMap(reportResult.get('reportExtendedMetadata'));
        Map<String, Object> aggregateColumnInfo = safeMap(ext.get('aggregateColumnInfo'));
        List<Object> aggs = safeList(reportMetadata.get('aggregates'));

        if (idx == null || idx < 0 || idx >= aggs.size()) {
            return null;
        }

        String aggKey = getAggregateKeyAt(aggs, idx);
        if (!String.isBlank(aggKey) && aggregateColumnInfo.containsKey(aggKey)) {
            String label = getString(safeMap(aggregateColumnInfo.get(aggKey)), 'label');
            if (!String.isBlank(label)) {
                label = label.replace(' 合計:', '').replace('合計:', '').replace(':', '').trim();
                if (
                    '数値'.equals(label) ||
                    '数値(小数点)'.equals(label) ||
                    'パーセント'.equals(label) ||
                    'レコード件数'.equals(label)
                ) {
                    return null;
                }
                return label;
            }
        }
        return null;
    }

    private static String getAggregateKeyAt(List<Object> aggs, Integer idx) {
        if (idx == null || idx < 0 || idx >= aggs.size()) {
            return null;
        }

        Object one = aggs[idx];
        if (one instanceof String) {
            return (String) one;
        }
        return getString(safeMap(one), 'name');
    }

    private static String getGroupingLabelByLevel(Map<String, Object> ext, Integer level) {
        Map<String, Object> groupingColumnInfo = safeMap(ext.get('groupingColumnInfo'));
        for (Object one : groupingColumnInfo.values()) {
            Map<String, Object> info = safeMap(one);
            Integer gl = toInteger(info.get('groupingLevel'));
            if (gl == level) {
                return getString(info, 'label');
            }
        }
        return null;
    }

    private static String displayLabel(String raw) {
        if (String.isBlank(raw) || '-'.equals(raw)) {
            return 'Unset';
        }
        return raw;
    }

    private static String extractRichTextHeading(Map<String, Object> meta) {
        Map<String, Object> props = safeMap(meta.get('properties'));
        Map<String, Object> content = safeMap(props.get('content'));
        String raw = getString(content, 'richTextContent');

        if (String.isBlank(raw)) {
            return resolveComponentTitle(meta);
        }

        try {
            Object richObj = JSON.deserializeUntyped(raw);
            List<String> inserts = new List<String>();
            collectRichTextInserts(richObj, inserts);
            String plain = String.join(inserts, '');
            for (String line : plain.split('\n')) {
                if (!String.isBlank(line)) {
                    return line.trim();
                }
            }
        } catch (Exception ignoreEx) {
        }

        return resolveComponentTitle(meta);
    }

    private static void collectRichTextInserts(Object node, List<String> inserts) {
        if (node == null) {
            return;
        }

        if (node instanceof List<Object>) {
            for (Object child : (List<Object>) node) {
                collectRichTextInserts(child, inserts);
            }
            return;
        }

        if (node instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) node;
            if (m.containsKey('insert') && m.get('insert') != null) {
                inserts.add(String.valueOf(m.get('insert')));
            }
            for (String key : m.keySet()) {
                if (key != 'insert') {
                    collectRichTextInserts(m.get(key), inserts);
                }
            }
        }
    }

    private static String formatPercent(Decimal value) {
        if (value == null) {
            return '-';
        }
        return String.valueOf(value.setScale(1, System.RoundingMode.HALF_UP)) + '%';
    }

    private static String formatNumber(Decimal value) {
        if (value == null) {
            return '-';
        }

        String s = String.valueOf(value.setScale(4, System.RoundingMode.HALF_UP));
        if (s.contains('.')) {
            while (s.endsWith('0')) {
                s = s.substring(0, s.length() - 1);
            }
            if (s.endsWith('.')) {
                s = s.substring(0, s.length() - 1);
            }
        }
        return s;
    }

    private static String escapeTableCell(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('|', '\\|').replace('\r\n', '<br>').replace('\n', '<br>').replace('\r', '<br>');
    }

    private static String indent(Integer depth) {
        Integer d = depth == null ? 0 : depth;
        String s = '';
        for (Integer i = 0; i < d; i++) {
            s += '  ';
        }
        return s;
    }

    // ============================================================
    // Generic helpers
    // ============================================================

    private static String nullToDefault(String value, String defaultValue) {
        return String.isBlank(value) ? defaultValue : value;
    }

    private static String abbreviate(String value, Integer maxLen) {
        if (value == null || maxLen == null || value.length() <= maxLen) {
            return value;
        }
        return value.substring(0, maxLen) + '...';
    }

    private static String firstNonBlankString(Map<String, Object> mapNode, List<String> keys) {
        if (mapNode == null || keys == null) {
            return null;
        }

        for (String key : keys) {
            if (mapNode.containsKey(key) && mapNode.get(key) != null) {
                String v = String.valueOf(mapNode.get(key));
                if (!String.isBlank(v)) {
                    return v;
                }
            }
        }
        return null;
    }

    private static String getString(Map<String, Object> m, String key) {
        return (m == null || !m.containsKey(key) || m.get(key) == null) ? null : String.valueOf(m.get(key));
    }

    private static Integer toInteger(Object value) {
        if (value == null) {
            return null;
        }

        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            Decimal d = toDecimal(value);
            if (d == null) {
                return null;
            }
            return Integer.valueOf(String.valueOf(d.setScale(0, System.RoundingMode.HALF_UP)));
        }
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf(String.valueOf((Integer) value));
        }
        if (value instanceof Long) {
            return Decimal.valueOf(String.valueOf((Long) value));
        }
        if (value instanceof Double) {
            return Decimal.valueOf(String.valueOf((Double) value));
        }

        try {
            return Decimal.valueOf(String.valueOf(value).replace(',', '').replace('%', ''));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<String, Object> safeMap(Object obj) {
        return obj instanceof Map<String, Object> ? (Map<String, Object>) obj : new Map<String, Object>();
    }

    private static List<Object> safeList(Object obj) {
        return obj instanceof List<Object> ? (List<Object>) obj : new List<Object>();
    }
}
