# Dashboard Analyst Agent

A Salesforce **Agentforce** agent that reads the Lightning dashboard a user is currently viewing and returns a business-analyst-style summary, **Overview / Key KPIs / Trends & Notable Patterns / Recommended Actions**, directly in the chat, in English. The user's only input is a natural-language request such as "Analyze this dashboard." Designed around **Context Engineering** principles (single tool, compressed tool output, just-in-time data retrieval, no long-term memory).

## Status

- Agent `Dashboard_Analyst` (Agent Script / Employee Agent, built with the new builder) is **published and Active (v1)** in org `<YOUR_ORG_ID>`.
- Dashboard values are retrieved via **native Apex (Reports API), zero HTTP callouts**. This is the primary, currently-wired path.
- A legacy, callout-based implementation (Named Credential + Dashboard Results API) exists for reference; see [Two implementations](#two-implementations) below.

## Listing Metadata

- **Industries:** Cross-industry
- **Horizontal Product:** Analytics / Business Intelligence
- **Business Need:** In-chat, natural-language summarization of the Lightning dashboard a user is currently viewing (Overview / KPIs / Trends / Recommended Actions)
- **Requires:** Salesforce org with Agentforce (Agent Script / Employee Agent) enabled; Lightning dashboards with Reports API access
- **Compatible With:** Agentforce Employee Agents; native Apex Reports API (zero-callout path); legacy Named Credential + Dashboard Results API path (reference implementation)
- **Salesforce Editions:** Editions with Agentforce enabled

**App Details**
- Version: v1 (published/Active, see [Status](#status) above)
- Package Contents: Apex classes only, no custom objects or custom tabs
- Languages: English

**Security:** Not applicable, internal agent, not listed on AppExchange.

## Architecture

```
[ User on a Lightning Dashboard ]
            │ "Analyze this dashboard"
            ▼
   [ Agentforce Agent: Dashboard_Analyst ]
   ├─ agent_router, routes the request to a subagent
   ├─ dashboard_analysis, the main subagent; calls the action, then writes the summary
   ├─ off_topic, politely declines out-of-scope requests
   └─ ambiguous_question, asks for clarification when the request is unclear
                                 │
                                 ▼
              [ Apex Action: apex://AnalyzeAnalyticsAssetAction ]
                                 │ (see "Two implementations", the deployed action
                                 │  target can be swapped for AnalyzeDashboardNative)
                                 ▼
              [ Salesforce Reports / Dashboard Results API ]
                                 │ JSON (factMap, groupings, aggregates)
                                 ▼
              [ Apex renders it to a pruned Markdown summary ]
                                 │
                                 ▼
              [ Agent writes the 4-section English summary back to chat ]
```

Context layers, and why each is shaped the way it is:

| Layer | What it holds | Why |
|---|---|---|
| System / subagent instructions | Role, prohibitions, and the fixed 4-section output framework | Stable axis without embedding step-by-step procedures |
| Tool surface | A single action, `analyze_dashboard` | Avoids tool bloat, minimizes the model's choices |
| Tool output | Markdown, pruned (bounded groupings/rows) inside Apex before it ever reaches the model | Protects the attention budget; avoids "lost in the middle" |
| Runtime retrieval | Dashboard Id is pulled from screen/URL context just-in-time | Never preloaded, never stale |
| Short-term memory | `last_summary` variable, scoped to the session | Lets follow-up questions reuse the last fetch instead of re-running the action |
| Long-term memory | None | Stateless by design, there's nothing here that needs to persist across sessions |

Full narrative version: [docs/architecture.md](docs/architecture.md).

## Two implementations

The repo ships two Apex actions that do the same job by different means:

| | [`AnalyzeDashboardNative.cls`](force-app/main/default/classes/AnalyzeDashboardNative.cls) | [`AnalyzeAnalyticsAssetAction.cls`](force-app/main/default/classes/AnalyzeAnalyticsAssetAction.cls) |
|---|---|---|
| Data access | `Reports.ReportManager.runReport()`, native Apex | HTTP callout to the Dashboard Results API via a Named Credential |
| Setup required | None beyond the running user's report access | External Client App + Auth Provider + Named Credential (manual UI setup, see [docs/SETUP-NamedCredential.md](docs/SETUP-NamedCredential.md)) |
| Callouts | 0 | 1+ per analysis |
| Status | Primary / recommended | Reference implementation, kept for comparison |

**Important:** the shipped agent bundle ([`Dashboard_Analyst.agent`](force-app/main/default/aiAuthoringBundles/Dashboard_Analyst/Dashboard_Analyst.agent)) currently targets `apex://AnalyzeAnalyticsAssetAction` (the legacy/callout path), not the native one. If you want the zero-callout behavior live, repoint the action's `target:` to `apex://AnalyzeDashboardNative` and republish, see [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

## Prerequisites

- A Salesforce org with Agentforce / Agent Script (new builder) enabled.
- Salesforce CLI (`sf`) installed and authenticated to the target org.
- The running/agent user needs read access to the dashboards and underlying reports it will be asked to analyze.
- Only if using the legacy `AnalyzeAnalyticsAssetAction` path: an External Client App, Auth Provider, and Named Credential configured per [docs/SETUP-NamedCredential.md](docs/SETUP-NamedCredential.md) (manual UI steps, not deployable via metadata).

## Project structure

```
force-app/main/default/
├── aiAuthoringBundles/Dashboard_Analyst/   # Agent Script source (system prompt, subagents, actions)
├── bots/Dashboard_Analyst/                 # Compiled bot metadata, generated per publish (v1-v4)
├── genAiPlannerBundles/Dashboard_Analyst_v*/ # Compiled planner bundles, generated per publish
├── classes/                                # AnalyzeDashboardNative + AnalyzeAnalyticsAssetAction (+ tests)
├── permissionsets/                         # Analytics_Dashboard_Agent
├── externalClientApps/, extlClntAppOauthSettings/ # Self-callout auth plumbing for the legacy path
└── settings/EinsteinCopilot.settings-meta.xml
docs/            # Architecture, agent spec, build guide, setup guide, requirements
PLAN.md, AGENT.md  # Working notes on scope/history, not Salesforce metadata (see .forceignore)
```

`bots/` and `genAiPlannerBundles/` are **compiled artifacts**, every `sf agent publish authoring-bundle` regenerates them from the `.agent` source. Don't hand-edit them; edit the `.agent` file instead and republish.

## Setup / Deployment

```bash
# 1. Deploy the Apex actions and permission set
sf project deploy start --target-org <alias> \
  --metadata ApexClass:AnalyzeDashboardNative ApexClass:AnalyzeDashboardNativeTest \
             ApexClass:AnalyzeAnalyticsAssetAction ApexClass:AnalyzeAnalyticsAssetActionTest \
             PermissionSet:Analytics_Dashboard_Agent

# 2. Deploy and publish the agent
sf project deploy start --target-org <alias> --metadata AiAuthoringBundle:Dashboard_Analyst
sf agent publish authoring-bundle --json --api-name Dashboard_Analyst
sf agent activate --json --api-name Dashboard_Analyst

# 3. Grant access
sf org assign permset --target-org <alias> --name Analytics_Dashboard_Agent
```

If using the legacy callout path, also complete the manual Named Credential setup ([docs/SETUP-NamedCredential.md](docs/SETUP-NamedCredential.md)) before step 2. Full walkthrough, including the parts of Agentforce setup that can't be captured in metadata (Topic/Action wiring in v62), is in [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

## Configuration

| Setting | Where | Notes |
|---|---|---|
| `language.default_locale` | `Dashboard_Analyst.agent` | `en`, agent replies in English |
| Action target | `Dashboard_Analyst.agent` → `actions.analyze_dashboard.target` | `apex://AnalyzeAnalyticsAssetAction` by default; swap to `apex://AnalyzeDashboardNative` for the zero-callout path |
| `Analytics_Dashboard_Agent` permission set | `force-app/main/default/permissionsets/` | Grants the agent's running user access to the Apex actions |
| Named Credential (`Salesforce_API`) | Setup UI only, not in metadata | Only required for the legacy callout path |

There are no environment variables, all configuration lives in Salesforce metadata/setup.

## Usage

Once published and the user has the permission set:

1. Open any Lightning dashboard.
2. In the Agentforce chat, say "Analyze this dashboard" (or similar).
3. The agent extracts the Dashboard Id from page context (no need to paste a URL unless it can't determine one), runs the action, and replies with:
   - **Overview**, what the dashboard is, what it contains
   - **Key KPIs**, the most important figures, quoted exactly from the data
   - **Trends & Notable Patterns**, highs/lows, zero/empty values, anything unexpected
   - **Recommended Actions**, up to 3 next steps grounded in the data
4. Follow-up questions reuse the last fetched summary (`last_summary`) rather than re-running the action, unless a new dashboard is explicitly requested.

## Testing

```bash
sf apex run test --target-org <alias> \
  --class-names AnalyzeDashboardNativeTest,AnalyzeAnalyticsAssetActionTest \
  --result-format human --synchronous
```

Both Apex actions have unit test coverage (`AnalyzeDashboardNativeTest.cls`, `AnalyzeAnalyticsAssetActionTest.cls`) exercising ordered-component rendering, blank input handling, and rich-text component parsing. There is no automated test coverage for the agent's conversational behavior itself (Agent Script instructions), that's verified manually via `sf agent preview` or in the org.

## Troubleshooting

- **Agent asks for a URL every time**: the running user may lack access to the dashboard, or the page context isn't being passed, see the fallback prompt logic in the `dashboard_analysis` subagent instructions.
- **"Please provide dashboardIdOrUrl or rawPayloadJson"**: the Apex action couldn't extract a Dashboard Id (starts with `01Z`) from the input, normal if the user hasn't opened a dashboard yet.
- **Callout errors on the legacy path**: check the Named Credential / External Credential / Auth Provider setup in [docs/SETUP-NamedCredential.md](docs/SETUP-NamedCredential.md); this whole class of error disappears if you switch to `AnalyzeDashboardNative`.
- **Changes to the `.agent` file aren't showing up**: you must redeploy and re-run `sf agent publish authoring-bundle` (and `sf agent activate` if it's a new version), editing the source alone doesn't affect the live agent.

More detail, including known CLI quirks encountered during the original build, is in [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

## Contributing

This is a single-team internal project; there's no formal contribution process. Open a PR against `main`, make sure both Apex test classes still pass, and if you change agent behavior, update [docs/Dashboard_Analyst-AgentSpec.md](docs/Dashboard_Analyst-AgentSpec.md) to match.

## License

[MIT](LICENSE) © 2026 VurtuoLabs

## Further reading

- [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md), full build/reproduction steps, including manual-only setup
- [docs/Dashboard_Analyst-AgentSpec.md](docs/Dashboard_Analyst-AgentSpec.md), agent design spec and subagent map
- [docs/architecture.md](docs/architecture.md), full context-engineering rationale
- [docs/requirements.md](docs/requirements.md), original requirements
- [PLAN.md](PLAN.md) / [AGENT.md](AGENT.md), working notes
