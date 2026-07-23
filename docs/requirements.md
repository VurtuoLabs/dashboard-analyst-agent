# Requirements, Analytics × Agentforce "AI Dashboard Analysis"

Reference: Slack Canvas `F0AVAP1BMTP` (Build guide for "AI Dashboard Analysis" powered by the Analytics API × Agentforce)

## 1. Use Case
While a user has a Lightning Dashboard open and enters "Analyze this dashboard." into Agentforce, the agent retrieves the DashboardId from the screen context, calls the Analytics API via Apex, and returns a summary and analysis of its contents (components, key figures, groupings).

## 2. Components
| Category | Name | Role |
|---|---|---|
| External Credential | `Self Callout` | OAuth 2.0 (self-callout to the org's own environment) |
| Auth Provider | `Self Auth` | Consumer Key/Secret + scope `api refresh_token` |
| Named Credential | `Salesforce_API` | Endpoint = the org's own my.salesforce.com / Auth Protocol = OAuth 2.0 |
| Apex | `AnalyzeAnalyticsAssetAction` | Invocable. Takes a Dashboard Id/URL and returns a summary in markdown |
| Permission Set | `Analytics_Dashboard_Agent` | Grants access to the Apex class |
| Agentforce Topic | `Dashboard Analysis` | Framed via the Instruction |
| Agent Action | `Analyze Dashboard` | References the Apex action, requests `dashboardIdOrUrl` from the user |

## 3. Authentication Flow (manual configuration, one-time only)
Follow Slack Canvas steps 1-1 through 1-4 exactly as documented:
1. Create the **External Client App** `Self Callout`, enable OAuth, set scope = `api`, `refresh_token offline_access`, and note down the Consumer Key/Secret.
2. Create the **Auth. Provider** `Self Auth` with type Salesforce. **Be sure to enter `api refresh_token` in Default Scopes, separated by a single space** (omitting this causes `invalid_scope`). Note down the Callback URL.
3. **Overwrite** the External Client App's Callback URL with the Callback URL obtained in step 2.
4. Create the **Named Credential** `Salesforce_API` in Legacy format. URL = the org's own my.salesforce.com, Auth Provider = `Self Auth`, Scope left blank; the authentication flow starts on save → Allow → success once it shows "Authenticated."
   - ⚠ Make sure your browser's pop-up blocker is disabled.

## 4. Acceptance Criteria
- Apex Test coverage ≥ 75%.
- When "Analyze this dashboard." is entered on a Lightning Dashboard screen, Agentforce returns a summary along with at least one insight (e.g., maximum value, imbalance, recommended action).
- If the input Id is invalid or not contained in the URL, the agent explains this gracefully.

## 5. Out of Scope (for this phase)
- Analysis of CRM Analytics / Lens (Reports & Dashboards REST API only).
- Editing or auto-refreshing dashboards.
- Cross-org analysis.
