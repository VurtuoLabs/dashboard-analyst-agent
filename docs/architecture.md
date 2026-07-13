# Architecture & Context Layering

## 1. Runtime Configuration

```
[ User on Lightning Dashboard ]
            │ "Analyze this dashboard"
            ▼
   [ Agentforce Agent ]
   ├ Topic: Dashboard Analysis
   └ Action: Analyze Dashboard ──┐
                                 ▼
              [ Apex: AnalyzeAnalyticsAssetAction ]
                                 │ HTTP via callout:Salesforce_API
                                 ▼
              [ /services/data/v62.0/analytics/dashboards/{id} ]
                                 │ JSON
                                 ▼
              [ markdown summary back to Agent ]
                                 │
                                 ▼
                         [ user's chat ]
```

## 2. Context Layer Design (Context Engineering)

| Layer | What it holds | Why |
|---|---|---|
| System / Topic Instruction | Role, prohibitions, and output framework (KPIs/trends/anomalies/recommendations) | Right altitude (a stable axis, without holding detailed procedures) |
| Tool (Apex Action) | Kept to a single action (`Analyze Dashboard`) | Avoids tool bloat, minimizes choices |
| Tool output (formatted within Apex) | Markdown summary, pruned to `MAX_COMPONENTS=30 / MAX_GROUPINGS=10` | Conserves the attention budget, mitigates the lost-in-the-middle problem |
| Runtime retrieval | The DashboardId is fetched dynamically from the screen context (just-in-time) | Not preloaded, fetched only when needed |
| Short-term memory | The conversation within the same session | Maintains context continuity for follow-up questions |
| Long-term memory | Not needed (for this project) | A stateless design favors simplicity |

## 3. Division of Responsibility on the Apex Side
- **Input normalization**: Extracts the ID from the URL (regex `01Z[a-zA-Z0-9]{12,15}`).
- **API calls**: Calls `/describe` and results in two separate calls (metadata + numeric values).
- **Compaction**: Passing a large dashboard through as-is would easily consume the context window, so the **summary is generated on the Apex side** before being returned.
- **Error path**: Exceptions are gracefully returned as `summary = "ERROR: ..."`, so the agent can explain them in natural language.

## 4. Anti-Patterns and How This Project Addresses Them
| Anti-pattern | This project's approach |
|---|---|
| Stuffing all JSON into the prompt | Converted to markdown and pruned within Apex |
| Tool sprawl | Only a single Action |
| Hardcoded if-else instructions | The Topic Instruction only provides the framework |
| Vague instructions | The output format is fixed via the Instruction |
| Stale context | Just-in-time; fetched fresh every time |

## 5. Deployment Prerequisites
1. The External Client App + Auth Provider + Named Credential require **manual UI configuration** (see Slack Canvas 1-1 through 1-4).
2. Apex / PermissionSet can be deployed via `sf project deploy start`.
3. The Agentforce Topic / Action / Instruction require manual UI configuration (metadata DX support is only partial in v62).
