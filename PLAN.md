# PLAN / Status

## Done (all automated via CLI, applied to org `<YOUR_ORG_ID>`)
- [x] SFDX project scaffold (`sfdx-project.json` API 67.0, `.forceignore`)
- [x] **Native Apex `AnalyzeDashboardNative`** (Reports API, **zero callouts**) + 6 passing tests
- [x] Legacy Apex `AnalyzeAnalyticsAssetAction` (Named Credential approach, kept for reference) + 4 passing tests
- [x] Permission Set `Analytics_Dashboard_Agent` (access to both Apex classes) → assigned to the running user
- [x] **Agent `Dashboard_Analyst` (new builder / AiAuthoringBundle, Employee Agent, English)**
- [x] validate → deploy → **publish → activate (v1 Active)**
- [x] Verified working via live preview (3 cases: initial analysis / follow-up / no URL)
- [x] Full documentation set ([BUILD-GUIDE](docs/BUILD-GUIDE.md) / [AgentSpec](docs/Dashboard_Analyst-AgentSpec.md) and others)
- [x] Pushed to GitHub

## Parts that can only be done manually (minimal, UI required)
1. **Placing the agent on a Lightning page / Utility Bar** (channel assignment is a UI operation)
   - [Setup] > Agentforce Studio > add `Dashboard Analyst` to the target app (e.g., mass sales activity management), or place the Agentforce component via Lightning App Builder.
2. **Granting permissions to other users** (also possible via CLI: `sf org assign permset --name Analytics_Dashboard_Agent --on-behalf-of <user>`)

> The External Credential / Auth Provider / Named Credential / browser OAuth "allow" steps required by the legacy version are
> **entirely unnecessary now that the native approach has been adopted**.

## Next improvement ideas
- After panel placement, verify and tune via trace whether the Dashboard Id can be picked up from screen context alone, without pasting a URL
- An English-locale instruction variant
- Automated testing via AiEvaluationDefinition (testing-agentforce)
- Comparison and time-series diffing across multiple dashboards
