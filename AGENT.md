# Project: Dashboard Analyst Agent

A project deployed to a Salesforce org that implements "automated Lightning Dashboard analysis via Agentforce." Built around the theme of **Context Engineering** for AI agents.

## Target org
- **Org Id**: `00DWt00000IO7kMMAT`
- **Alias**: `rohto-demo`
- **Username**: `storm.6df4e0cac12e44@salesforce.com`
- **API Version**: 62.0

## Goals (achieved)
1. Agentforce can **read any Lightning Dashboard and summarize its key points and insights in English**.
2. The user simply says "Analyze this dashboard" on the Lightning Dashboard screen.
3. An Apex Invocable Action retrieves the dashboard's `factMap` and returns it as a compact markdown summary.

## Implementation summary (current state)
- The agent `Dashboard_Analyst` (new builder / AiAuthoringBundle, **Employee Agent**, English) is published and **v1 Active**.
- The primary backing implementation is **`AnalyzeDashboardNative`** (native Reports API, zero callouts, no Named Credential required).
- The legacy `AnalyzeAnalyticsAssetAction` (Named Credential approach) is kept for reference.
- Details: [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md), [docs/Dashboard_Analyst-AgentSpec.md](docs/Dashboard_Analyst-AgentSpec.md).

## Directory structure
- `force-app/main/default/classes/`, Apex actions and tests
- `force-app/main/default/permissionsets/`, permissions required for operation
- `force-app/main/default/aiAuthoringBundles/Dashboard_Analyst/`, **the agent itself (.agent / Agent Script)**
- `docs/`, design spec, build guide, requirements, architecture

## Agent / development rules (Context Engineering compliant)
- **Just-in-time**: Large factMaps are truncated on the Apex side to **MAX_REPORTS=25 / MAX_GROUPINGS_PER_REPORT=12** before being passed to the model.
- **Tool-first**: Keep to a single Action (`analyze_dashboard`) to avoid tool bloat.
- **Compact summary**: The Apex side generates a markdown summary; raw JSON is never streamed.
- **Right altitude**: Instructions stay at the business-perspective framework level (Overview / KPIs / Trends / Recommendations).
- **Callout-free**: The primary implementation uses **native `Reports.ReportManager`** (no callouts, no Named Credential required). See `AnalyzeDashboardNative`.

## sf command conventions
- Always use `sf` (`sfdx` is deprecated).
- Include `--target-org <YOUR_ORG_ALIAS>` on every command. `sourceApiVersion` is 67.0 (required for AiAuthoringBundle).

## Deploy / publish
```bash
sf project deploy start --target-org <YOUR_ORG_ALIAS> --metadata ApexClass:AnalyzeDashboardNative ApexClass:AnalyzeDashboardNativeTest PermissionSet:Analytics_Dashboard_Agent
sf project deploy start --target-org <YOUR_ORG_ALIAS> --metadata AiAuthoringBundle:Dashboard_Analyst
sf agent publish authoring-bundle --json --api-name Dashboard_Analyst
sf agent activate --json --api-name Dashboard_Analyst
sf org assign permset --target-org <YOUR_ORG_ALIAS> --name Analytics_Dashboard_Agent
```
